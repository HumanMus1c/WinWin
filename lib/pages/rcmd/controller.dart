import 'package:winwin/common/widgets/video_card/video_card_adapter.dart';
import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/core/log/app_logger.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/video.dart';
import 'package:winwin/models/video/rec_video_item.dart';
import 'package:winwin/pages/common/common_list_controller.dart';
import 'package:winwin/plugin/api/plugin_manager.dart';
import 'package:winwin/plugin/builtin/feed_filter/feed_filter_plugin.dart';
import 'package:winwin/plugin/builtin/feed_filter/feed_filter_policy.dart';
import 'package:winwin/plugin/builtin/home_feed_anonymizer/home_feed_anonymizer_plugin.dart';
import 'package:winwin/plugin/rules/rule_plugin_manager.dart';
import 'package:winwin/services/video_card_meta_service.dart';
import 'package:winwin/utils/viewport_load_budget.dart';

class RcmdController extends CommonListController {
  // Simplified from Pref.enableSaveLastData; keeps last data on error/refresh.
  late bool enableSaveLastData = true;

  /// Web 推荐流单页条数。
  static const int _webPageSize = 20;

  /// 最近一次成功的数据源是否为 Web 流（仅用于估算补货批大小）。
  ///
  /// 数据源不再「首屏定死」：每次拉取都按「登录态 Web → 匿名 Web → App」
  /// 依次尝试。Web 流单次列表请求即带 `pubdate/stat.like`，App 流没有点赞
  /// 字段，只能整页补详情；一次 Web 失败不再让整个会话都落到 App 流。
  bool _lastSourceWeb = true;

  int? lastRefreshAt;
  late bool savedRcmdTip = true;

  /// 刷新合并时旧内容保留的上限；下滚追加不再裁剪头部（与上游一致，
  /// 避免裁头导致滚动偏移回缩、在底部反复触发加载）。
  static const int _maxItems = 300;

  /// 单次补货并发拉取的批次数上限。
  ///
  /// 实测（2026-10-26 登录态连续探测 31 批）：服务端在同一会话内会大量回送
  /// 刚发过的卡片，单批 8 条去重后常常只剩 0~3 条，而每批要 800ms 左右，
  /// 串行追平的观感就是「新内容一张一张往外蹦」。并发多批可在同一时间窗
  /// 内拿到数倍有效条目，合并后一次性提交，用户看到的是成块新增。
  ///
  /// 批次数按视口预算收敛（2026-10-27）：只补足「一屏」的额度，
  /// 小窗口下自动降到 1~2 批，避免一次拉回远超视口的内容。
  static const int _maxPrefetchBatches = 4;

  /// App 推荐接口单批原始条数的保守估计（去重后通常更少）。
  static const int _assumedBatchSize = 8;

  /// 当前数据源单批目标条数：Web 流按 [ps] 返回，App 流按保守估计。
  int get _batchSize => _lastSourceWeb ? _webPageSize : _assumedBatchSize;

  /// 推荐流网格：单行高度（卡片信息区 100 + 间距 8）与单卡宽度上限。
  static const double _gridRowExtent = 108;
  static const double _gridMaxCrossAxisExtent = 240;

  // Endless feed: never mark as ended.
  @override
  bool get isEnd => false;

  @override
  void onInit() {
    super.onInit();
    page = 0;
    queryData();
  }

  @override
  Future<LoadingState> customGetData() async {
    // main() kicks this off without awaiting so the window can render;
    // wait for storage/accounts/Dio before the first request goes out.
    await ensureBootstrap();
    return _fetchPage(page);
  }

