import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/video.dart';
import 'package:winwin/pages/common/common_list_controller.dart';

class RcmdController extends CommonListController {
  // Simplified from Pref.enableSaveLastData; keeps last data on error/refresh.
  late bool enableSaveLastData = true;
  // Use the app recommend API by default (Pref.appRcmd equivalent).
  final bool appRcmd = true;

  int? lastRefreshAt;
  late bool savedRcmdTip = true;

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
      if (loadingState.value case Success(:final response)) {
        if (response != null && response.isNotEmpty) {
          if (savedRcmdTip) {
            lastRefreshAt = dataList.length;
          }
          if (response.length > 200) {
            dataList.addAll(response.take(50));
          } else {
            dataList.addAll(response);
          }
        }
      }
      return;
    }
    // append 路径（无限 feed 下滚加载）：裁剪历史头部控制常驻规模。
    // 触发时机为滚到底加载更多（视口在列表尾部），裁头部不影响视口内容；
    // 用户回滚到顶部时看到的是更新的推荐批次（有限 feed 的固有取舍）。
    const int maxItems = 300;
    if (loadingState.value case Success(:final response)) {
      final list = response;
      if (list == null) return;
      final overflow = list.length + dataList.length - maxItems;
      if (overflow <= 0) return;
      list.removeRange(0, overflow);
    }
  }

  @override
  Future<void> onRefresh() {
    page = 0;
    isEnd = false;
    return queryData();
  }
}
