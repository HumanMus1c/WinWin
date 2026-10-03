// Ported from BiliPai (Kotlin) -> WinWin (Dart)
// Original: com/android/purebilibili/feature/video/danmaku/DanmakuKeywordFilterPolicy.kt
//
// 弹幕关键词屏蔽规则引擎。
//
// 三种匹配器（与 B 站 /x/dm/filter/user 接口约定一致）：
//   - 关键词（keyword）：子串包含，大小写不敏感。
//   - 正则（regex）：前缀 regex: / re: / /.../ ，大小写不敏感。
//   - 用户哈希（userHash）：前缀 uid: / user: / hash: / @，精确匹配 midHash。
//
// 支持 JSON / XML / 纯文本三种导入格式，用于屏蔽规则分享/导入。
// 纯文本规则以 换行/逗号/中文逗号 分隔。
//
// 与 [RuleFilter] 的关系：
// - [RuleFilter]（models/danmaku/danmaku_rule.dart）面向服务端结构化规则
//  （SimpleRule[type,filter] 三组列表），用于入桶前过滤。
// - 本策略面向用户侧自由格式规则串（单文本框输入 / 文件导入），提供更灵活
//   的规则解析、分组、导入容错与匹配能力，可作为 RuleFilter 的上游来源。

import 'dart:convert';

// ── 规则前缀常量 ──

const String _kRegexRulePrefix = 'regex:';
const String _kShortRegexRulePrefix = 're:';
const String _kUserHashRulePrefix = 'uid:';
const String _kUserRulePrefix = 'user:';
const String _kHashRulePrefix = 'hash:';

/// 规则分隔符：换行 / 英文逗号 / 中文逗号。
final RegExp _kDanmakuRuleSplitter = RegExp(r'[\n,，]+');

/// 屏蔽规则分组。
enum DanmakuBlockRuleGroup {
  keyword,
  regex,
  userHash,
}

/// 三段式规则分区结果。
class DanmakuBlockRuleSections {
  final List<String> keywordRules;
  final List<String> regexRules;
  final List<String> userHashRules;

  const DanmakuBlockRuleSections({
    this.keywordRules = const [],
    this.regexRules = const [],
    this.userHashRules = const [],
  });

  /// 合并为扁平规则列表（关键词 + 正则 + 用户哈希）。
  List<String> toFlatList() => [
        ...keywordRules,
        ...regexRules,
        ...userHashRules,
      ];

  @override
  String toString() =>
      'DanmakuBlockRuleSections(keyword=${keywordRules.length}, '
      'regex=${regexRules.length}, userHash=${userHashRules.length})';
}

/// 屏蔽规则导入结果。
class DanmakuBlockRuleImportResult {
  final List<String> rules;
  final List<String> invalidEntries;
  final int skippedDisabledCount;
  final String? errorMessage;

  const DanmakuBlockRuleImportResult({
    this.rules = const [],
    this.invalidEntries = const [],
    this.skippedDisabledCount = 0,
    this.errorMessage,
  });

  /// 按前缀分组后的规则。
  DanmakuBlockRuleSections get sections => partitionDanmakuBlockRules(rules);

  /// 是否可导入（无错误且规则非空）。
  bool get canImport => errorMessage == null && rules.isNotEmpty;

  @override
  String toString() =>
      'DanmakuBlockRuleImportResult(rules=${rules.length}, '
      'invalid=${invalidEntries.length}, skipped=$skippedDisabledCount'
      '${errorMessage != null ? ", error=$errorMessage" : ""})';
}

// ── 匹配器（sealed，仅本文件内使用）──

abstract class _DanmakuBlockRuleMatcher {
  bool matches(String content, {String userHash = ''});
}

class _DanmakuKeywordMatcher implements _DanmakuBlockRuleMatcher {
  final String keyword;
  _DanmakuKeywordMatcher(this.keyword);

  @override
  bool matches(String content, {String userHash = ''}) {
    return content.toLowerCase().contains(keyword.toLowerCase());
  }
}

class _DanmakuRegexMatcher implements _DanmakuBlockRuleMatcher {
  final RegExp regex;
  _DanmakuRegexMatcher(this.regex);

  @override
  bool matches(String content, {String userHash = ''}) {
    return regex.hasMatch(content);
  }
}

class _DanmakuUserHashMatcher implements _DanmakuBlockRuleMatcher {
  final String userHashRule;
  _DanmakuUserHashMatcher(this.userHashRule);

  @override
  bool matches(String content, {String userHash = ''}) {
    if (userHash.isEmpty) return false;
    return userHash.toLowerCase() == userHashRule.toLowerCase();
  }
}

// ── 规则解析 ──

