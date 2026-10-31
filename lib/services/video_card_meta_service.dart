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

  /// 最多 2 个并发，避免聊天里连续多张视频卡同时打接口。
  static const int _maxConcurrent = 2;
  static int _active = 0;
  static final List<Completer<void>> _waiters = [];

  static VideoCardData? cached(String? bvid) {
    if (bvid == null || bvid.isEmpty) return null;
    return _cache[bvid];
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
            ownerName: owner is Map ? (owner['name']?.toString() ?? '') : '',
            mid: owner is Map ? (owner['mid'] as num?)?.toInt() : null,
            playCount: stat is Map ? (stat['view'] as num?)?.toInt() : null,
            danmakuCount: stat is Map ? (stat['danmaku'] as num?)?.toInt() : null,
            publishedAt: (data['pubdate'] as num?)?.toInt(),
            aid: (data['aid'] as num?)?.toInt() ?? fallback.aid,
            cid: (data['cid'] as num?)?.toInt() ?? fallback.cid,
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
