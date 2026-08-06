import 'package:flutter/material.dart';

import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/core/storage/storage_key.dart';
import 'package:winwin/pages/setting/models/settings_model.dart';
import 'package:winwin/pages/setting/theme_notifier.dart';
import 'package:winwin/pages/setting/widgets/select_dialog.dart';

/// 外观设置项列表。
///
/// 移植自 PiliPlus 的 `styleSettings`，仅保留桌面端适用项。
List<SettingsModel> get styleSettings => [
      // 主题模式
      NormalModel(
        title: '主题模式',
        leading: const Icon(Icons.brightness_6_outlined),
        getSubtitle: () =>
            '当前模式：${ThemeModeType.fromMode(ThemeNotifier.instance.value).label}',
        onTap: (context, setState) async {
          final res = await showDialog<ThemeModeType>(
            context: context,
            builder: (context) => SelectDialog<ThemeModeType>(
              title: '主题模式',
              value: ThemeModeType.fromMode(ThemeNotifier.instance.value),
              values: ThemeModeType.values
                  .map((e) => (e, e.label))
                  .toList(),
            ),
          );
          if (res != null) {
            await ThemeNotifier.instance.setMode(res.toThemeMode());
            setState();
          }
        },
      ),

      // 纯黑主题（深色模式下背景纯黑）
      const SwitchModel(
        title: '纯黑主题',
        subtitle: '深色模式下使用纯黑背景（OLED 省电）',
        leading: Icon(Icons.contrast),
        setKey: SettingBoxKey.isPureBlackTheme,
        defaultVal: false,
        needReboot: true,
      ),

      // 字体大小缩放
      NormalModel(
        title: '字体大小',
        leading: const Icon(Icons.text_fields),
        getSubtitle: () => '当前缩放：${(GStorage.setting.get(SettingBoxKey.defaultTextScale, defaultValue: 1.0) as double).toStringAsFixed(2)}',
        onTap: (context, setState) async {
          final current = GStorage.setting.get(SettingBoxKey.defaultTextScale,
              defaultValue: 1.0) as double;
          final res = await showDialog<double>(
            context: context,
            builder: (context) => _SliderDialog(
              title: '字体大小',
              value: current,
              min: 0.8,
              max: 1.4,
              divisions: 12,
              suffix: 'x',
            ),
          );
          if (res != null) {
            await GStorage.setting.put(SettingBoxKey.defaultTextScale, res);
            setState();
            if (context.mounted) {
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                const SnackBar(
                  content: Text('重启生效'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          }
        },
      ),

      // 界面缩放
      NormalModel(
        title: '界面缩放',
        leading: const Icon(Icons.zoom_in_outlined),
        getSubtitle: () =>
            '当前缩放比例：${(GStorage.setting.get(SettingBoxKey.uiScale, defaultValue: 1.0) as double).toStringAsFixed(2)}',
        onTap: (context, setState) async {
          final current = GStorage.setting.get(SettingBoxKey.uiScale,
              defaultValue: 1.0) as double;
          final res = await showDialog<double>(
            context: context,
            builder: (context) => _SliderDialog(
              title: '界面缩放',
              value: current,
              min: 0.8,
              max: 1.5,
              divisions: 14,
              suffix: 'x',
            ),
          );
          if (res != null) {
            await GStorage.setting.put(SettingBoxKey.uiScale, res);
            setState();
            if (context.mounted) {
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                const SnackBar(
                  content: Text('重启生效'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          }
        },
      ),

      // 显示窗口标题栏（桌面端）
      const SwitchModel(
        title: '显示窗口标题栏',
        leading: Icon(Icons.window),
        setKey: SettingBoxKey.showWindowTitleBar,
        defaultVal: true,
        needReboot: true,
      ),

      // 显示托盘图标（桌面端）
      const SwitchModel(
        title: '显示托盘图标',
        leading: Icon(Icons.donut_large_rounded),
        setKey: SettingBoxKey.showTrayIcon,
        defaultVal: true,
        needReboot: true,
      ),

      // 退出时最小化到托盘
      const SwitchModel(
        title: '退出时最小化到托盘',
        subtitle: '关闭窗口时最小化到系统托盘而非退出',
        leading: Icon(Icons.minimize),
        setKey: SettingBoxKey.minimizeOnExit,
        defaultVal: false,
      ),
    ];

/// 滑块对话框（内联实现，避免单独文件）。
class _SliderDialog extends StatefulWidget {
  final String title;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String suffix;

  const _SliderDialog({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    this.suffix = '',
  });

  @override
  State<_SliderDialog> createState() => _SliderDialogState();
}

class _SliderDialogState extends State<_SliderDialog> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${_value.toStringAsFixed(2)}${widget.suffix}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Slider(
            value: _value,
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            onChanged: (v) => setState(() => _value = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _value),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