/// 解析原始规则文本为规则列表。
///
/// 优先尝试 JSON 格式；失败则按分隔符切分纯文本。
List<String> parseDanmakuBlockRules(String raw) {
  final json = _parseDanmakuBlockRulesJson(raw);
  if (json != null) return json;
  return raw
      .split(_kDanmakuRuleSplitter)
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
}

/// 解析导入内容（支持 XML / JSON / 纯文本）。
///
/// - XML：解析 `<item>` / `<filter>` 元素，跳过 enabled=false。
/// - JSON：解析 keywords/regex/userHashes/rules 等字段。
/// - 纯文本：按分隔符切分。
DanmakuBlockRuleImportResult parseDanmakuBlockRuleImport(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return const DanmakuBlockRuleImportResult(errorMessage: '文件内容为空');
  }
  if (trimmed.startsWith('<')) {
    return _parseDanmakuBlockRuleXmlImport(trimmed);
  }
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    final rules = _parseDanmakuBlockRulesJson(trimmed);
    if (rules == null) {
      return const DanmakuBlockRuleImportResult(
          errorMessage: 'JSON 屏蔽规则格式无效');
    }
    return _buildDanmakuBlockRuleImportResult(rules);
  }
  return _buildDanmakuBlockRuleImportResult(
    trimmed.split(_kDanmakuRuleSplitter),
  );
}

DanmakuBlockRuleImportResult _buildDanmakuBlockRuleImportResult(
  List<String> candidates, {
  int skippedDisabledCount = 0,
}) {
  final valid = <String>[];
  final invalid = <String>[];
  for (final candidate in candidates) {
    final normalized = _normalizeDanmakuImportedRule(candidate);
    if (normalized == null || _resolveMatcher(normalized) == null) {
      final trimmed = candidate.trim();
      if (trimmed.isNotEmpty) invalid.add(trimmed);
    } else {
      valid.add(normalized);
    }
  }
  return DanmakuBlockRuleImportResult(
    rules: _distinct(valid),
    invalidEntries: _distinct(invalid),
    skippedDisabledCount: skippedDisabledCount,
  );
}

String? _normalizeDanmakuImportedRule(String rule) {
  final normalized = rule.trim();
  if (normalized.isEmpty) return null;
  final prefix = normalized.length >= 2
      ? normalized.substring(0, 2).toLowerCase()
      : '';
  final body = normalized.substring(2).trim();
  switch (prefix) {
    case 't=':
      return body.isNotEmpty ? body : null;
    case 'r=':
      return body.isNotEmpty ? '$_kRegexRulePrefix$body' : null;
    case 'u=':
      return body.isNotEmpty ? '$_kUserHashRulePrefix$body' : null;
    default:
      return _normalizeDanmakuBlockRuleForAppend(normalized);
  }
}

List<String>? _parseDanmakuBlockRulesJson(String raw) {
  final trimmed = raw.trim();
  if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return null;
  final dynamic element;
  try {
    element = jsonDecode(trimmed);
  } catch (_) {
    return null;
  }
  List<String>? result;
  if (element is List) {
    result = _jsonArrayToRuleStrings(element);
  } else if (element is Map<String, dynamic>) {
    result = _jsonObjectToRuleStrings(element);
  }
  if (result == null || result.isEmpty) return null;
  return _distinct(result);
}

List<String> _jsonObjectToRuleStrings(Map<String, dynamic> obj) {
  final keywordRules = _readStringArray(obj, [
    'keywords',
    'keywordRules',
    'keyword',
    'words',
  ])
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
  final regexRules = _readStringArray(obj, ['regex', 'regexRules', 'regexp'])
      .map(_normalizeDanmakuRegexImportRule)
      .whereType<String>()
      .toList(growable: false);
  final userHashRules = _readStringArray(
    obj,
    ['userHashes', 'userHashRules', 'uids', 'users'],
  )
      .map(_normalizeDanmakuUserHashManagerInput)
      .whereType<String>()
      .toList(growable: false);
  final directRules = _readStringArray(obj, ['rules', 'items', 'blockRules'])
      .map(_normalizeDanmakuBlockRuleForAppend)
      .whereType<String>()
      .toList(growable: false);
  return [...keywordRules, ...regexRules, ...userHashRules, ...directRules];
}

List<String> _readStringArray(Map<String, dynamic> obj, List<String> keys) {
  for (final key in keys) {
    final value = obj[key];
    if (value is List) {
      return _jsonArrayToRuleStrings(value);
    }
    if (value is String) {
      return parseDanmakuBlockRules(value);
    }
  }
  return const [];
}

