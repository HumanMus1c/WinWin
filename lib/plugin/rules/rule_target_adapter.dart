import 'package:winwin/grpc/bilibili/community/service/dm/v1.pb.dart';
import 'package:winwin/models/video/rec_video_item.dart';
import 'package:winwin/plugin/canvas_danmaku/models/danmaku_content_item.dart';

/// 规则字段适配：把 WinWin 的运行时模型映射成 JSON 规则可读的字段。
///
/// 字段集合对齐 BiliPai `RuleEngine`，并补充 WinWin 推荐流模型里
/// 可获得的 `rcmdReason` / `pubdate` / `isFollowed` / `tname`。
/// 不存在的字段返回 null ⇒ 条件按不命中处理（与上游一致）。
abstract final class RuleTargetAdapter {
  static Object? video(BaseRcmdVideoItemModel item, String field) {
    switch (field) {
      case 'title':
        return item.title;
      case 'duration':
        return item.duration;
      case 'bvid':
        return item.bvid;
      case 'tname':
        return item.tname;
      case 'goto':
        return item.goto;
      case 'rcmdReason':
        return item.rcmdReason;
      case 'isFollowed':
        return item.isFollowed;
      case 'owner.mid':
        return item.owner.mid;
      case 'owner.name':
        return item.owner.name;
      case 'stat.view':
        return item.stat.view;
      case 'stat.like':
        return item.stat.like;
      case 'stat.danmaku':
        return item.stat.danmu;
      case 'pubdate':
        return item is RcmdVideoItemModel ? item.pubdate : null;
      default:
        return null;
    }
  }

  static Object? danmaku(DanmakuContentItem<Object?> item, String field) {
    final extra = item.extra;
    switch (field) {
      case 'content':
        return item.text;
      case 'type':
        return extra is DanmakuElem ? extra.mode : item.type.name;
      case 'mode':
        return extra is DanmakuElem ? extra.mode : null;
      case 'progress':
        return extra is DanmakuElem ? extra.progress : null;
      case 'color':
        return extra is DanmakuElem
            ? extra.color
            : item.color.toARGB32() & 0xFFFFFF;
      case 'weight':
        return extra is DanmakuElem ? extra.weight : null;
      case 'midHash':
        return extra is DanmakuElem ? extra.midHash : null;
      // 弹幕接口只返回 midHash，不含原始 uid；保留字段名以兼容规则写法。
      case 'userId':
        return null;
      default:
        return null;
    }
  }
}
