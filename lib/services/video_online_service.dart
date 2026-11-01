import 'dart:async';

import 'package:winwin/http/video.dart';

/// 视频卡「XX人正在看」在线人数：按 bvid+cid 懒加载，60s 缓存，最多 2 并发。
///
/// 对应接口 `/x/player/online/total`；受设置「显示在线人数」控制，
/// 默认关闭，只有卡片可见且参数齐全时才请求。
abstract final class VideoOnlineService {
  static const Duration _ttl = Duration(seconds: 60);
  static const int _maxConcurrent = 2;
  static const int _maxEntries = 512;

  static final Map<String, _OnlineEntry> _cache = {};
  static final Map<String, Future<String?>> _inFlight = {};
  static int _active = 0;
  static final List<Completer<void>> _waiters = [];

  static String _key(int aid, int? cid, String? bvid) =>
      '${bvid?.isNotEmpty == true ? bvid : aid}#$cid';

  static String? cached({
    required int aid,
    required int? cid,
    String? bvid,
  }) {
    if (!_usable(aid, cid)) return null;
    final key = _key(aid, cid, bvid);
    final entry = _cache[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.fetchedAt) > _ttl) {
      _cache.remove(key);
      return null;
    }
    return entry.text;
  }

  static Future<String?> fetch({
    required int aid,
    required int? cid,
    String? bvid,
  }) {
    if (!_usable(aid, cid)) return Future.value(null);
    final key = _key(aid, cid, bvid);
    final cachedText = cached(aid: aid, cid: cid, bvid: bvid);
    if (cachedText != null) return Future.value(cachedText);
    final existing = _inFlight[key];
    if (existing != null) return existing;

    final completer = Completer<String?>();
    final future = completer.future;
    _inFlight[key] = future;

    () async {
      await _acquire();
      try {
        final res = await VideoHttp.onlineTotal(
          aid: aid,
          cid: cid!,
          bvid: bvid,
        );
        final text = res.dataOrNull?.trim();
        if (text != null && text.isNotEmpty && text != '0') {
          _cache[key] = _OnlineEntry(text: text, fetchedAt: DateTime.now());
          _sweep();
          completer.complete(text);
        } else {
          completer.complete(null);
        }
      } catch (_) {
        completer.complete(null);
      } finally {
        _inFlight.remove(key);
        _release();
      }
    }();

    return future;
  }

  static bool _usable(int aid, int? cid) => aid > 0 && cid != null && cid > 0;

  static void _sweep() {
    if (_cache.length <= _maxEntries) return;
    final oldest = _cache.entries.reduce(
      (a, b) => a.value.fetchedAt.isBefore(b.value.fetchedAt) ? a : b,
    );
    _cache.remove(oldest.key);
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

class _OnlineEntry {
  const _OnlineEntry({required this.text, required this.fetchedAt});

  final String text;
  final DateTime fetchedAt;
}