  /// 拉取单页推荐：登录态 Web → 匿名 Web → App，三级回退。
  ///
  /// 登录态 Web 流可能因风控/超时偶发失败；匿名 Web 流仍带 `pubdate` 与
  /// `stat.like`，优先于 App 流。只有两者都失败才回退 App，并在返回前整页
  /// 批量补全详情，避免卡片渲染后点赞逐张回填。
  Future<LoadingState<List<BaseRcmdVideoItemModel>>> _fetchPage(int idx) async {
    final web = await VideoHttp.rcmdVideoList(
      freshIdx: idx,
      ps: _webPageSize,
      // 「初见推荐」插件：Web 推荐流不带登录 Cookie。
      anonymous: HomeFeedAnonymizerPlugin.active,
    );
    if (web case Success(:final response)) {
      _lastSourceWeb = true;
      return Success(_applyPlugins(_toBaseList(response)));
    }

    AppLogger.w('Rcmd', 'web feed idx=$idx failed: ${web is Error ? web.errMsg : web}');

    final anonWeb = await VideoHttp.rcmdVideoList(
      freshIdx: idx,
      ps: _webPageSize,
      anonymous: true,
    );
    if (anonWeb case Success(:final response)) {
      AppLogger.w('Rcmd', 'web feed idx=$idx recovered by anonymous account');
      _lastSourceWeb = true;
      return Success(_applyPlugins(_toBaseList(response)));
    }

    final app = await VideoHttp.rcmdVideoListApp(freshIdx: idx);
    if (app case Success(:final response)) {
      AppLogger.w(
        'Rcmd',
        'web+anonymous failed, fallback app feed idx=$idx '
        '(anonymous error: ${anonWeb is Error ? anonWeb.errMsg : anonWeb})',
      );
      _lastSourceWeb = false;
      final list = _applyPlugins(_toBaseList(response));
      await VideoCardMetaService.prefetch(
        list.map((item) => VideoCardData.from(item)),
      );
      return Success(list);
    }

    // 全部失败：优先透出登录态 Web 的错误信息（更贴近用户实际网络）。
    if (web is Error) return Error(web.errMsg, code: web.code);
    if (anonWeb is Error) return Error(anonWeb.errMsg, code: anonWeb.code);
    if (app is Error) return Error(app.errMsg, code: app.code);
    return const Error('推荐流加载失败');
  }

  /// 统一装箱为基类列表：Web / App 两类模型的运行时类型不同，
  /// 固定基类容器后，刷新合并与下滚追加都不会再因泛型不匹配抛 TypeError。
  static List<BaseRcmdVideoItemModel> _toBaseList(
    Iterable<BaseRcmdVideoItemModel> items,
  ) =>
      <BaseRcmdVideoItemModel>[...items];

  /// 插件过滤：内置「推荐流过滤」→ 外部 JSON 规则插件。
  ///
  /// 过滤器在每批数据进入去重/合并前执行，避免被过滤的卡片先渲染再消失。
  static List<BaseRcmdVideoItemModel> _applyPlugins(
    List<BaseRcmdVideoItemModel> items,
  ) {
    var result = items;

    final feedFilter = PluginManager.maybeInstance?.find<FeedFilterPlugin>();
    if (feedFilter != null && PluginManager.enabled(FeedFilterPlugin.pluginId)) {
      result = [
        for (final item in result)
          if (feedFilter.shouldShow(item, kind: FeedKind.recommend)) item,
      ];
    }

    final rules = RulePluginManager.maybeInstance;
    if (rules != null) {
      result = rules.filterFeed(result);
    }
    return result;
  }

  /// 条目唯一键：App 接口的 av 卡由 aid 反推 bvid；其余卡片（直播/番剧等）
  /// 用 goto + param 区分，避免跨类型撞号。
  static String? _keyOf(Object? item) {
    if (item is! BaseRcmdVideoItemModel) return null;
    final bvid = item.bvid;
    if (bvid != null && bvid.isNotEmpty) return bvid;
    if (item.param != null) return '${item.goto}:${item.param}';
    return null;
  }

  /// 按 [_keyOf] 去重追加，[limit] 为合并后目标列表的总条数上限。
  static void _addUnique(
    List<dynamic> target,
    Set<String> seen,
    Iterable<dynamic> items, {
    int limit = _maxItems,
  }) {
    for (final item in items) {
      if (target.length >= limit) return;
      final key = _keyOf(item);
      if (key == null || seen.add(key)) target.add(item);
    }
  }

  @override
  bool handleError(String? errMsg) {
    if (!enableSaveLastData) return false;
    // Keep stale cards visible when a refresh fails, but surface the
    // error/retry UI when the very first load fails (no data to keep).
    return switch (loadingState.value) {
      Success(:final response) => response != null && response.isNotEmpty,
      _ => false,
    };
  }

