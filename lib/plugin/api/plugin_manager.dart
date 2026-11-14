import 'package:flutter/foundation.dart';

import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/core/log/app_logger.dart';
import 'package:winwin/core/storage/storage.dart';

import 'app_plugin.dart';
import 'builtin_plugin_registry.dart';
import 'plugin_state_store.dart';

/// 内置插件调度中心（移植自 BiliPai `PluginManager.kt`）。
///
/// 与上游的差异：
/// - 无 Android Context，状态存储由 [PluginStateStore] 注入；
/// - 插件列表用 [ValueNotifier] 暴露，供设置页直接监听；
/// - 外部 JSON 规则插件由 `RulePluginManager` 独立管理，不注册进本表。
class PluginManager {
  PluginManager._(this.store)
      : registry = BuiltinPluginRegistry(
          store: store,
          onFailure: (pluginId, error, stackTrace) {
            AppLogger.e(
              'PluginManager',
              'plugin lifecycle failed: $pluginId ($error)',
              error: error,
              stackTrace: stackTrace,
            );
          },
        );

  static PluginManager? _instance;

  /// bootstrap 完成后可用；未初始化时返回 null（设置页之外的早期调用需判空）。
  static PluginManager? get maybeInstance => _instance;

  static PluginManager get instance {
    final current = _instance;
    if (current == null) {
      throw StateError('PluginManager.initialize() has not been called');
    }
    return current;
  }

  /// 便捷查询：未初始化或插件未知时返回 false。
  static bool enabled(String pluginId) =>
      maybeInstance?.isEnabled(pluginId) ?? false;

  final PluginStateStore store;
  final BuiltinPluginRegistry registry;

  ValueListenable<List<PluginInfo>> get plugins => registry.plugins;

  final Map<String, DateTime> _lastHintAt = {};

  static Future<PluginManager> initialize({PluginStateStore? store}) async {
    final current = _instance;
    if (current != null) return current;
    final manager =
        PluginManager._(store ?? HivePluginStateStore(GStorage.plugin));
    _instance = manager;
    AppLogger.w('PluginManager', 'initialized');
    return manager;
  }

  Future<void> registerAll(Iterable<BuiltinPlugin> list) async {
    for (final plugin in list) {
      await registry.register(plugin);
      final info = registry.infoOf(plugin.id);
      AppLogger.w(
        'PluginManager',
        'registered ${plugin.id} enabled=${info?.enabled ?? false}',
      );
    }
  }

  PluginInfo? infoOf(String pluginId) => registry.infoOf(pluginId);

  bool isEnabled(String pluginId) => registry.infoOf(pluginId)?.enabled ?? false;

  Future<bool> setEnabled(String pluginId, bool enabled) async {
    final ok = await registry.setEnabled(pluginId, enabled);
    AppLogger.w(
      'PluginManager',
      'setEnabled $pluginId=$enabled ok=$ok',
    );
    return ok;
  }

  T? find<T extends AppPlugin>() {
    for (final info in registry.plugins.value) {
      final plugin = info.plugin;
      if (plugin is T) return plugin as T;
    }
    return null;
  }

  List<T> enabledOfType<T extends AppPlugin>() => [
        for (final info in registry.plugins.value)
          if (info.enabled && info.plugin is T) info.plugin as T,
      ];

  int get enabledCount =>
      registry.plugins.value.where((info) => info.enabled).length;

  bool get effectHintsEnabled => store.effectHintsEnabled;

  Future<void> setEffectHintsEnabled(bool enabled) =>
      store.setEffectHintsEnabled(enabled);

  /// 插件生效提示（对应 BiliPai `PluginEffectHintBus`）。
  ///
  /// - 全局开关关闭时静默；
  /// - 同一文案在 [cooldown] 内只提示一次，避免过滤批次/弹幕批次刷屏。
  void emitHint(
    String message, {
    Duration cooldown = const Duration(seconds: 8),
  }) {
    if (!effectHintsEnabled || message.isEmpty) return;
    final now = DateTime.now();
    final last = _lastHintAt[message];
    if (last != null && now.difference(last) < cooldown) return;
    _lastHintAt[message] = now;
    showAppSnackBar(message);
  }
}
