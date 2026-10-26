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

  /// 推荐流常驻条数上限（无限 feed 的滑窗大小）。
  static const int _maxItems = 300;

  /// 单次下滚至少补够的新条目数：服务端偶尔回送已看过的卡片时，
  /// 只追加一两条会让信息流看起来「一张一张」地出现，故按半行以上追平。
  static const int _minNewPerLoad = 6;

  /// 单次下滚最多追拉的批次数，避免服务端持续重复时形成请求风暴。
  static const int _maxCatchUp = 3;

  /// 本次下滚实际新增条数（去重后），供 [onLoadMore] 追平判断。
  int _lastAppended = 0;

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
    // On refresh (page == 0) merge old data below the new batch so users
    // don't lose what they haven't seen yet.
    if (enableSaveLastData && page == 0) {
      _lastAppended = 0;
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
      return;
    }
    // append 路径（无限 feed 下滚加载）：丢弃本批次中已在列表内的卡片，
    // 并裁剪历史头部控制常驻规模。
    // 触发时机为滚到底加载更多（视口在列表尾部），裁头部不影响视口内容；
    // 用户回滚到顶部时看到的是更新的推荐批次（有限 feed 的固有取舍）。
    if (loadingState.value case Success(:final response)) {
      final list = response;
      if (list == null) return;
      final seen = <String>{};
      for (final item in list) {
        final key = _keyOf(item);
        if (key != null) seen.add(key);
      }
      dataList.removeWhere((item) {
        final key = _keyOf(item);
        return key != null && !seen.add(key);
      });
      _lastAppended = dataList.length;
      final overflow = list.length + dataList.length - _maxItems;
      if (overflow <= 0) return;
      list.removeRange(0, overflow);
      // 头部被裁掉后，刷新分隔点同步前移，避免提示落到错误卡片上。
      final tip = lastRefreshAt;
      if (tip != null) {
        lastRefreshAt = tip - overflow > 0 ? tip - overflow : null;
      }
    }
  }

  @override
  Future<void> onLoadMore() async {
    if (isLoading) return;
    // 服务端同一游标区间可能回送大量已看过的卡片；去重后若新增过少，
    // 立刻追下一批，避免信息流「一张一张」地出现。
    for (var attempt = 0; attempt < _maxCatchUp; attempt++) {
      _lastAppended = 0;
      await super.onLoadMore();
      if (_lastAppended >= _minNewPerLoad) return;
    }
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
