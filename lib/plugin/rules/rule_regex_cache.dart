import 'dart:collection';

/// 规则正则缓存（对应 BiliPai `CompiledRegexCache`）。
///
/// 导入时校验语法，运行时只做编译结果复用：
/// - 单条 pattern 限长，避免极端回溯；
/// - LRU 上限防止插件数量 × 规则数量无限增长；
/// - 编译失败缓存 null，后续同 pattern 直接不匹配。
class RuleRegexCache {
  RuleRegexCache({
    this.maxEntries = 128,
    this.maxPatternLength = 256,
  });

  final int maxEntries;
  final int maxPatternLength;

  final LinkedHashMap<String, RegExp?> _cache = LinkedHashMap();

  RegExp? get(String pattern) {
    if (pattern.isEmpty || pattern.length > maxPatternLength) return null;
    if (_cache.containsKey(pattern)) {
      final cached = _cache.remove(pattern);
      _cache[pattern] = cached;
      return cached;
    }
    RegExp? compiled;
    try {
      compiled = RegExp(pattern, caseSensitive: false);
    } catch (_) {
      compiled = null;
    }
    _cache[pattern] = compiled;
    while (_cache.length > maxEntries) {
      _cache.remove(_cache.keys.first);
    }
    return compiled;
  }

  void clear() => _cache.clear();
}
