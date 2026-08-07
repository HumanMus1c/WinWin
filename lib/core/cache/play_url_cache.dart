import 'dart:collection';

/// PlayUrl 缓存 — 从 BiliPai PlayUrlCache.kt 移植。
///
/// LRU + TTL 策略：容量 80 条，过期 10 分钟。
/// 缓存键格式：`bvid:cid:q={qualityKey}:a={audioKey}`。
class PlayUrlCache {
  PlayUrlCache._();

  static const _maxCacheSize = 80;
  static const _cacheDurationMs = 10 * 60 * 1000; // 10 分钟

  final LinkedHashMap<String, _CachedPlayUrl> _cache =
      LinkedHashMap<String, _CachedPlayUrl>();

  /// 获取缓存的 playurl 数据。
  ///
  /// [requestedQuality] 为 null 时自动匹配该视频最新的未过期缓存。
  /// [audioLang] 为 null 时使用 "default"。
  dynamic get(
    String bvid,
    int cid, {
    int? requestedQuality,
    String? audioLang,
  }) {
    final key = _buildKey(bvid, cid, requestedQuality, audioLang);
    final cached = _cache[key];
    if (cached != null) {
      if (!cached.isExpired) {
        // LRU: 移到末尾（最近使用）
        _cache.remove(key);
        _cache[key] = cached;
        return cached.data;
      } else {
        _cache.remove(key);
      }
    }

    // 自动画质模式：尝试匹配该视频任意变体
    if (requestedQuality == null && audioLang == null) {
      final match = _findNewestValidCacheForVideo(bvid, cid);
      if (match != null) {
        return match.data;
      }
    }
    return null;
  }

  /// 写入缓存。
  void put(
    String bvid,
    int cid,
    dynamic data, {
    int? quality,
    String? audioLang,
  }) {
    final key = _buildKey(bvid, cid, quality, audioLang);
    // 容量淘汰
    while (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = _CachedPlayUrl(
      bvid: bvid,
      cid: cid,
      data: data,
      quality: quality,
      audioLang: audioLang,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 使指定视频的缓存失效。
  ///
  /// [quality] 和 [audioLang] 均为 null 时删除该视频所有变体。
  void invalidate(
    String bvid,
    int cid, {
    int? quality,
    String? audioLang,
  }) {
    if (quality == null && audioLang == null) {
      final prefix = '$bvid:$cid:';
      _cache.removeWhere((key, _) => key.startsWith(prefix));
    } else {
      final key = _buildKey(bvid, cid, quality, audioLang);
      _cache.remove(key);
    }
  }

  void clear() => _cache.clear();

  int get size => _cache.length;

  String get stats => 'PlayUrlCache: ${_cache.length}/$_maxCacheSize entries';

  _CachedPlayUrl? _findNewestValidCacheForVideo(String bvid, int cid) {
    final prefix = '$bvid:$cid:';
    _CachedPlayUrl? newest;
    String? newestKey;
    for (final entry in _cache.entries) {
      if (entry.key.startsWith(prefix) && !entry.value.isExpired) {
        if (newest == null ||
            entry.value.timestamp > newest.timestamp) {
          newest = entry.value;
          newestKey = entry.key;
        }
      }
    }
    if (newestKey != null && newest != null) {
      // LRU: 移到末尾
      _cache.remove(newestKey);
      _cache[newestKey] = newest;
    }
    return newest;
  }

  String _buildKey(
    String bvid,
    int cid,
    int? quality,
    String? audioLang,
  ) {
    final qualityKey = quality?.toString() ?? 'auto';
    final audioKey = audioLang ?? 'default';
    return '$bvid:$cid:q=$qualityKey:a=$audioKey';
  }
}

class _CachedPlayUrl {
  final String bvid;
  final int cid;
  final dynamic data;
  final int? quality;
  final String? audioLang;
  final int timestamp;

  _CachedPlayUrl({
    required this.bvid,
    required this.cid,
    required this.data,
    required this.quality,
    required this.audioLang,
    required this.timestamp,
  });

  int get expiresAt => timestamp + PlayUrlCache._cacheDurationMs;

  bool get isExpired =>
      DateTime.now().millisecondsSinceEpoch > expiresAt;
}

/// 全局单例。
final playUrlCache = PlayUrlCache._();
