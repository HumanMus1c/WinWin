import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/video.dart';
import 'package:winwin/pages/common/common_list_controller.dart';
import 'package:winwin/utils/viewport_load_budget.dart';

/// 热门视频控制器（移植自 PiliPlus `HotController`）。
///
/// 调用 `/x/web-interface/popular`，页码制分页（pn 从 1 起，ps=20）。
/// 复用 [RcmdVideoItemModel]（web 格式稿件），与推荐流共用 [VideoCardV]。
class HotController extends CommonListController {
  @override
  void onInit() {
    super.onInit();
    queryData();
  }

  @override
  Future<LoadingState> customGetData() async {
    await ensureBootstrap();
    // 视口预算：热门流为视频卡网格，冷启动首批最多 2 屏、滚动补批最多 1 屏。
    final visible = ViewportLoadBudget.visibleGridItems(
      viewportExtent: ViewportLoadBudget.viewportExtentOf(scrollController) - 220,
      viewportWidth: ViewportLoadBudget.windowLogicalWidth - 104,
      rowExtent: 98,
      maxCrossAxisExtent: 240,
    );
    final ps = ViewportLoadBudget.capRequestItems(
      fallback: 20,
      visibleItems: visible,
      firstPage: page <= 1,
    );
    return VideoHttp.hotVideoList(pn: page, ps: ps);
  }
}
