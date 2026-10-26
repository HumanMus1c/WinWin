import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/video.dart';
import 'package:winwin/models/video/rec_video_item.dart';
import 'package:winwin/pages/common/common_list_controller.dart';
import 'package:winwin/utils/viewport_load_budget.dart';

class RcmdController extends CommonListController {
  // Simplified from Pref.enableSaveLastData; keeps last data on error/refresh.
  late bool enableSaveLastData = true;
  // Use the app recommend API by default (Pref.appRcmd equivalent).
  final bool appRcmd = true;

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

  /// 推荐流网格：单行高度（卡片 90 + 间距 8）与单卡宽度上限。
  static const double _gridRowExtent = 98;
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
    return appRcmd
        ? VideoHttp.rcmdVideoListApp(freshIdx: page)
        : VideoHttp.rcmdVideoList(freshIdx: page, ps: 20);
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
      dataList
        ..clear()
        ..addAll(merged);
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
        // 列表运行时类型是 List<RcmdVideoItemAppModel>，追加列表必须同型；
        // 用 List<dynamic> 调 addAll 会在运行时抛
        // "List<dynamic> is not a subtype of Iterable<RcmdVideoItemAppModel>"。
        final added = <RcmdVideoItemAppModel>[];
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
        list.addAll(added);
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
      fallback: _maxPrefetchBatches * _assumedBatchSize,
      visibleItems: _viewportCardCapacity,
      firstPage: false,
    );
    final count = (target / _assumedBatchSize).ceil();
    if (count < 1) return 1;
    return count > _maxPrefetchBatches ? _maxPrefetchBatches : count;
  }

  Future<List<RcmdVideoItemAppModel>> _fetchBatch(int idx) async {
    await ensureBootstrap();
    try {
      final res = await VideoHttp.rcmdVideoListApp(freshIdx: idx);
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
