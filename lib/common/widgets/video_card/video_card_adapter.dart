import 'package:winwin/models/fav/fav_models.dart';
import 'package:winwin/models/history/history_models.dart';
import 'package:winwin/models/search/result.dart';
import 'package:winwin/models/video/rec_video_item.dart';
import 'package:winwin/models/video/related_video.dart';

/// 统一视频卡片数据适配结构体。
///
/// 取代在 [VideoCardV] / [VideoCardH] 内部每张卡片调用数十次 `_opt(() => ...)`
/// 的动态反射和异常捕获，在 Dart 编译期和运行时以强类型匹配提取数据，
/// 消除列表与瀑布流高速滚动时的 GC 抖动与 `NoSuchMethodError` 构造开销。
class VideoCardData {
  final String? bvid;
  final String? cover;
  final String title;
  final int duration;
  final String ownerName;
  final int? mid;
  final int? playCount;
  final int? danmakuCount;
  final String? rcmdReason;
  final bool isFollowed;
  final double? progress; // 0.0 ~ 1.0 归一化进度

  const VideoCardData({
    this.bvid,
    this.cover,
    this.title = '',
    this.duration = 0,
    this.ownerName = '',
    this.mid,
    this.playCount,
    this.danmakuCount,
    this.rcmdReason,
    this.isFollowed = false,
    this.progress,
  });

  /// 从任意已知或未知数据类型中高效安全地提取卡片展示字段。
  factory VideoCardData.from(dynamic item) {
    if (item == null) return const VideoCardData();
    if (item is VideoCardData) return item;

    // 1. 推荐流基类模型 (包含 Web 推荐与 App 推荐)
    if (item is BaseRcmdVideoItemModel) {
      return VideoCardData(
        bvid: item.bvid,
        cover: item.cover,
        title: item.title ?? '',
        duration: item.duration > 0 ? item.duration : 0,
        ownerName: item.owner.name ?? '',
        mid: item.owner.mid,
        playCount: item.stat.view,
        danmakuCount: item.stat.danmu,
        rcmdReason: item.rcmdReason,
        isFollowed: item.isFollowed,
      );
    }

    // 2. 相关推荐模型 (RelatedVideoItem)
    if (item is RelatedVideoItem) {
      return VideoCardData(
        bvid: item.bvid,
        cover: item.pic,
        title: item.title ?? '',
        duration: item.duration ?? 0,
        ownerName: item.owner?.name ?? '',
        mid: item.owner?.mid,
        playCount: item.stat?.view,
        danmakuCount: item.stat?.danmaku,
      );
    }

    // 3. 历史记录模型 (HistoryItem)
    if (item is HistoryItem) {
      final dur = item.duration ?? 0;
      double? prog = item.progress?.toDouble();
      if (prog != null && prog > 1 && dur > 0) {
        prog = (prog / dur).clamp(0.0, 1.0);
      }
      return VideoCardData(
        bvid: item.history.bvid,
        cover: item.cover,
        title: item.title ?? '',
        duration: dur,
        ownerName: item.authorName ?? '',
        mid: item.authorMid,
        progress: prog,
      );
    }

    // 4. 收藏夹详情项 (FavDetailItem)
    if (item is FavDetailItem) {
      return VideoCardData(
        bvid: item.bvid,
        cover: item.cover,
        title: item.title ?? '',
        duration: item.duration ?? 0,
        ownerName: item.upper?.name ?? '',
        mid: item.upper?.mid,
        playCount: item.cntInfo?.play,
        danmakuCount: item.cntInfo?.danmaku,
      );
    }

    // 5. 搜索结果视频模型 (SearchVideoItemModel)
    if (item is SearchVideoItemModel) {
      return VideoCardData(
        bvid: item.bvid,
        cover: item.cover,
        title: item.title ?? '',
        duration: item.duration ?? 0,
        ownerName: item.author ?? '',
        mid: item.mid,
        playCount: item.play,
        danmakuCount: item.danmaku,
      );
    }

    // 6. Map 结构回退
    if (item is Map) {
      final dur = (item['duration'] as num?)?.toInt() ?? 0;
      double? prog = (item['progress'] as num?)?.toDouble();
      if (prog != null && prog > 1 && dur > 0) {
        prog = (prog / dur).clamp(0.0, 1.0);
      }
      final owner = item['owner'] ?? item['upper'] ?? item['author'];
      String ownerName = '';
      int? mid;
      if (owner is Map) {
        ownerName = (owner['name'] ?? owner['author_name'])?.toString() ?? '';
        mid = (owner['mid'] as num?)?.toInt();
      } else if (item['author_name'] != null) {
        ownerName = item['author_name'].toString();
      }

      final stat = item['stat'] ?? item['cnt_info'] ?? item['cntInfo'];
      int? playCount;
      int? danmakuCount;
      if (stat is Map) {
        playCount = (stat['view'] ?? stat['play']) as int?;
        danmakuCount = (stat['danmu'] ?? stat['danmaku']) as int?;
      } else {
        playCount = (item['play'] ?? item['view']) as int?;
        danmakuCount = (item['danmu'] ?? item['danmaku']) as int?;
      }

      return VideoCardData(
        bvid: item['bvid']?.toString(),
        cover: (item['cover'] ?? item['pic'])?.toString(),
        title: item['title']?.toString() ?? '',
        duration: dur,
        ownerName: ownerName,
        mid: mid,
        playCount: playCount,
        danmakuCount: danmakuCount,
        rcmdReason: item['rcmd_reason']?.toString(),
        isFollowed: item['is_followed'] == true,
        progress: prog,
      );
    }

    // 7. 兜底动态反射（非标准类型）
    return _parseDynamic(item);
  }

  static VideoCardData _parseDynamic(dynamic dyn) {
    try {
      final String? bvid = _tryVal<String?>(() => dyn.bvid as String?);
      final String? cover = _tryVal<String?>(() => (dyn.cover ?? dyn.pic) as String?);
      final String title = _tryVal<String?>(() => dyn.title?.toString()) ?? '';
      final int duration = _tryVal<int?>(() => (dyn.duration as num?)?.toInt()) ?? 0;
      final dynamic owner = _tryVal<dynamic>(() => dyn.owner ?? dyn.upper ?? dyn.author);
      final String ownerName = _tryVal<String?>(() => (owner?.name ?? dyn.authorName)?.toString()) ?? '';
      final int? mid = _tryVal<int?>(() => (owner?.mid as num?)?.toInt());
      final dynamic stat = _tryVal<dynamic>(() => dyn.stat ?? dyn.cntInfo);
      final int? playCount = _tryVal<int?>(() => (stat?.view ?? stat?.play ?? dyn.play) as int?);
      final int? danmakuCount = _tryVal<int?>(() => (stat?.danmu ?? stat?.danmaku ?? dyn.danmaku) as int?);
      final String? rcmdReason = _tryVal<String?>(() => dyn.rcmdReason?.toString());
      final bool isFollowed = _tryVal<bool?>(() => dyn.isFollowed == true) ?? false;
      return VideoCardData(
        bvid: bvid,
        cover: cover,
        title: title,
        duration: duration,
        ownerName: ownerName,
        mid: mid,
        playCount: playCount,
        danmakuCount: danmakuCount,
        rcmdReason: rcmdReason,
        isFollowed: isFollowed,
      );
    } catch (_) {
      return const VideoCardData();
    }
  }

  static T? _tryVal<T>(T Function() fn) {
    try {
      return fn();
    } catch (_) {
      return null;
    }
  }
}
