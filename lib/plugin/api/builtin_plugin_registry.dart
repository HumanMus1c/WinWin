import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_plugin.dart';
import 'plugin_state_store.dart';

/// 内置插件注册表（移植自 BiliPai `BuiltinPluginRegistry.kt`）。
///
/// 关键语义与上游一致：
/// - 所有注册 / 启停操作串行执行（Dart 单线程下用 Future 链模拟 Mutex）；
/// - 启用失败时调用 `onDisable` 回滚，插件保持禁用并上报错误；
/// - 未注册插件的启停请求先落盘，注册时再应用（pending override）；
/// - 启用状态写入成功后，才发布新的执行状态。
class BuiltinPluginRegistry {
  BuiltinPluginRegistry({
    required this.store,
    this.onFailure,
    this.onEnabledChanged,
  });

  final PluginStateStore store;

  final void Function(String pluginId, Object error, StackTrace stack)? onFailure;
  final void Function(BuiltinPlugin plugin, bool enabled)? onEnabledChanged;

  final ValueNotifier<List<PluginInfo>> plugins =
      ValueNotifier<List<PluginInfo>>(const <PluginInfo>[]);

  final Map<String, bool> _pendingEnabledOverrides = {};
  final Set<String> _readyPluginIds = {};
  final Map<String, Completer<void>> _readyCompleters = {};

  Future<void> _tail = Future<void>.value();

  /// 串行化所有状态变更。
  Future<T> _serialize<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> register(BuiltinPlugin plugin) => _serialize(() async {
        if (plugins.value.any((info) => info.plugin.id == plugin.id)) return;

        bool storedEnabled;
        try {
          storedEnabled = store.enabledOrNull(plugin.id) ?? plugin.defaultEnabled;
        } catch (error, stackTrace) {
          onFailure?.call(plugin.id, error, stackTrace);
          _markReady(plugin.id);
          return;
        }

        final requestedEnabled =
            _pendingEnabledOverrides.remove(plugin.id) ?? storedEnabled;
        var enabled = false;
        if (requestedEnabled) {
          try {
            await plugin.onEnable();
            enabled = true;
          } catch (error, stackTrace) {
            await _restoreLifecycle(plugin, enabled: false);
            plugins.value = [
              ...plugins.value,
              PluginInfo(plugin: plugin, enabled: false),
            ];
            onFailure?.call(plugin.id, error, stackTrace);
            _markReady(plugin.id);
            return;
          }
        }

        plugins.value = [
          ...plugins.value,
          PluginInfo(plugin: plugin, enabled: enabled),
        ];
        _markReady(plugin.id);
      });

  /// 返回是否成功（失败时已回滚并上报）。
  Future<bool> setEnabled(String pluginId, bool enabled) =>
      _serialize(() async {
        final index =
            plugins.value.indexWhere((info) => info.plugin.id == pluginId);
        if (index < 0) {
          try {
            await store.setEnabled(pluginId, enabled);
            _pendingEnabledOverrides[pluginId] = enabled;
            return true;
          } catch (error, stackTrace) {
            onFailure?.call(pluginId, error, stackTrace);
            return false;
          }
        }

        final info = plugins.value[index];
        if (info.enabled == enabled) return true;

        try {
          if (enabled) {
            await info.plugin.onEnable();
          } else {
            await info.plugin.onDisable();
          }
          await store.setEnabled(pluginId, enabled);
        } catch (error, stackTrace) {
          await _restoreLifecycle(info.plugin, enabled: info.enabled);
          onFailure?.call(pluginId, error, stackTrace);
          return false;
        }

        final next = List<PluginInfo>.of(plugins.value);
        next[index] = info.copyWith(enabled: enabled);
        plugins.value = next;

        try {
          onEnabledChanged?.call(info.plugin, enabled);
        } catch (error, stackTrace) {
          // 通知失败不能回滚已提交的生命周期与存储写入。
          onFailure?.call(pluginId, error, stackTrace);
        }
        return true;
      });

  Future<void> awaitPluginReady(String pluginId) {
    if (_readyPluginIds.contains(pluginId)) return Future<void>.value();
    return (_readyCompleters[pluginId] ??= Completer<void>()).future;
  }

  /// 已注册插件的当前状态。
  PluginInfo? infoOf(String pluginId) {
    for (final info in plugins.value) {
      if (info.plugin.id == pluginId) return info;
    }
    return null;
  }

  Future<void> _restoreLifecycle(
    BuiltinPlugin plugin, {
    required bool enabled,
  }) async {
    try {
      if (enabled) {
        await plugin.onEnable();
      } else {
        await plugin.onDisable();
      }
    } catch (error, stackTrace) {
      onFailure?.call(plugin.id, error, stackTrace);
    }
  }

  void _markReady(String pluginId) {
    _readyPluginIds.add(pluginId);
    final completer = _readyCompleters.remove(pluginId);
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }
}
