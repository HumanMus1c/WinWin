import 'package:file_picker/file_picker.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:material_ui/material_ui.dart';

import 'package:winwin/common/widgets/miuix_dialog_shell.dart';
import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/core/storage/storage_key.dart';
import 'package:winwin/pages/setting/models/settings_model.dart';
import 'package:winwin/pages/setting/theme_notifier.dart';
import 'package:winwin/pages/setting/widgets/select_dialog.dart';
import 'package:winwin/pages/setting/widgets/slider_dialog.dart';
import 'package:winwin/theme/app_font_notifier.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/inherited_ui_style.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/theme/system_font_scanner.dart';
import 'package:winwin/theme/ui_style.dart';
import 'package:winwin/theme/ui_style_notifier.dart';

/// 外观设置项列表。
///
/// 移植自 PiliPlus 的 `styleSettings`，仅保留桌面端适用项。
List<SettingsModel> get styleSettings => [
      // ── Phase 7.1：界面风格（Material 3 / Miuix 热切换） ──
      NormalModel(
        title: '界面风格',
        leading: const Icon(Icons.palette_outlined),
        getSubtitle: () =>
            '当前风格：${UiStyleNotifier.instance.value.label}（切换即时生效）',
        onTap: (context, setState) async {
          final res = await showSelectDialog<UiStyle>(
            context,
            title: '界面风格',
            value: UiStyleNotifier.instance.value,
            values: UiStyle.values.map((e) => (e, e.label)).toList(),
            subtitleBuilder: (_, index) {
              final desc = switch (UiStyle.values[index]) {
                UiStyle.material3 => 'M3 原生控件 + 标准 tonal elevation',
                UiStyle.miuix => '扁平控件 + 0 elevation + 1.15× 圆角',
              };
              return Text(desc);
            },
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
          final res = await showSelectDialog<ThemeModeType>(
            context,
            title: '主题模式',
            value: ThemeModeType.fromMode(ThemeNotifier.instance.value),
            values: ThemeModeType.values.map((e) => (e, e.label)).toList(),
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
            builder: (context) => AppSliderDialog(
              title: '字体大小',
              value: current,
              min: 0.8,
              max: 1.4,
              divisions: 12,
              suffix: 'x',
              decimals: 2,
            ),
          );
          if (res != null) {
            await GStorage.setting.put(SettingBoxKey.defaultTextScale, res);
            setState();
            if (context.mounted) {
              showToast(context, '重启生效', duration: const Duration(seconds: 2));
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
            builder: (context) => AppSliderDialog(
              title: '界面缩放',
              value: current,
              min: 0.8,
              max: 1.5,
              divisions: 14,
              suffix: 'x',
              decimals: 2,
            ),
          );
          if (res != null) {
            await GStorage.setting.put(SettingBoxKey.uiScale, res);
            setState();
            if (context.mounted) {
              showToast(context, '重启生效', duration: const Duration(seconds: 2));
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

    // Miuix 分支（阶段3 修复轮）：MiuixDialogShell + Miuix 单选行 + 原生
    // 搜索框；文本样式锁定默认（隔离全局字体变更），行内字体预览样式保留。
    if (InheritedUiStyle.of(context) == UiStyle.miuix) {
      return _buildMiuixDialog(context, notifier, hasCustom);
    }

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

  /// Miuix 版字体选择弹窗（阶段3 修复轮：替换旧版 MD3 AlertDialog 外观）。
  Widget _buildMiuixDialog(
    BuildContext context,
    AppFontNotifier notifier,
    bool hasCustom,
  ) {
    return MiuixTheme(
      data: MiuixTheme.of(context).copyWith(textStyles: defaultTextStyles()),
      child: MiuixDialogShell(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 640),
        child: SizedBox(
          width: 460,
          height: 520,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Style.lg,
                  Style.sm,
                  Style.sm,
                  0,
                ),
                child: Row(
                  children: [
                    Text(
                      '应用字体',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    IconButton(
                      icon: AppIcon(AppIcons.clear(context)),
                      tooltip: '关闭',
                      onPressed: () {
                        widget.setState();
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Style.lg),
                child: MiuixTextField(
                  controller: _searchController,
                  onChanged: _onSearch,
                  label: '搜索字体…',
                  useLabelAsPlaceholder: true,
                  leadingIcon: AppIcon(AppIcons.search(context), size: 20),
                ),
              ),
              const SizedBox(height: Style.sm),
              Expanded(
                child: _scanning
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        children: [
                          for (final font in _filteredFonts)
                            _miuixFontRow(
                              context,
                              family: font.family,
                              title:
                                  font.family == AppFontNotifier.windowsDefault
                                      ? '${font.label}（Windows 默认）'
                                      : font.label,
                              subtitle: font.label != font.family
                                  ? font.family
                                  : null,
                              titleFontFamily: font.actualFamily,
                              titleWeight: font.weight,
                              titleItalic: font.isItalic,
                            ),
                          if (hasCustom)
                            _miuixFontRow(
                              context,
                              family: AppFontNotifier.customFontFamily,
                              title: '自定义字体（已导入）',
                              subtitle: '点击「恢复默认」可移除',
                            ),
                        ],
                      ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Style.lg,
                  vertical: Style.sm,
                ),
                child: Row(
                  children: [
                    MiuixButton(
                      onPressed: _importing ? null : _importFont,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _importing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : AppIcon(Icons.file_upload_outlined, size: 18),
                          const SizedBox(width: 6),
                          Text(_importing ? '导入中…' : '导入字体文件'),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (hasCustom)
                      MiuixButton(
                        onPressed: () async {
                          await notifier.clearCustomFont();
                          setState(() => _selected = notifier.value);
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppIcon(Icons.restore, size: 18),
                            const SizedBox(width: 6),
                            const Text('恢复默认'),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Miuix 版字体行：单选按钮 + 字体预览标题（保留各字体自身字形）。
  Widget _miuixFontRow(
    BuildContext context, {
    required String family,
    required String title,
    String? subtitle,
    String? titleFontFamily,
    FontWeight? titleWeight,
    bool titleItalic = false,
  }) {
    Future<void> select() async {
      await AppFontNotifier.instance.setFontFamily(family);
      if (mounted) setState(() => _selected = family);
    }

    return MiuixBasicComponent(
      startAction: MiuixRadioButton(
        selected: _selected == family,
        onChanged: (_) => select(),
      ),
      content: [
        Text(
          title,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: titleFontFamily,
            fontWeight: titleWeight,
            fontStyle: titleItalic ? FontStyle.italic : FontStyle.normal,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ],
      insideMargin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      onClick: select,
    );
  }

  /// 通过 file_picker 选择并导入自定义字体文件。
  Future<void> _importFont() async {
    setState(() => _importing = true);
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['ttf', 'otf'],
      );
      if (file == null || file.path == null) {
        setState(() => _importing = false);
        return;
      }
      final path = file.path!;
      final err = await AppFontNotifier.instance.importCustomFont(path);
      if (!mounted) return;
      if (err != null) {
        showToast(context, err, duration: const Duration(seconds: 3));
      } else {
        setState(() => _selected = AppFontNotifier.customFontFamily);
        showToast(context, '字体导入成功', duration: const Duration(seconds: 2));
      }
    } catch (e) {
      if (mounted) {
        showToast(context, '导入失败：$e', duration: const Duration(seconds: 3));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }
}
