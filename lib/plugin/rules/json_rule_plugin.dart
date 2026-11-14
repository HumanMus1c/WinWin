import 'package:winwin/plugin/api/plugin_capability.dart';

/// JSON 规则插件数据模型（移植自 BiliPai `JsonRulePlugin.kt`）。
///
/// 支持两种规则写法：
/// 1. 旧格式（字段直写）：`{field, op, value, action, style?}`
/// 2. 新格式（复合条件）：`{condition: {and|or|field...}, action, style?}`
final class JsonRulePlugin {
  const JsonRulePlugin({
    required this.id,
    required this.name,
    required this.type,
    required this.rules,
    this.description = '',
    this.version = '1.0.0',
    this.author = 'Unknown',
    this.iconUrl,
  });

  final String id;
  final String name;
  final String description;
  final String version;
  final String author;

  /// `feed`（推荐流）或 `danmaku`（弹幕）。
  final String type;

  final String? iconUrl;
  final List<JsonRule> rules;

  static const String typeFeed = 'feed';
  static const String typeDanmaku = 'danmaku';

  bool get isFeed => type == typeFeed;
  bool get isDanmaku => type == typeDanmaku;

  Set<PluginCapability> get capabilities {
    final result = <PluginCapability>{};
    if (isFeed) result.add(PluginCapability.recommendationCandidates);
    if (isDanmaku) result.add(PluginCapability.danmakuMutation);
    if (iconUrl != null && iconUrl!.isNotEmpty) {
      result.add(PluginCapability.network);
    }
    return result;
  }

  PluginCapabilityManifest get capabilityManifest => PluginCapabilityManifest(
        pluginId: id,
        displayName: name,
        version: version,
        entryPoint: 'json:$id',
        capabilities: capabilities,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'version': version,
        'author': author,
        'type': type,
        if (iconUrl != null) 'iconUrl': iconUrl,
        'rules': [for (final rule in rules) rule.toJson()],
      };

  /// 从解码后的 JSON 构建；非法内容抛出 [FormatException]（带中文原因）。
  factory JsonRulePlugin.fromJson(Map<String, dynamic> json) =>
      _parseJsonRulePlugin(json);
}

/// 单条规则。
final class JsonRule {
  const JsonRule({
    required this.condition,
    required this.action,
    this.style,
  });

  final RuleCondition condition;

  /// `hide` 或 `highlight`。
  final String action;

  final DanmakuHighlightStyle? style;

  static const String actionHide = 'hide';
  static const String actionHighlight = 'highlight';

  bool get isHide => action == actionHide;
  bool get isHighlight => action == actionHighlight;

  Map<String, dynamic> toJson() => {
        'condition': condition.toJson(),
        'action': action,
        if (style != null) 'style': style!.toJson(),
      };
}

/// 条件表达式（AND / OR 可嵌套）。
sealed class RuleCondition {
  const RuleCondition();

  Map<String, dynamic> toJson();
}

final class SimpleRuleCondition extends RuleCondition {
  const SimpleRuleCondition({
    required this.field,
    required this.op,
    required this.value,
  });

  final String field;
  final String op;
  final Object? value;

  @override
  Map<String, dynamic> toJson() => {
        'field': field,
        'op': op,
        'value': value,
      };
}

final class AndRuleCondition extends RuleCondition {
  const AndRuleCondition(this.conditions);

  final List<RuleCondition> conditions;

  @override
  Map<String, dynamic> toJson() => {
        'and': [for (final condition in conditions) condition.toJson()],
      };
}

final class OrRuleCondition extends RuleCondition {
  const OrRuleCondition(this.conditions);

  final List<RuleCondition> conditions;

  @override
  Map<String, dynamic> toJson() => {
        'or': [for (final condition in conditions) condition.toJson()],
      };
}

/// 高亮样式（仅弹幕规则使用）。
final class DanmakuHighlightStyle {
  const DanmakuHighlightStyle({
    this.colorValue,
    this.bold = false,
    this.scale = 1.0,
  });

  /// 0xRRGGBB；null 表示沿用原色。
  final int? colorValue;
  final bool bold;
  final double scale;

  int? get argb => colorValue == null ? null : 0xFF000000 | colorValue!;

  Map<String, dynamic> toJson() => {
        if (colorValue != null)
          'color': '#${colorValue!.toRadixString(16).padLeft(6, '0').toUpperCase()}',
        'bold': bold,
        'scale': scale,
      };
}

// ════════════════════════════════════════════════════════════════
// 解析与校验
// ════════════════════════════════════════════════════════════════

final RegExp _pluginIdPattern = RegExp(r'^[A-Za-z0-9_.-]{1,64}$');
final RegExp _hexColorPattern = RegExp(r'^#?([0-9a-fA-F]{6})$');

const int kMaxRulesPerPlugin = 200;
const int kMaxConditionDepth = 8;
const int kMaxRegexPatternLength = 256;

