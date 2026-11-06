import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/video.dart';
import 'package:winwin/models/video/video_detail.dart';

/// 首页卡片详情预取：鼠标 hover 时静默拉取 `videoIntro`，
/// 点击进入详情页时直接复用，省去一次详情接口往返（约 100~250ms）。
///
/// 约束：并发上限 2、排队上限 6、缓存 TTL 3 分钟、最多 24 条，
/// 避免悬停扫过整屏时集中打满接口触发风控。
abstract final class VideoIntroPrefetch {
  static const Duration _ttl = Duration(minutes: 3);
  static const int _maxEntries = 24;
  static const int _maxInflight = 2;
  static const int _maxPending = 6;

  static final Map<String, _Entry> _cache = {};
  static final List<String> _pending = [];
  static int _inflight = 0;

  /// 是否有可直接复用的新鲜结果（含在途请求）。
  static bool hasFresh(String bvid) {
    final entry = _cache[bvid];
    if (entry == null) return false;
    if (DateTime.now().difference(entry.createdAt) > _ttl) {
      _cache.remove(bvid);
      return false;
    }
    return true;
  }

  /// hover 预取：并发满时排队，静默失败（失败结果会在完成后清除，允许重试）。
  static void prefetch(String bvid) {
    if (bvid.isEmpty || hasFresh(bvid)) return;
    if (_inflight >= _maxInflight) {
      if (_pending.length < _maxPending && !_pending.contains(bvid)) {
        _pending.add(bvid);
      }
      return;
    }
    _start(bvid);
  }

  /// 详情页取数：命中新鲜缓存（含在途）直接复用，否则直连并写入缓存。
  static Future<LoadingState<VideoDetailData>> fetch(String bvid) {
    final entry = _cache[bvid];
    if (entry != null && DateTime.now().difference(entry.createdAt) <= _ttl) {
      return entry.future;
    }
    final future = VideoHttp.videoIntro(bvid: bvid);
    _put(bvid, future);
    return future;
  }

  static void _start(String bvid) {
    _inflight++;
    _put(bvid, VideoHttp.videoIntro(bvid: bvid), tracked: true);
  }

  static void _put(
    String bvid,
    Future<LoadingState<VideoDetailData>> future, {
    bool tracked = false,
  }) {
    final entry = _Entry(createdAt: DateTime.now(), future: future);
    _cache[bvid] = entry;
    _trim();
    future.then<void>(
      (res) {
        if (res is Error) entry.failed = true;
      },
      onError: (_) => entry.failed = true,
    ).whenComplete(() {
      if (entry.failed && _cache[bvid] == entry) {
        _cache.remove(bvid);
      }
      if (!tracked) return;
      if (_inflight > 0) _inflight--;
      if (_pending.isNotEmpty) {
        final next = _pending.removeAt(0);
        if (!hasFresh(next)) _start(next);
      }
    });
  }

  static void _trim() {
    if (_cache.length <= _maxEntries) return;
    final keys = _cache.keys.toList()
      ..sort((a, b) => _cache[a]!.createdAt.compareTo(_cache[b]!.createdAt));
    for (final key in keys.take(_cache.length - _maxEntries)) {
      _cache.remove(key);
    }
  }
}

class _Entry {
  _Entry({required this.createdAt, required this.future});

  final DateTime createdAt;
  final Future<LoadingState<VideoDetailData>> future;
  bool failed = false;
}
