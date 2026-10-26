import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/video.dart';
import 'package:winwin/models/video/rec_video_item.dart';
import 'package:winwin/pages/common/common_list_controller.dart';

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

  /// 单次补货并发拉取的批次数。
  ///
  /// 实测（2026-10-26 登录态连续探测 31 批）：服务端在同一会话内会大量回送
  /// 刚发过的卡片，单批 8 条去重后常常只剩 0~3 条，而每批要 800ms 左右，
  /// 串行追平的观感就是「新内容一张一张往外蹦」。并发多批可在同一时间窗
  /// 内拿到数倍有效条目，合并后一次性提交，用户看到的是成块新增。
  static const int _prefetchBatches = 4;

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
        final int startIdx = page;
        final batches = await Future.wait([
          for (var i = 0; i < _prefetchBatches; i++)
            _fetchBatch(startIdx + i),
        ]);
        page = startIdx + _prefetchBatches;

        final seen = <String>{};
        for (final item in list) {
          final key = _keyOf(item);
          if (key != null) seen.add(key);
        }
        final added = <dynamic>[];
        for (final batch in batches) {
          for (final item in batch) {
            final key = _keyOf(item);
            if (key == null || seen.add(key)) added.add(item);
          }
        }
        // 全部批次都被去重掉时不刷新 UI，避免空重建。
        if (added.isEmpty) return;
        list.addAll(added);
        loadingState.refresh();
      } finally {
        isLoading = false;
        await flushPendingRefresh();
      }
    }
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
