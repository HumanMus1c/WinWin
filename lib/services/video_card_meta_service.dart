import 'dart:async';

import 'package:winwin/core/log/app_logger.dart';
import 'package:winwin/common/widgets/video_card/video_card_adapter.dart';
import 'package:winwin/http/api.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/http/response_map.dart';

/// 聊天视频卡的元数据补全：按 bvid 拉取 UP / 播放 / 弹幕，使卡片与首页竖卡同构。
///
/// 消息协议 `msg_type=11` 只下发 `bvid/title/cover/times`，没有 UP 与统计；
/// 这里仅对可见的视频消息补一次 `/x/web-interface/view`，按 bvid 缓存，
/// 失败时回退为消息自带字段（卡片仍可点击播放）。
abstract final class VideoCardMetaService {
  static final Map<String, VideoCardData> _cache = {};
  static final Map<String, Future<VideoCardData>> _inFlight = {};

  /// 最多 6 个并发：首页 App 兜底按整页批量补全，聊天里连续多张视频卡
  /// 也不会一次打满接口。
  static const int _maxConcurrent = 6;
  static int _active = 0;
  static final List<Completer<void>> _waiters = [];

  static VideoCardData? cached(String? bvid) {
    if (bvid == null || bvid.isEmpty) return null;
    return _cache[bvid];
  }

  /// 用已缓存统计覆盖当前条目的本地字段（推荐理由 / 关注态 / 进度保持原样）。
  ///
  /// 与 [enrich] 不同，这里不发起网络请求：缓存命中时让首页卡片首帧就带
  /// 点赞与发布时间，避免「先渲染未补全卡片、下一帧再回填」的逐个跳动。
  static VideoCardData applyCached(VideoCardData fallback) {
    final hit = cached(fallback.bvid);
    if (hit == null) return fallback;
    return VideoCardData(
      bvid: fallback.bvid,
      cover: fallback.cover?.isNotEmpty == true ? fallback.cover : hit.cover,
      title: fallback.title.isNotEmpty ? fallback.title : hit.title,
      duration: fallback.duration > 0 ? fallback.duration : hit.duration,
      ownerName: fallback.ownerName.isNotEmpty
          ? fallback.ownerName
          : hit.ownerName,
      mid: fallback.mid ?? hit.mid,
      playCount: hit.playCount ?? fallback.playCount,
      danmakuCount: hit.danmakuCount ?? fallback.danmakuCount,
      likeCount: hit.likeCount ?? fallback.likeCount,
      publishedAt: hit.publishedAt ?? fallback.publishedAt,
      rcmdReason: fallback.rcmdReason,
      isFollowed: fallback.isFollowed,
      progress: fallback.progress,
      progressSeconds: fallback.progressSeconds,
      playedAt: fallback.playedAt,
      aid: fallback.aid ?? hit.aid,
      cid: fallback.cid ?? hit.cid,
      goto: fallback.goto,
      param: fallback.param,
      threePoint: fallback.threePoint,
    );
  }

  /// 整页批量补全：首页 App 兜底流没有 `stat.like/pubdate`，在返回列表前
  /// 并发补齐，随后 [applyCached] 让整页点赞一次性出现。
  static Future<void> prefetch(Iterable<VideoCardData> items) {
    final seen = <String>{};
    final pending = <Future<VideoCardData>>[];
    for (final item in items) {
      final bvid = item.bvid;
      if (bvid == null || bvid.isEmpty || !seen.add(bvid)) continue;
      if (_cache.containsKey(bvid)) continue;
      pending.add(enrich(item));
    }
    return Future.wait(pending).then((_) {});
  }

  static Future<VideoCardData> enrich(VideoCardData fallback) {
    final bvid = fallback.bvid;
    if (bvid == null || bvid.isEmpty) return Future.value(fallback);
    final cachedData = _cache[bvid];
    if (cachedData != null) return Future.value(cachedData);
    final inFlight = _inFlight[bvid];
    if (inFlight != null) return inFlight;

    final completer = Completer<VideoCardData>();
    final future = completer.future;
    _inFlight[bvid] = future;

    () async {
      await _acquire();
      try {
        final res = await Request.dio.get<dynamic>(
          Api.videoIntro,
          queryParameters: {'bvid': bvid},
        );
        final map = asJsonMap(res.data);
        final data = map['data'];
        var merged = fallback;
        if ((map['code'] as num?)?.toInt() == 0 && data is Map) {
          final owner = data['owner'];
          final stat = data['stat'];
          merged = VideoCardData(
            bvid: bvid,
            cover: fallback.cover?.isNotEmpty == true
                ? fallback.cover
                : data['pic']?.toString(),
            title: fallback.title.isNotEmpty
                ? fallback.title
                : (data['title']?.toString() ?? ''),
            duration: fallback.duration > 0
                ? fallback.duration
                : ((data['duration'] as num?)?.toInt() ?? 0),
            ownerName: owner is Map && (owner['name']?.toString() ?? '').isNotEmpty
                ? owner['name'].toString()
                : fallback.ownerName,
            mid: owner is Map
                ? (owner['mid'] as num?)?.toInt()
                : fallback.mid,
            playCount: stat is Map
                ? ((stat['view'] as num?)?.toInt() ?? fallback.playCount)
                : fallback.playCount,
            danmakuCount: stat is Map
                ? ((stat['danmaku'] as num?)?.toInt() ?? fallback.danmakuCount)
                : fallback.danmakuCount,
            likeCount: stat is Map
                ? ((stat['like'] as num?)?.toInt() ?? fallback.likeCount)
                : fallback.likeCount,
            publishedAt:
                (data['pubdate'] as num?)?.toInt() ?? fallback.publishedAt,
            rcmdReason: fallback.rcmdReason,
            isFollowed: fallback.isFollowed,
            progress: fallback.progress,
            progressSeconds: fallback.progressSeconds,
            playedAt: fallback.playedAt,
            aid: (data['aid'] as num?)?.toInt() ?? fallback.aid,
            cid: (data['cid'] as num?)?.toInt() ?? fallback.cid,
            goto: fallback.goto,
            param: fallback.param,
            threePoint: fallback.threePoint,
          );
        }
        _cache[bvid] = merged;
        completer.complete(merged);
      } catch (e) {
        AppLogger.w('VideoCardMeta', 'bvid=$bvid enrich failed: $e');
        _cache[bvid] = fallback;
        completer.complete(fallback);
      } finally {
        _inFlight.remove(bvid);
        _release();
      }
    }();

    return future;
  }

  static Future<void> _acquire() async {
    if (_active < _maxConcurrent) {
      _active++;
      return;
    }
    final waiter = Completer<void>();
    _waiters.add(waiter);
    await waiter.future;
  }

  static void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
      return;
    }
    if (_active > 0) _active--;
  }
}
