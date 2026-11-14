import 'dart:convert';

import 'package:hive_ce/hive.dart';

/// 插件状态存储抽象（便于单测注入内存实现）。
///
/// 对应 BiliPai `PluginStore` 的三类 key：
/// - `enabled.<id>`：内置插件启停
/// - `config.<id>`：插件配置（JSON）
/// - `data.<id>.<name>`：插件私有数据（JSON）
///
/// 规则插件另有 `rule.enabled.<id>` / `rule.stats.<id>` 两个命名空间，
/// 与内置插件互不干扰。
abstract interface class PluginStateStore {
  bool? enabledOrNull(String pluginId);
  Future<void> setEnabled(String pluginId, bool enabled);

  Map<String, dynamic>? config(String pluginId);
  Future<void> setConfig(String pluginId, Map<String, dynamic>? config);

  Object? data(String pluginId, String name);
  Future<void> setData(String pluginId, String name, Object? value);

  bool get effectHintsEnabled;
  Future<void> setEffectHintsEnabled(bool enabled);

  bool? ruleEnabledOrNull(String pluginId);
  Future<void> setRuleEnabled(String pluginId, bool enabled);

  int ruleStats(String pluginId);
  Future<void> setRuleStats(String pluginId, int value);

  Future<void> removeRuleState(String pluginId);
}

/// Hive 实现：落在独立的 `plugin` box，不污染现有设置 box。
class HivePluginStateStore implements PluginStateStore {
  HivePluginStateStore(this._box);

  final Box<dynamic> _box;

  static const String _enabledPrefix = 'enabled.';
  static const String _configPrefix = 'config.';
  static const String _dataPrefix = 'data.';
  static const String _effectHintsKey = 'effectHints';
  static const String _ruleEnabledPrefix = 'rule.enabled.';
  static const String _ruleStatsPrefix = 'rule.stats.';

  @override
  bool? enabledOrNull(String pluginId) {
    final value = _box.get('$_enabledPrefix$pluginId');
    return value is bool ? value : null;
  }

  @override
  Future<void> setEnabled(String pluginId, bool enabled) =>
      _box.put('$_enabledPrefix$pluginId', enabled);

  @override
  Map<String, dynamic>? config(String pluginId) {
    final raw = _box.get('$_configPrefix$pluginId');
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  @override
  Future<void> setConfig(String pluginId, Map<String, dynamic>? config) {
    final key = '$_configPrefix$pluginId';
    if (config == null) return _box.delete(key);
    return _box.put(key, jsonEncode(config));
  }

  @override
  Object? data(String pluginId, String name) {
    final raw = _box.get('$_dataPrefix$pluginId.$name');
    if (raw is String && raw.isNotEmpty) {
      try {
        return jsonDecode(raw);
      } catch (_) {
        return raw;
      }
    }
    return raw;
  }

  @override
  Future<void> setData(String pluginId, String name, Object? value) {
    final key = '$_dataPrefix$pluginId.$name';
    if (value == null) return _box.delete(key);
    return _box.put(key, jsonEncode(value));
  }

  @override
  bool get effectHintsEnabled =>
      _box.get(_effectHintsKey, defaultValue: false) as bool;

  @override
  Future<void> setEffectHintsEnabled(bool enabled) =>
      _box.put(_effectHintsKey, enabled);

  @override
  bool? ruleEnabledOrNull(String pluginId) {
    final value = _box.get('$_ruleEnabledPrefix$pluginId');
    return value is bool ? value : null;
  }

  @override
  Future<void> setRuleEnabled(String pluginId, bool enabled) =>
      _box.put('$_ruleEnabledPrefix$pluginId', enabled);

  @override
  int ruleStats(String pluginId) {
    final value = _box.get('$_ruleStatsPrefix$pluginId');
    return value is int && value > 0 ? value : 0;
  }

  @override
  Future<void> setRuleStats(String pluginId, int value) =>
      _box.put('$_ruleStatsPrefix$pluginId', value < 0 ? 0 : value);

  @override
  Future<void> removeRuleState(String pluginId) async {
    await _box.delete('$_ruleEnabledPrefix$pluginId');
    await _box.delete('$_ruleStatsPrefix$pluginId');
  }
}
