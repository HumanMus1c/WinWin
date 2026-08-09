import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/video.dart';
import 'package:winwin/pages/common/common_list_controller.dart';

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
    return VideoHttp.hotVideoList(pn: page, ps: 20);
  }
}
