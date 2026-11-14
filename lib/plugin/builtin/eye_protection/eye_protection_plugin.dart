import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:winwin/core/shell/app_dialogs.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/pages/setting/widgets/normal_item.dart';
import 'package:winwin/pages/setting/widgets/select_dialog.dart';
import 'package:winwin/pages/setting/widgets/slider_dialog.dart';
import 'package:winwin/plugin/api/app_plugin.dart';
import 'package:winwin/plugin/api/plugin_capability.dart';
import 'package:winwin/plugin/api/plugin_manager.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/app_components.dart';

import 'eye_protection_policy.dart';

/// 护眼模式插件：全应用暖色/压暗叠色 + 夜间时段。
///
/// 桌面端限制：只做应用内滤镜，不修改系统亮度；窗口原生标题栏不在覆盖范围。
class EyeProtectionPlugin extends BuiltinPlugin {
  static const String pluginId = 'eye_protection';

  /// 全局叠色参数；应用壳监听后渲染覆盖层。
  static final ValueNotifier<EyeProtectionVisual?> visualNotifier =
      ValueNotifier<EyeProtectionVisual?>(null);

  EyeProtectionConfig _config = const EyeProtectionConfig();
  bool _loaded = false;
  bool _active = false;
  Timer? _timer;

  @override
  String get id => pluginId;

  @override
  String get name => '护眼模式';

  @override
  String get description => '降低蓝光与亮度：全应用暖色叠色，支持夜间时段自动开启';

  @override
  String get version => '1.0.0';

  @override
  String get author => 'BiliPai';

  @override
  Set<PluginCapability> get capabilities => {
        PluginCapability.pluginStorage,
      };

  @override
  bool get defaultEnabled => false;

  EyeProtectionConfig get config => _config;

  @override
  Future<void> onEnable() async {
    ensureLoaded();
    _active = true;
    _startTimer();
    refresh();
  }

  @override
  Future<void> onDisable() async {
    _active = false;
    _timer?.cancel();
    _timer = null;
    visualNotifier.value = null;
  }

  void ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    _config = EyeProtectionConfig.fromJson(
      PluginManager.instance.store.config(pluginId),
    );
  }

  Future<void> updateConfig(EyeProtectionConfig next) async {
    _config = next;
    _loaded = true;
    await PluginManager.instance.store.setConfig(pluginId, next.toJson());
    _restartTimerIfNeeded();
    refresh();
  }

  void refresh() {
    // 注意：onEnable 阶段注册表尚未发布 enabled=true，故用本地 _active 判定，
    // 不能依赖 PluginManager.enabled（否则启用后要等 30s 定时器才生效）。
    if (!_active) {
      visualNotifier.value = null;
      return;
    }
    visualNotifier.value = EyeProtectionPolicy.resolve(_config, DateTime.now());
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
  }

  void _restartTimerIfNeeded() {
    if (_config.nightModeEnabled) {
      if (_timer == null || !_timer!.isActive) _startTimer();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  Widget buildSettings(BuildContext context) => _EyeProtectionSettings(this);
}

class _EyeProtectionSettings extends StatefulWidget {
  const _EyeProtectionSettings(this.plugin);

  final EyeProtectionPlugin plugin;

  @override
  State<_EyeProtectionSettings> createState() => _EyeProtectionSettingsState();
}

class _EyeProtectionSettingsState extends State<_EyeProtectionSettings> {
  late EyeProtectionConfig _config;

  @override
  void initState() {
    super.initState();
    widget.plugin.ensureLoaded();
    _config = widget.plugin.config;
  }

  Future<void> _update(EyeProtectionConfig next) async {
    setState(() => _config = next);
    await widget.plugin.updateConfig(next);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: Style.lg, bottom: Style.sm),
          child: Text(
            '滤镜参数',
            style: tokens.text.labelMedium?.copyWith(
              color: tokens.colors.outline,
            ),
          ),
        ),
        AppGroup(
          children: [
            NormalItem(
              title: '压暗强度',
              subtitle: '当前：${(_config.dim * 100).round()}%',
              leading: AppIcon(AppIcons.eye()),
              onTap: (dialogContext, refresh) async {
                final value = await showAppDialog<double>(
                  context: dialogContext,
                  builder: (_) => AppSliderDialog(
                    title: '压暗强度',
                    value: _config.dim * 100,
                    min: 0,
                    max: 60,
                    divisions: 60,
                    suffix: '%',
                    decimals: 0,
                  ),
                );
                if (value == null) return;
                await _update(_config.copyWith(dim: value / 100));
                refresh();
              },
            ),
            NormalItem(
              title: '暖色强度',
              subtitle: '当前：${(_config.warmth * 100).round()}%',
              leading: AppIcon(AppIcons.palette()),
              onTap: (dialogContext, refresh) async {
                final value = await showAppDialog<double>(
                  context: dialogContext,
                  builder: (_) => AppSliderDialog(
                    title: '暖色强度',
                    value: _config.warmth * 100,
                    min: 0,
                    max: 40,
                    divisions: 40,
                    suffix: '%',
                    decimals: 0,
                  ),
                );
                if (value == null) return;
                await _update(_config.copyWith(warmth: value / 100));
                refresh();
              },
            ),
            AppListItem(
              icon: AppIcon(AppIcons.danmaku()),
              title: '夜间自动开启',
              subtitle: '仅在设定时段内应用滤镜',
              trailing: AppSwitch(
                value: _config.nightModeEnabled,
                onChanged: (value) =>
                    _update(_config.copyWith(nightModeEnabled: value)),
              ),
              onTap: () => _update(
                _config.copyWith(
                  nightModeEnabled: !_config.nightModeEnabled,
                ),
              ),
            ),
            NormalItem(
              title: '开始时间',
              subtitle: '当前：${_hourLabel(_config.startHour)}',
              leading: AppIcon(AppIcons.timer()),
              enabled: _config.nightModeEnabled,
              onTap: (dialogContext, refresh) async {
                final value = await showSelectDialog<int>(
                  dialogContext,
                  title: '开始时间',
                  value: _config.startHour,
                  values: _hourOptions(),
                );
                if (value == null) return;
                await _update(_config.copyWith(startHour: value));
                refresh();
              },
            ),
            NormalItem(
              title: '结束时间',
              subtitle: '当前：${_hourLabel(_config.endHour)}',
              leading: AppIcon(AppIcons.timer()),
              enabled: _config.nightModeEnabled,
              onTap: (dialogContext, refresh) async {
                final value = await showSelectDialog<int>(
                  dialogContext,
                  title: '结束时间',
                  value: _config.endHour,
                  values: _hourOptions(),
                );
                if (value == null) return;
                await _update(_config.copyWith(endHour: value));
                refresh();
              },
            ),
          ],
        ),
        const SizedBox(height: Style.lg),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Style.lg),
          child: Text(
            '护眼模式通过应用内半透明叠色实现，不会修改系统亮度；'
            '视频画面同样会被着色，截图也会包含滤镜。',
            style: tokens.text.bodySmall?.copyWith(
              color: tokens.colors.outline,
            ),
          ),
        ),
      ],
    );
  }

  static String _hourLabel(int hour) =>
      '${hour.toString().padLeft(2, '0')}:00';

  static List<(int, String)> _hourOptions() => [
        for (var hour = 0; hour < 24; hour++)
          (hour, '${hour.toString().padLeft(2, '0')}:00'),
      ];
}
