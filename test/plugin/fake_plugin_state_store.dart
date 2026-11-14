import 'package:winwin/plugin/api/plugin_state_store.dart';

/// 测试用内存状态存储（不依赖 Hive）。
class FakePluginStateStore implements PluginStateStore {
  final Map<String, bool> enabled = {};
  final Map<String, Map<String, dynamic>?> configs = {};
  final Map<String, Object?> dataValues = {};
  final Map<String, bool> ruleEnabled = {};
  final Map<String, int> statsByPlugin = {};
  bool effectHints = false;

  String _dataKey(String pluginId, String name) => '$pluginId.$name';

  @override
  bool? enabledOrNull(String pluginId) => enabled[pluginId];

  @override
  Future<void> setEnabled(String pluginId, bool value) async {
    enabled[pluginId] = value;
  }

  @override
  Map<String, dynamic>? config(String pluginId) => configs[pluginId];

  @override
  Future<void> setConfig(String pluginId, Map<String, dynamic>? config) async {
    configs[pluginId] = config;
  }

  @override
  Object? data(String pluginId, String name) =>
      dataValues[_dataKey(pluginId, name)];

  @override
  Future<void> setData(String pluginId, String name, Object? value) async {
    dataValues[_dataKey(pluginId, name)] = value;
  }

  @override
  bool get effectHintsEnabled => effectHints;

  @override
  Future<void> setEffectHintsEnabled(bool value) async {
    effectHints = value;
  }

  @override
  bool? ruleEnabledOrNull(String pluginId) => ruleEnabled[pluginId];

  @override
  Future<void> setRuleEnabled(String pluginId, bool value) async {
    ruleEnabled[pluginId] = value;
  }

  @override
  int ruleStats(String pluginId) => statsByPlugin[pluginId] ?? 0;

  @override
  Future<void> setRuleStats(String pluginId, int value) async {
    statsByPlugin[pluginId] = value;
  }

  @override
  Future<void> removeRuleState(String pluginId) async {
    ruleEnabled.remove(pluginId);
    statsByPlugin.remove(pluginId);
  }
}
