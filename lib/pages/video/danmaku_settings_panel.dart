import 'package:flutter_miuix/miuix.dart';
import 'package:material_ui/material_ui.dart';

import 'package:winwin/common/widgets/miuix_dialog_shell.dart';
import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/core/storage/storage_key.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/pages/danmaku/danmaku_block.dart';
import 'package:winwin/pages/danmaku/danmaku_options.dart';
import 'package:winwin/pages/video/player_controller.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/core/shell/app_dialogs.dart';
import 'package:winwin/ui/components/app_tooltip.dart';

/// 弹幕设置面板（移植自 PiliPlus `lib/pages/video/widgets/header_mixin.dart`
/// 中的弹幕设置区）。
///
/// WinWin 精简版：独立面板（showDialog + 可滚动 ListView），涵盖字号 /
/// 不透明度 / 显示区域 / 滚动&静态时长 / 描边 / 字重 / 行高 / 屏蔽类型 /
/// 智能云屏蔽 / 合并 / 会员彩弹 / 海量模式 / 固定速度 / 静态转滚动。
///
/// 每次改动即时写入 GStorage 并刷新 [WinWinPlayerController.danmakuEngine]
/// 的 option；不透明度改动额外写入 [WinWinPlayerController.danmakuOpacity]
/// 供弹幕视图层监听刷新。
void showDanmakuSettingsPanel(
  BuildContext context, {
  required WinWinPlayerController controller,
  required bool fullscreen,
}) {
  showAppDialog<void>(
    context: context,
    builder: (context) => _DanmakuSettingsDialog(
      controller: controller,
      fullscreen: fullscreen,
    ),
  );
}

class _DanmakuSettingsDialog extends StatefulWidget {
  const _DanmakuSettingsDialog({
    required this.controller,
    required this.fullscreen,
  });

  final WinWinPlayerController controller;
  final bool fullscreen;

  @override
  State<_DanmakuSettingsDialog> createState() => _DanmakuSettingsDialogState();
}

class _DanmakuSettingsDialogState extends State<_DanmakuSettingsDialog> {
  late bool _enabled;
  late double _opacity;
  late double _fontScale;
  late double _area;
  late double _duration;
  late double _staticDuration;
  late double _strokeWidth;
  late int _fontWeight;
  late double _lineHeight;
  late int _weight;
  late Set<int> _blockType;
  late bool _merge;
  late bool _showVip;
  late bool _massive;
  late bool _fixedV;
  late bool _static2Scroll;

  @override
  void initState() {
    super.initState();
    _enabled = Pref.enableShowDanmaku;
    _opacity = Pref.danmakuOpacity;
    _fontScale = widget.fullscreen
        ? Pref.danmakuFontScaleFS
        : Pref.danmakuFontScale;
    _area = Pref.danmakuShowArea;
    _duration = Pref.danmakuDuration;
    _staticDuration = Pref.danmakuStaticDuration;
    _strokeWidth = Pref.danmakuStrokeWidth;
    _fontWeight = Pref.danmakuFontWeight;
    _lineHeight = Pref.danmakuLineHeight;
    _weight = Pref.danmakuWeight;
    _blockType = Pref.danmakuBlockType;
    _merge = Pref.mergeDanmaku;
    _showVip = Pref.showVipDanmaku;
    _massive = Pref.danmakuMassiveMode;
    _fixedV = Pref.danmakuFixedV;
    _static2Scroll = Pref.danmakuStatic2Scroll;
  }

  /// 写入一个设置项并刷新弹幕引擎 option（slider/switch 通用）。
  void _put(String key, Object value) {
    GStorage.setting.put(key, value);
    _refreshEngine();
  }

