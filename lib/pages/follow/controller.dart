import 'package:winwin/core/account/account_service.dart';
import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/http/dyn.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/models/video/rec_video_item.dart';
import 'package:winwin/pages/common/common_list_controller.dart';

/// 关注动态视频流控制器（移植自 PiliPlus `DynamicsTabController` 的 offset 游标模式）。
///
/// 调用 `/x/polymer/web-dynamic/v1/feed/all`（type='video' 仅视频动态），
/// **offset 游标分页**（非页码制）：每页响应返回下一页 offset，刷新时置空。
/// 需要登录态；未登录时返回错误，由 View 层渲染登录引导。
class FollowController extends CommonListController {
  /// 下一页游标（首次为 null，由响应 [DynFeedData.offset] 提供）。
  String? _offset;

  @override
  void onInit() {
    super.onInit();
    queryData();
  }

  @override
  Future<LoadingState> customGetData() async {
    await ensureBootstrap();
    if (!AccountService().isLogin) {
      return const Error('请先登录');
    }
    return DynHttp.followDynamic(offset: _offset, type: 'video');
  }

  @override
  List? getDataList(dynamic response) {
    final data = response as DynFeedData;
    // 更新游标；hasMore=false 时置空并标记结束。
    _offset = data.hasMore ? data.offset : null;
    if (!data.hasMore) isEnd = true;
    return data.items.map((d) => FollowVideoItem(d)).toList();
  }

  @override
  Future<void> onRefresh() {
    _offset = null;
    return super.onRefresh();
  }
}

/// 将关注动态 [DynItemModel] 适配为 [BaseRcmdVideoItemModel]，
/// 使 [VideoCardV] 与详情页跳转逻辑可直接复用（与推荐流/热门流一致）。
///
/// 映射：author → owner，archive → title/bvid/cover/duration/stat。
class FollowVideoItem extends BaseRcmdVideoItemModel {
  FollowVideoItem(DynItemModel dyn) {
    final archive = dyn.archive;
    final author = dyn.author;
    title = archive?.title;
    bvid = archive?.bvid;
    cover = archive?.cover;
    duration = _parseDurationText(archive?.durationText);
    // 关注流的稿件均来自已关注 UP，标记已关注以显示角标。
    isFollowed = true;
    owner = _DynOwner(author?.mid, author?.name);
    stat = _DynStat(archive?.play, archive?.danmaku);
  }
}

/// 解析 B 站动态时长文本（"12:34" / "1:02:03"）为秒数。
int _parseDurationText(String? text) {
  if (text == null || text.isEmpty) return -1;
  final parts = text.split(':');
  if (parts.length == 2) {
    final m = int.tryParse(parts[0]) ?? 0;
    final s = int.tryParse(parts[1]) ?? 0;
    return m * 60 + s;
  }
  if (parts.length == 3) {
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    final s = int.tryParse(parts[2]) ?? 0;
    return h * 3600 + m * 60 + s;
  }
  return int.tryParse(text) ?? -1;
}

class _DynOwner extends BaseOwner {
  _DynOwner(int? mid, String? name) {
    this.mid = mid;
    this.name = name;
  }
}

class _DynStat extends BaseStat {
  _DynStat(int? view, int? danmu) {
    this.view = view;
    this.danmu = danmu;
  }
}