List<String> _jsonArrayToRuleStrings(List array) {
  return array
      .map((element) {
        if (element is String) {
          final trimmed = element.trim();
          return trimmed.isNotEmpty ? trimmed : null;
        }
        if (element is Map<String, dynamic>) {
          final v = element['value'];
          if (v is String) {
            final trimmed = v.trim();
            return trimmed.isNotEmpty ? trimmed : null;
          }
        }
        return null;
      })
      .whereType<String>()
      .toList(growable: false);
}

String? _normalizeDanmakuRegexImportRule(String rule) {
  final normalized = rule.trim();
  if (normalized.isEmpty) return null;
  if (_isDanmakuRegexRule(normalized)) return normalized;
  return '$_kRegexRulePrefix$normalized';
}

// ── XML 导入（轻量解析，不依赖 xml 包）──

DanmakuBlockRuleImportResult _parseDanmakuBlockRuleXmlImport(String raw) {
  if (raw.toLowerCase().contains('<!doctype')) {
    return const DanmakuBlockRuleImportResult(
        errorMessage: 'XML 屏蔽规则不支持 DOCTYPE');
  }
  final candidates = <String>[];
  var skippedDisabledCount = 0;
  try {
    // 轻量 XML 解析：提取 <item ...>...</item> / <filter ...>...</filter>。
    final itemPattern = RegExp(
      "<(item|filter)\\b[^>]*enabled=[\"']?([^\"'>\\s]*)[\"']?[^>]*>([\\s\\S]*?)</\\1>",
      caseSensitive: false,
    );
    for (final match in itemPattern.allMatches(raw)) {
      final enabledAttr = match.group(2)?.trim().toLowerCase() ?? '';
      final textContent = match.group(3)?.trim() ?? '';
      if (enabledAttr == 'false' || enabledAttr == '0') {
        skippedDisabledCount++;
      } else if (textContent.isNotEmpty) {
        candidates.add(textContent);
      }
    }
    // 兼容自闭合或无闭合标签的 <item value="..."/> 格式。
    final attrPattern = RegExp(
      "<(?:item|filter)\\b[^>]*\\bvalue=[\"']([^\"']+)[\"'][^>]*/?>",
      caseSensitive: false,
    );
    for (final match in attrPattern.allMatches(raw)) {
      final value = match.group(1)?.trim() ?? '';
      if (value.isNotEmpty) candidates.add(value);
    }
  } catch (e) {
    return DanmakuBlockRuleImportResult(
      skippedDisabledCount: skippedDisabledCount,
      errorMessage: 'XML 屏蔽规则格式无效：$e',
    );
  }
  return _buildDanmakuBlockRuleImportResult(
    candidates,
    skippedDisabledCount: skippedDisabledCount,
  );
}

// ── 匹配 ──

/// 单条规则匹配。
bool matchesDanmakuBlockRule(
  String content,
  String rule, {
  String userHash = '',
}) {
  final matcher = _resolveMatcher(rule);
  if (matcher == null) return false;
  return matcher.matches(content, userHash: userHash);
}

/// 多条规则匹配（任一命中即屏蔽）。
bool shouldBlockDanmakuByRules(
  String content,
  List<String> rules, {
  String userHash = '',
}) {
  if ((content.trim().isEmpty && userHash.trim().isEmpty) || rules.isEmpty) {
    return false;
  }
  final matchers = _compileDanmakuBlockRules(rules);
  if (matchers.isEmpty) return false;
  return matchers.any((m) => m.matches(content, userHash: userHash));
}

/// 编译规则列表为匹配器列表（预编译，多次匹配时复用）。
List<_DanmakuBlockRuleMatcher> _compileDanmakuBlockRules(List<String> rules) {
  return rules
      .map((r) => _resolveMatcher(r))
      .whereType<_DanmakuBlockRuleMatcher>()
      .toList(growable: false);
}

// ── 分区 / 合并 / 追加 ──

/// 将扁平规则列表按前缀分组为三段。
DanmakuBlockRuleSections partitionDanmakuBlockRules(List<String> rules) {
  final normalized = _distinct(
    rules.map((r) => r.trim()).where((s) => s.isNotEmpty).toList(),
  );
  return DanmakuBlockRuleSections(
    keywordRules: normalized
        .where((r) => _resolveGroup(r) == DanmakuBlockRuleGroup.keyword)
        .toList(growable: false),
    regexRules: normalized
        .where((r) => _resolveGroup(r) == DanmakuBlockRuleGroup.regex)
        .toList(growable: false),
    userHashRules: normalized
        .where((r) => _resolveGroup(r) == DanmakuBlockRuleGroup.userHash)
        .toList(growable: false),
  );
}