  void _refreshEngine() {
    widget.controller.danmakuEngine?.updateOption(
      DanmakuOptions.get(
        fullscreen: widget.fullscreen,
        speed: widget.controller.playbackSpeed.value,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);

    return MiuixDialogShell(
      constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Style.lg,
          vertical: Style.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('弹幕设置', style: tokens.text.titleMedium),
                const Spacer(),
                MiuixIconButton(

                  onPressed: () => Navigator.of(context).pop(),

                  child: AppIcon(AppIcons.clear()),
                ),
              ],
            ),
            const MiuixHorizontalDivider(),
            Expanded(child: _buildList(tokens)),
          ],
        ),
      ),
    );
  }

  Widget _buildList(AppTokens tokens) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: Style.sm),
      children: [
        _SwitchRow(
          label: '开启弹幕',
          value: _enabled,
          onChanged: (v) {
            setState(() => _enabled = v);
            GStorage.setting.put(SettingBoxKey.enableShowDanmaku, v);
            // 触发弹幕视图层刷新（opacity notifier 重新赋值驱动重建）。
            widget.controller.danmakuOpacity.value = _opacity;
          },
        ),
        _SliderRow(
          label: '不透明度',
          value: _opacity,
          min: 0.1,
          max: 1.0,
          divisions: 18,
          valueLabel: _opacity.toStringAsFixed(2),
          onChanged: (v) => setState(() => _opacity = v),
          onChangeEnd: (v) {
            widget.controller.danmakuOpacity.value = v;
            GStorage.setting.put(SettingBoxKey.danmakuOpacity, v);
          },
          onReset: () {
            setState(() => _opacity = 1.0);
            widget.controller.danmakuOpacity.value = 1.0;
            GStorage.setting.put(SettingBoxKey.danmakuOpacity, 1.0);
          },
        ),
        _SliderRow(
          label: '字号缩放',
          value: _fontScale,
          min: 0.5,
          max: 3.0,
          divisions: 25,
          valueLabel: '${_fontScale.toStringAsFixed(2)}x',
          onChanged: (v) => setState(() => _fontScale = v),
          onChangeEnd: (v) => _put(
            widget.fullscreen
                ? SettingBoxKey.danmakuFontScaleFS
                : SettingBoxKey.danmakuFontScale,
            v,
          ),
          onReset: () {
            final d = widget.fullscreen ? 1.7 : 1.4;
            setState(() => _fontScale = d);
            _put(
              widget.fullscreen
                  ? SettingBoxKey.danmakuFontScaleFS
                  : SettingBoxKey.danmakuFontScale,
              d,
            );
          },
        ),
        _SliderRow(
          label: '显示区域',
          value: _area,
          min: 0.1,
          max: 1.0,
          divisions: 18,
          valueLabel: '${(_area * 100).round()}%',
          onChanged: (v) => setState(() => _area = v),
          onChangeEnd: (v) => _put(SettingBoxKey.danmakuShowArea, v),
          onReset: () {
            setState(() => _area = 1.0);
            _put(SettingBoxKey.danmakuShowArea, 1.0);
          },
        ),
        _SliderRow(
          label: '滚动时长',
          value: _duration,
          min: 1.0,
          max: 20.0,
          divisions: 19,
          valueLabel: '${_duration.toStringAsFixed(1)}s',
          onChanged: (v) => setState(() => _duration = v),
          onChangeEnd: (v) => _put(SettingBoxKey.danmakuDuration, v),
          onReset: () {
            setState(() => _duration = 7.0);
            _put(SettingBoxKey.danmakuDuration, 7.0);
          },
        ),
        _SliderRow(
          label: '静态时长',
          value: _staticDuration,
          min: 1.0,
          max: 20.0,
          divisions: 19,
          valueLabel: '${_staticDuration.toStringAsFixed(1)}s',
          onChanged: (v) => setState(() => _staticDuration = v),
          onChangeEnd: (v) => _put(SettingBoxKey.danmakuStaticDuration, v),
          onReset: () {
            setState(() => _staticDuration = 4.0);
            _put(SettingBoxKey.danmakuStaticDuration, 4.0);
          },
        ),
        _SliderRow(
          label: '描边宽度',
          value: _strokeWidth,
          min: 0.0,
          max: 5.0,
          divisions: 25,
          valueLabel: _strokeWidth.toStringAsFixed(1),
          onChanged: (v) => setState(() => _strokeWidth = v),
          onChangeEnd: (v) => _put(SettingBoxKey.danmakuStrokeWidth, v),
          onReset: () {
            setState(() => _strokeWidth = 2.5);
            _put(SettingBoxKey.danmakuStrokeWidth, 2.5);
          },
        ),
        _SliderRow(
          label: '字体粗细',
          value: _fontWeight.toDouble(),
          min: 1,
          max: 9,
          divisions: 8,
          valueLabel: 'w${_fontWeight * 100}',
          onChanged: (v) => setState(() => _fontWeight = v.round()),
          onChangeEnd: (v) => _put(SettingBoxKey.danmakuFontWeight, v.round()),
          onReset: () {
            setState(() => _fontWeight = 6);
            _put(SettingBoxKey.danmakuFontWeight, 6);
          },
        ),
        _SliderRow(
          label: '行高',
          value: _lineHeight,
          min: 1.0,
          max: 2.5,
          divisions: 15,
          valueLabel: _lineHeight.toStringAsFixed(2),
          onChanged: (v) => setState(() => _lineHeight = v),
          onChangeEnd: (v) => _put(SettingBoxKey.danmakuLineHeight, v),
          onReset: () {
            setState(() => _lineHeight = 1.6);
            _put(SettingBoxKey.danmakuLineHeight, 1.6);
          },
        ),
        _SliderRow(
          label: '智能云屏蔽',
          value: _weight.toDouble(),
          min: 0,
          max: 11,
          divisions: 11,
          valueLabel: '$_weight',
          onChanged: (v) => setState(() => _weight = v.round()),
          onChangeEnd: (v) => _put(SettingBoxKey.danmakuWeight, v.round()),
          onReset: () {
            setState(() => _weight = 0);
            _put(SettingBoxKey.danmakuWeight, 0);
          },
        ),
        const SizedBox(height: Style.sm),
        _buildBlockTypeChips(tokens),
        const SizedBox(height: Style.xl, child: Center(child: MiuixHorizontalDivider())),
        _SwitchRow(
          label: '合并相同弹幕',
          value: _merge,
          onChanged: (v) {
            setState(() => _merge = v);
            _put(SettingBoxKey.mergeDanmaku, v);
          },
        ),
        _SwitchRow(
          label: '显示会员彩弹',
          value: _showVip,
          onChanged: (v) {
            setState(() => _showVip = v);
            _put(SettingBoxKey.showVipDanmaku, v);
          },
        ),
        _SwitchRow(
          label: '海量弹幕模式',
          value: _massive,
          onChanged: (v) {
            setState(() => _massive = v);
            _put(SettingBoxKey.danmakuMassiveMode, v);
          },
        ),
        _SwitchRow(
          label: '滚动固定速度',
          value: _fixedV,
          onChanged: (v) {
            setState(() => _fixedV = v);
            _put(SettingBoxKey.danmakuFixedV, v);
          },
        ),
        _SwitchRow(
          label: '静态溢出转滚动',
          value: _static2Scroll,
          onChanged: (v) {
            setState(() => _static2Scroll = v);
            _put(SettingBoxKey.danmakuStatic2Scroll, v);
          },
        ),
      ],
    );
  }

  /// 屏蔽类型多选（滚动/顶部/底部/高级/彩色）。
  Widget _buildBlockTypeChips(AppTokens tokens) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Style.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('屏蔽类型', style: tokens.text.bodyMedium),
          const SizedBox(height: Style.sm),
          Wrap(
            spacing: Style.sm,
            runSpacing: Style.sm,
            children: [
              for (final b in blockTypesList)
                FilterChip(
                  label: Text(b.label),
                  selected: _blockType.contains(b.value),
                  selectedColor: biliPink.withValues(alpha: 0.25),
                  checkmarkColor: biliPink,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _blockType.add(b.value);
                      } else {
                        _blockType.remove(b.value);
                      }
                    });
                    _put(SettingBoxKey.danmakuBlockType, _blockType.toList());
                  },
                ),
            ],
          ),
          const SizedBox(height: Style.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: MiuixButton(onPressed: () => showDanmakuBlockPage(
                context,
                danmakuController: widget.controller.danmaku,
              ), child: Row(mainAxisSize: MainAxisSize.min, children: [AppIcon(AppIcons.block(), size: 18), const SizedBox(width: 6), const Text('屏蔽规则管理')])),
          ),
        ],
      ),
    );
  }
}

