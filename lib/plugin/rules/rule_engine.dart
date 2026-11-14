import 'json_rule_plugin.dart';
import 'rule_regex_cache.dart';

/// 字段取值回调：返回 null 表示该字段不存在（条件按不命中处理）。
typedef RuleFieldGetter = Object? Function(String field);

/// 规则引擎（移植自 BiliPai `RuleEngine.kt`）。
///
/// 纯函数、无状态（除正则缓存），便于单测与在滚动帧外预编译。
class RuleEngine {
  RuleEngine({RuleRegexCache? regexCache})
      : _regexCache = regexCache ?? RuleRegexCache();

  final RuleRegexCache _regexCache;

  /// 任一条 hide 规则命中即返回 true。
  bool shouldHide(List<JsonRule> rules, RuleFieldGetter getter) {
    for (final rule in rules) {
      if (!rule.isHide) continue;
      if (evaluate(rule.condition, getter)) return true;
    }
    return false;
  }

  /// 返回第一条命中的 highlight 样式；无命中返回 null。
  DanmakuHighlightStyle? highlightStyle(
    List<JsonRule> rules,
    RuleFieldGetter getter,
  ) {
    for (final rule in rules) {
      if (!rule.isHighlight) continue;
      if (evaluate(rule.condition, getter)) return rule.style;
    }
    return null;
  }

  bool evaluate(RuleCondition condition, RuleFieldGetter getter) {
    switch (condition) {
      case SimpleRuleCondition():
        return _evaluateSimple(condition, getter);
      case AndRuleCondition():
        for (final child in condition.conditions) {
          if (!evaluate(child, getter)) return false;
        }
        return true;
      case OrRuleCondition():
        for (final child in condition.conditions) {
          if (evaluate(child, getter)) return true;
        }
        return false;
    }
  }

  bool _evaluateSimple(SimpleRuleCondition condition, RuleFieldGetter getter) {
    final fieldValue = getter(condition.field);
    if (fieldValue == null) return false;

    switch (condition.op) {
      case 'eq':
        return _equals(fieldValue, condition.value);
      case 'ne':
        return !_equals(fieldValue, condition.value);
      case 'lt':
        return _compareNumber(fieldValue, condition.value, (a, b) => a < b);
      case 'le':
        return _compareNumber(fieldValue, condition.value, (a, b) => a <= b);
      case 'gt':
        return _compareNumber(fieldValue, condition.value, (a, b) => a > b);
      case 'ge':
        return _compareNumber(fieldValue, condition.value, (a, b) => a >= b);
      case 'contains':
        return fieldValue
            .toString()
            .toLowerCase()
            .contains(_asText(condition.value).toLowerCase());
      case 'startsWith':
        return fieldValue
            .toString()
            .toLowerCase()
            .startsWith(_asText(condition.value).toLowerCase());
      case 'endsWith':
        return fieldValue
            .toString()
            .toLowerCase()
            .endsWith(_asText(condition.value).toLowerCase());
      case 'regex':
        final regex = _regexCache.get(_asText(condition.value));
        return regex?.hasMatch(fieldValue.toString()) ?? false;
      case 'in':
        final candidates = condition.value;
        if (candidates is! List) return false;
        for (final candidate in candidates) {
          if (_equals(fieldValue, candidate)) return true;
        }
        return false;
      default:
        return false;
    }
  }

  bool _equals(Object fieldValue, Object? ruleValue) {
    if (fieldValue is num) {
      final target = ruleValue is num
          ? ruleValue
          : num.tryParse(ruleValue?.toString() ?? '');
      return target != null && fieldValue == target;
    }
    if (fieldValue is bool) {
      if (ruleValue is bool) return fieldValue == ruleValue;
      final text = ruleValue?.toString().toLowerCase();
      return (text == 'true' && fieldValue) || (text == 'false' && !fieldValue);
    }
    return fieldValue.toString() == ruleValue?.toString();
  }

  bool _compareNumber(
    Object fieldValue,
    Object? ruleValue,
    bool Function(double a, double b) comparator,
  ) {
    final a = _asDouble(fieldValue);
    final b = _asDouble(ruleValue);
    if (a == null || b == null) return false;
    return comparator(a, b);
  }

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static String _asText(Object? value) => value?.toString() ?? '';

  void clearCache() => _regexCache.clear();
}