JsonRulePlugin _parseJsonRulePlugin(Map<String, dynamic> json) {
  final id = _readString(json['id']);
  if (id == null || !_pluginIdPattern.hasMatch(id)) {
    throw const FormatException('插件 id 无效（仅支持字母数字/._-，长度 1-64）');
  }
  final name = _readString(json['name']);
  if (name == null || name.trim().isEmpty) {
    throw const FormatException('插件缺少 name');
  }
  final type = _readString(json['type']) ?? '';
  if (type != JsonRulePlugin.typeFeed && type != JsonRulePlugin.typeDanmaku) {
    throw const FormatException('插件 type 必须是 feed 或 danmaku');
  }
  final rawRules = json['rules'];
  if (rawRules is! List || rawRules.isEmpty) {
    throw const FormatException('插件 rules 不能为空');
  }
  if (rawRules.length > kMaxRulesPerPlugin) {
    throw const FormatException('插件规则数量超过上限（200 条）');
  }

  final rules = <JsonRule>[];
  for (var index = 0; index < rawRules.length; index++) {
    final raw = rawRules[index];
    if (raw is! Map) {
      throw FormatException('第 ${index + 1} 条规则不是 JSON 对象');
    }
    rules.add(_parseRule(Map<String, dynamic>.from(raw), index));
  }

  final iconUrl = _readString(json['iconUrl']);
  if (iconUrl != null && iconUrl.isNotEmpty) {
    final uri = Uri.tryParse(iconUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const FormatException('iconUrl 必须是 http/https 地址');
    }
  }

  return JsonRulePlugin(
    id: id,
    name: name.trim(),
    description: _readString(json['description']) ?? '',
    version: _readString(json['version']) ?? '1.0.0',
    author: _readString(json['author']) ?? 'Unknown',
    type: type,
    iconUrl: iconUrl,
    rules: rules,
  );
}

JsonRule _parseRule(Map<String, dynamic> json, int index) {
  final action = _readString(json['action']) ?? '';
  if (action != JsonRule.actionHide && action != JsonRule.actionHighlight) {
    throw FormatException('第 ${index + 1} 条规则 action 必须是 hide 或 highlight');
  }

  final rawCondition = json['condition'];
  final RuleCondition condition;
  if (rawCondition != null) {
    if (rawCondition is! Map) {
      throw FormatException('第 ${index + 1} 条规则 condition 必须是 JSON 对象');
    }
    condition = _parseCondition(
      Map<String, dynamic>.from(rawCondition),
      index,
      depth: 0,
    );
  } else {
    condition = _parseCondition(json, index, depth: 0);
  }

  final rawStyle = json['style'];
  DanmakuHighlightStyle? style;
  if (rawStyle is Map) {
    style = _parseStyle(Map<String, dynamic>.from(rawStyle), index);
  } else if (action == JsonRule.actionHighlight) {
    style = const DanmakuHighlightStyle();
  }

  return JsonRule(condition: condition, action: action, style: style);
}

RuleCondition _parseCondition(
  Map<String, dynamic> json,
  int ruleIndex, {
  required int depth,
}) {
  if (depth > kMaxConditionDepth) {
    throw FormatException('第 ${ruleIndex + 1} 条规则条件嵌套过深');
  }

  final rawAnd = json['and'];
  if (rawAnd != null) {
    if (rawAnd is! List || rawAnd.isEmpty) {
      throw FormatException('第 ${ruleIndex + 1} 条规则 and 必须是非空数组');
    }
    return AndRuleCondition([
      for (final child in rawAnd)
        if (child is Map)
          _parseCondition(
            Map<String, dynamic>.from(child),
            ruleIndex,
            depth: depth + 1,
          )
        else
          throw FormatException('第 ${ruleIndex + 1} 条规则 and 子项必须是对象'),
    ]);
  }

  final rawOr = json['or'];
  if (rawOr != null) {
    if (rawOr is! List || rawOr.isEmpty) {
      throw FormatException('第 ${ruleIndex + 1} 条规则 or 必须是非空数组');
    }
    return OrRuleCondition([
      for (final child in rawOr)
        if (child is Map)
          _parseCondition(
            Map<String, dynamic>.from(child),
            ruleIndex,
            depth: depth + 1,
          )
        else
          throw FormatException('第 ${ruleIndex + 1} 条规则 or 子项必须是对象'),
    ]);
  }

  final field = _readString(json['field']);
  final op = _readString(json['op']);
  if (field == null || field.isEmpty || op == null || op.isEmpty) {
    throw FormatException('第 ${ruleIndex + 1} 条规则缺少 field/op');
  }
  if (!json.containsKey('value')) {
    throw FormatException('第 ${ruleIndex + 1} 条规则缺少 value');
  }

  final value = _normalizeValue(json['value']);
  if (op == 'regex') {
    final pattern = value?.toString() ?? '';
    if (pattern.length > kMaxRegexPatternLength) {
      throw FormatException('第 ${ruleIndex + 1} 条规则正则过长（上限 256 字符）');
    }
    try {
      RegExp(pattern);
    } catch (_) {
      throw FormatException('第 ${ruleIndex + 1} 条规则正则无法编译：$pattern');
    }
  }

  return SimpleRuleCondition(field: field, op: op, value: value);
}

DanmakuHighlightStyle _parseStyle(Map<String, dynamic> json, int ruleIndex) {
  int? colorValue;
  final rawColor = json['color'];
  if (rawColor is String) {
    final match = _hexColorPattern.firstMatch(rawColor.trim());
    if (match == null) {
      throw FormatException('第 ${ruleIndex + 1} 条规则颜色格式无效（示例 #FFD700）');
    }
    colorValue = int.parse(match.group(1)!, radix: 16);
  }
  final rawScale = json['scale'];
  final scale = rawScale is num ? rawScale.toDouble() : 1.0;
  if (scale < 0.5 || scale > 3.0) {
    throw FormatException('第 ${ruleIndex + 1} 条规则 scale 必须在 0.5-3.0');
  }
  return DanmakuHighlightStyle(
    colorValue: colorValue,
    bold: json['bold'] == true,
    scale: scale,
  );
}

Object? _normalizeValue(Object? value) {
  if (value is num || value is String || value is bool) return value;
  if (value is List) {
    return [
      for (final item in value)
        if (item is num || item is String || item is bool) item,
    ];
  }
  return null;
}

String? _readString(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}
