import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/core/storage/storage_key.dart';
import 'package:winwin/pages/setting/models/settings_model.dart';
import 'package:winwin/pages/setting/theme_notifier.dart';
import 'package:winwin/pages/setting/widgets/select_dialog.dart';
import 'package:winwin/theme/app_font_notifier.dart';
import 'package:winwin/theme/system_font_scanner.dart';
import 'package:winwin/theme/ui_style.dart';
import 'package:winwin/theme/ui_style_notifier.dart';

/// 外观设置项列表。
///
/// 移植自 PiliPlus 的 `styleSettings`，仅保留桌面端适用项。
List<SettingsModel> get styleSettings => [
      // ── Phase 7.1：界面风格（Material 3 / Miuix / iOS 热切换） ──
      NormalModel(
        title: '界面风格',
        leading: const Icon(Icons.palette_outlined),
        getSubtitle: () =>
            '当前风格：${UiStyleNotifier.instance.value.label}（切换即时生效）',
        onTap: (context, setState) async {
          final res = await showDialog<UiStyle>(
            context: context,
            builder: (context) => SelectDialog<UiStyle>(
              title: '界面风格',
              value: UiStyleNotifier.instance.value,
              values: UiStyle.values.map((e) => (e, e.label)).toList(),
              subtitleBuilder: (_, index) {
                final desc = switch (UiStyle.values[index]) {
                  UiStyle.ios => 'Cupertino 控件 + 连续曲率圆角 + 扩散阴影',
                  UiStyle.material3 => 'M3 原生控件 + 标准 tonal elevation',
                  UiStyle.miuix => '扁平控件 + 0 elevation + 1.15× 圆角',
                };
                return Text(
                  desc,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                );
              },
            ),
          );
          if (res != null) {
            await UiStyleNotifier.instance.setStyle(res);
            setState();
          }
        },
      ),

      // 应用字体（移植自 BiliPai AppFontFileStore）
      NormalModel(
        title: '应用字体',
        leading: const Icon(Icons.font_download_outlined),
        getSubtitle: () => '当前：${AppFontNotifier.instance.displayName}',
        onTap: (context, setState) async {
          await showDialog<void>(
            context: context,
            builder: (context) => _FontPickerDialog(setState: setState),
          );
        },
      ),

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

/// 字体选择对话框。
///
/// 参照 BiliPai `AppearanceSettingsScreen` 的「应用字体」分区：
/// - 系统字体单选列表（扫描 Windows 已安装的全部字体）
/// - 搜索框过滤字体
/// - 自定义字体导入入口（file_picker 选择 .ttf/.otf）
/// - 恢复默认按钮（清除已导入的自定义字体）
class _FontPickerDialog extends StatefulWidget {
  final void Function() setState;

  const _FontPickerDialog({required this.setState});

  @override
  State<_FontPickerDialog> createState() => _FontPickerDialogState();
}

class _FontPickerDialogState extends State<_FontPickerDialog> {
  late String _selected;
  bool _importing = false;
  bool _scanning = true;
  List<FontInfo> _allFonts = [];
  List<FontInfo> _filteredFonts = [];
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selected = AppFontNotifier.instance.value;
    _loadFonts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFonts() async {
    final fonts = await SystemFontScanner.scan();
    if (!mounted) return;
    setState(() {
      _allFonts = fonts;
      _filteredFonts = fonts;
      _scanning = false;
    });
  }

  void _onSearch(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      _filteredFonts = q.isEmpty
          ? _allFonts
          : _allFonts
              .where((f) =>
                  f.label.toLowerCase().contains(q) ||
                  f.family.toLowerCase().contains(q))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    // 将整个字体选择弹窗与全局字体变更隔离，锁定使用系统默认 UI 字体，
    // 防止全局字体切换时弹窗本身的基础样式被覆盖。
    final isolatedTheme = baseTheme.copyWith(
      textTheme: baseTheme.textTheme.apply(
        fontFamily: AppFontNotifier.windowsDefault,
      ),
      primaryTextTheme: baseTheme.primaryTextTheme.apply(
        fontFamily: AppFontNotifier.windowsDefault,
      ),
    );
    final notifier = AppFontNotifier.instance;
    final hasCustom = notifier.isCustomFont;

    return Theme(
      data: isolatedTheme,
      child: AlertDialog(
        title: const Text('应用字体'),
        contentPadding: EdgeInsets.zero,
        content: SizedBox(
          width: 420,
          height: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 搜索框
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearch,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    hintText: '搜索字体…',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              // 字体列表
              Expanded(
                child: _scanning
                    ? const Center(child: CircularProgressIndicator())
                    : RadioGroup<String>(
                        onChanged: (v) async {
                          if (v == null) return;
                          await notifier.setFontFamily(v);
                          setState(() => _selected = v);
                        },
                        groupValue: _selected,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _filteredFonts.length + (hasCustom ? 1 : 0),
                          itemBuilder: (context, index) {
                            // 自定义字体项放在列表末尾。
                            if (index == _filteredFonts.length && hasCustom) {
                              return RadioListTile<String>(
                                dense: true,
                                value: AppFontNotifier.customFontFamily,
                                title: const Text('自定义字体（已导入）'),
                                subtitle: Text(
                                  '点击「恢复默认」可移除',
                                  style: isolatedTheme.textTheme.labelSmall?.copyWith(
                                        color: isolatedTheme.colorScheme.outline,
                                      ),
                                ),
                              );
                            }
                            final font = _filteredFonts[index];
                            final isDefault =
                                font.family == AppFontNotifier.windowsDefault;
                            final hasSubtitle = font.label != font.family;
                            return RadioListTile<String>(
                              dense: true,
                              value: font.family,
                              title: Text(
                                isDefault
                                    ? '${font.label}（Windows 默认）'
                                    : font.label,
                                style: TextStyle(
                                  fontFamily: font.actualFamily,
                                  fontWeight: font.weight,
                                  fontStyle: font.isItalic
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                ),
                              ),
                              subtitle: hasSubtitle
                                  ? Text(
                                      font.family,
                                      style: isolatedTheme.textTheme.labelSmall?.copyWith(
                                            color: isolatedTheme.colorScheme.outline,
                                          ),
                                    )
                                  : null,
                            );
                          },
                        ),
                      ),
              ),
              const Divider(height: 1),
              // 导入 / 恢复默认
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: _importing ? null : _importFont,
                      icon: SizedBox(
                        width: 18,
                        height: 18,
                        child: _importing
                            ? const CircularProgressIndicator(strokeWidth: 2)
                            : const Icon(Icons.file_upload_outlined, size: 18),
                      ),
                      label: Text(_importing ? '导入中…' : '导入字体文件'),
                    ),
                    if (hasCustom) ...[
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () async {
                          await notifier.clearCustomFont();
                          setState(() => _selected = notifier.value);
                        },
                        icon: const Icon(Icons.restore, size: 18),
                        label: const Text('恢复默认'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              widget.setState();
              Navigator.pop(context);
            },
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }

  /// 通过 file_picker 选择并导入自定义字体文件。
  Future<void> _importFont() async {
    setState(() => _importing = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ttf', 'otf'],
        withData: false,
      );
      if (result == null || result.files.single.path == null) {
        setState(() => _importing = false);
        return;
      }
      final path = result.files.single.path!;
      final err = await AppFontNotifier.instance.importCustomFont(path);
      if (!mounted) return;
      if (err != null) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(err), duration: const Duration(seconds: 3)),
        );
      } else {
        setState(() => _selected = AppFontNotifier.customFontFamily);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('字体导入成功'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('导入失败：$e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }
}