/// 通用滑块行：label + value + 恢复默认 + Slider。
class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.onChanged,
    required this.onChangeEnd,
    this.onReset,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueLabel;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  /// 恢复默认值；非空时行尾显示重置按钮。
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Style.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: AppThemeHost.of(context).text.bodyMedium),
              const Spacer(),
              Text(
                valueLabel,
                style: TextStyle(
                  color: biliPink,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (onReset != null) ...[
                const SizedBox(width: 2),
                MiuixIconButton(
                  minWidth: 28,
                  minHeight: 28,
                  onPressed: onReset,
                  child: AppTooltip(
                    message: '恢复默认',
                    child: AppIcon(
                      AppIcons.refresh(),
                      size: 15,
                      color: AppThemeHost.of(context).colors.outline,
                    ),
                  ),
                ),
              ],
            ],
          ),
          // 阶段5d-L1：M3 分支已移除；MiuixSlider 内部 CustomPaint 不撑宽，
          // 宽松约束（如本行 Column）下必须显式撑满（阶段3d 回归修复）。
          SizedBox(
            width: double.infinity,
            child: MiuixSlider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              steps: divisions > 1 ? divisions - 1 : 0,
              onValueChanged: onChanged,
              onValueChangeFinished: () =>
                  onChangeEnd(value.clamp(min, max)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 通用开关行。
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Style.xs),
      child: Row(
        children: [
          Text(label, style: AppThemeHost.of(context).text.bodyMedium),
          const Spacer(),
          // 阶段5d-L1：M3 分支已移除。
          MiuixSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