  @override
  void handleListResponse(List dataList) {
    // 只在刷新（page == 0）时把旧数据接在新批次下面，用户不至于丢失
    // 尚未看完的内容；下滚追加改由 [onLoadMore] 自行合并提交。
    if (!enableSaveLastData || page != 0) return;
    if (loadingState.value case Success(:final response)) {
      final old = response;
      if (old == null || old.isEmpty) {
        lastRefreshAt = null;
        return;
      }
      // 新批次在前、旧数据在后，按条目键全局去重：否则新批次已有的卡片
      // 会被旧列表重复追加（与评论分页重复加载同类问题）。
      final seen = <String>{};
      final merged = <dynamic>[];
      _addUnique(merged, seen, dataList);
      final newCount = merged.length;
      _addUnique(merged, seen, old);
      // `dataList` 已由 `_fetchPage` 统一装箱为基类列表；仍逐条 `add`，
      // 避免将来改回具体模型列表时再次踩 `addAll` 的迭代器泛型校验坑。
      dataList.clear();
      for (final item in merged) {
        dataList.add(item);
      }
      if (savedRcmdTip && newCount < dataList.length) {
        lastRefreshAt = newCount;
      }
    }
  }

  /// 并发补货：一次拉取多批，去重后一次性追加、只刷新一次 UI。
  @override
  Future<void> onLoadMore() async {
    if (isLoading) return;
    if (loadingState.value case Success(:final response)) {
      final list = response;
      if (list == null) return;
      isLoading = true;
      try {
        var nextIdx = page;
        // 列表与追加项统一为基类集合，Web / App 混合追加不会触发泛型校验。
        final added = <BaseRcmdVideoItemModel>[];
        // 服务端偶发整轮都只回送已看过的卡片（实测连续 7 批新增 0~1 条），
        // 空手而归时再补一轮，避免滚到底毫无反应。两轮合计仍受
        // [_maxPrefetchBatches] 封顶，不会因重试放大拉取量。
        var batchesLeft = _maxPrefetchBatches;
        for (var round = 0; round < 2 && added.isEmpty && batchesLeft > 0; round++) {
          final count = _prefetchBatchCount < batchesLeft
              ? _prefetchBatchCount
              : batchesLeft;
          final batches = await Future.wait([
            for (var i = 0; i < count; i++) _fetchBatch(nextIdx + i),
          ]);
          nextIdx += count;
          batchesLeft -= count;

          final seen = <String>{};
          for (final item in list) {
            final key = _keyOf(item);
            if (key != null) seen.add(key);
          }
          for (final batch in batches) {
            for (final item in batch) {
              final key = _keyOf(item);
              if (key == null || seen.add(key)) added.add(item);
            }
          }
        }
        page = nextIdx;
        // 两轮都被去重掉时不刷新 UI，避免空重建。
        if (added.isEmpty) return;
        // 列表与 `added` 均已是基类集合；沿用逐条 `add`，只按元素实例校验，
        // 不依赖迭代器泛型，后续再换数据源也不会重演泛型 TypeError。
        for (final item in added) {
          list.add(item);
        }
        loadingState.refresh();
      } finally {
        isLoading = false;
        await flushPendingRefresh();
      }
    }
  }

  /// 当前视口可容纳的推荐卡片数（扣除滚动区上下留白 220）。
  int get _viewportCardCapacity {
    final extent = ViewportLoadBudget.viewportExtentOf(scrollController) - 220;
    final width = ViewportLoadBudget.windowLogicalWidth - 104; // 侧栏 80 + 页边 24
    return ViewportLoadBudget.visibleGridItems(
      viewportExtent: extent > 0 ? extent : 1,
      viewportWidth: width > 0 ? width : _gridMaxCrossAxisExtent,
      rowExtent: _gridRowExtent,
      maxCrossAxisExtent: _gridMaxCrossAxisExtent,
    );
  }

  /// 本轮补货批次数：只补足「一屏」额度，最多 [_maxPrefetchBatches]。
  int get _prefetchBatchCount {
    final target = ViewportLoadBudget.capRequestItems(
      fallback: _maxPrefetchBatches * _batchSize,
      visibleItems: _viewportCardCapacity,
      firstPage: false,
    );
    final count = (target / _batchSize).ceil();
    if (count < 1) return 1;
    return count > _maxPrefetchBatches ? _maxPrefetchBatches : count;
  }

  Future<List<BaseRcmdVideoItemModel>> _fetchBatch(int idx) async {
    await ensureBootstrap();
    try {
      final res = await _fetchPage(idx);
      if (res case Success(:final response)) return response;
    } catch (_) {
      // 追加失败不打断当前列表，下一次滚动会重试。
    }
    return const [];
  }

  @override
  Future<void> onRefresh() async {
    // 在途请求未收尾时登记补发：既不丢下拉刷新，也不再轮询阻塞指示器。
    if (isLoading) return deferRefresh();
    page = 0;
    isEnd = false;
    await queryData();
  }
}
