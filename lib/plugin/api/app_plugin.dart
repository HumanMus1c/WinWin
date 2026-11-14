import 'package:flutter/widgets.dart';

import 'plugin_capability.dart';

/// 插件生命周期契约（移植自 BiliPai `plugin-sdk/Plugin.kt`）。
///
/// 只约束「身份 + 启停」；具体能力（推荐流过滤 / 弹幕改写 / 播放器控制）
/// 由各插件按需实现额外的接口或静态入口，避免为单一插件膨胀基类。
abstract class AppPlugin {
  String get id;
  String get name;
  String get version;

  Set<PluginCapability> get capabilities;

  /// 首次安装（无持久化状态）时是否默认启用。
  bool get defaultEnabled => false;

  PluginCapabilityManifest get capabilityManifest => PluginCapabilityManifest(
        pluginId: id,
        displayName: name,
        version: version,
        entryPoint: runtimeType.toString(),
        capabilities: capabilities,
      );

  Future<void> onEnable();

  Future<void> onDisable();
}

/// 内置插件：额外提供描述、作者与设置页内容（对应 BiliPai `BuiltinPlugin`）。
abstract class BuiltinPlugin extends AppPlugin {
  String get description;

  String get author => 'WinWin';

  /// 插件详情页的配置区；无配置返回空。
  Widget buildSettings(BuildContext context) => const SizedBox.shrink();
}

/// 内置插件注册快照（对应 BiliPai `PluginInfo`）。
@immutable
class PluginInfo {
  const PluginInfo({required this.plugin, required this.enabled});

  final BuiltinPlugin plugin;
  final bool enabled;

  PluginInfo copyWith({bool? enabled}) =>
      PluginInfo(plugin: plugin, enabled: enabled ?? this.enabled);
}