/// 合并三段规则为扁平列表（去重）。
List<String> mergeDanmakuBlockRuleSections({
  List<String> keywordRules = const [],
  List<String> regexRules = const [],
  List<String> userHashRules = const [],
}) {
  final normalizedKeywords = keywordRules
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
  final normalizedRegexRules = regexRules
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
  final normalizedUserHashRules = userHashRules
      .map(_normalizeDanmakuUserHashManagerInput)
      .whereType<String>()
      .toList(growable: false);
  return _distinct([
    ...normalizedKeywords,
    ...normalizedRegexRules,
    ...normalizedUserHashRules,
  ]);
}

/// 向已有规则文本追加一条规则。
String appendDanmakuBlockRule(String rawRules, String rule) {
  final normalized = _normalizeDanmakuBlockRuleForAppend(rule);
  final existing = parseDanmakuBlockRules(rawRules);
  if (normalized == null) return existing.join('\n');
  return _distinct([...existing, normalized]).join('\n');
}

/// 追加关键词规则。
String appendDanmakuKeywordBlockRule(String rawRules, String keyword) =>
    appendDanmakuBlockRule(rawRules, keyword);

/// 追加用户哈希规则（自动加 uid: 前缀）。
String appendDanmakuUserHashBlockRule(String rawRules, String userHash) {
  final normalized = _normalizeDanmakuUserHashManagerInput(userHash);
  if (normalized == null) return parseDanmakuBlockRules(rawRules).join('\n');
  return appendDanmakuBlockRule(rawRules, normalized);
}

// ── 内部：匹配器解析 ──

_DanmakuBlockRuleMatcher? _resolveMatcher(String rule) {
  final normalized = rule.trim();
  if (normalized.isEmpty) return null;

  final userHashRule = _normalizeDanmakuUserHashRule(normalized);
  if (userHashRule != null) {
    return _DanmakuUserHashMatcher(
      userHashRule.substring(_kUserHashRulePrefix.length),
    );
  }

  String? regexBody;
  if (normalized.toLowerCase().startsWith(_kRegexRulePrefix)) {
    regexBody = normalized.substring(_kRegexRulePrefix.length).trim();
  } else if (normalized.toLowerCase().startsWith(_kShortRegexRulePrefix)) {
    regexBody = normalized.substring(_kShortRegexRulePrefix.length).trim();
  } else if (normalized.length >= 2 &&
      normalized.startsWith('/') &&
      normalized.endsWith('/')) {
    regexBody = normalized.substring(1, normalized.length - 1).trim();
  }

  if (regexBody != null) {
    if (regexBody.isEmpty) return null;
    try {
      return _DanmakuRegexMatcher(
        RegExp(regexBody, caseSensitive: false),
      );
    } catch (_) {
      return null;
    }
  }

  return _DanmakuKeywordMatcher(normalized);
}

DanmakuBlockRuleGroup _resolveGroup(String rule) {
  final normalized = rule.trim();
  if (_normalizeDanmakuUserHashRule(normalized) != null) {
    return DanmakuBlockRuleGroup.userHash;
  }
  if (_isDanmakuRegexRule(normalized)) {
    return DanmakuBlockRuleGroup.regex;
  }
  return DanmakuBlockRuleGroup.keyword;
}

String? _normalizeDanmakuBlockRuleForAppend(String rule) {
  final normalized = rule.trim();
  if (normalized.isEmpty) return null;
  return _normalizeDanmakuUserHashRule(normalized) ?? normalized;
}

bool _isDanmakuRegexRule(String rule) {
  final lower = rule.toLowerCase();
  return lower.startsWith(_kRegexRulePrefix) ||
      lower.startsWith(_kShortRegexRulePrefix) ||
      (rule.length >= 2 && rule.startsWith('/') && rule.endsWith('/'));
}

String? _normalizeDanmakuUserHashRule(String rule) {
  final normalized = rule.trim();
  String? body;
  if (normalized.toLowerCase().startsWith(_kUserHashRulePrefix)) {
    body = normalized.substring(_kUserHashRulePrefix.length);
  } else if (normalized.toLowerCase().startsWith(_kUserRulePrefix)) {
    body = normalized.substring(_kUserRulePrefix.length);
  } else if (normalized.toLowerCase().startsWith(_kHashRulePrefix)) {
    body = normalized.substring(_kHashRulePrefix.length);
  } else if (normalized.startsWith('@')) {
    body = normalized.substring(1);
  }
  body = body?.trim();
  if (body == null || body.isEmpty) return null;
  return '$_kUserHashRulePrefix$body';
}

String? _normalizeDanmakuUserHashManagerInput(String rule) {
  final normalized = rule.trim();
  if (normalized.isEmpty) return null;
  return _normalizeDanmakuUserHashRule(normalized) ??
      '$_kUserHashRulePrefix$normalized';
}

// ── 内部工具 ──

List<String> _distinct(List<String> list) {
  // 保持顺序的去重。
  final seen = <String>{};
  return list.where((s) => seen.add(s)).toList(growable: false);
}
