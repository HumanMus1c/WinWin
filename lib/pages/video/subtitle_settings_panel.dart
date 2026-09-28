import 'package:flutter/material.dart';

import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/core/storage/storage_key.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/pages/video/player_controller.dart';
import 'package:winwin/pages/video/subtitle_controller.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/inherited_ui_style.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/theme/ui_style.dart';

/// 字幕选择 + 样式设置面板（Phase 4.4）。
///
/// 上半部分：字幕轨道选择（关闭 / 各语言字幕，AI 字幕标注「AI」）；
/// 下半部分：字幕样式（字号 / 背景不透明度 / 描边 / 字重 / 边距）+ AI 偏好策略。
///
/// 样式改动即时写入 GStorage，字幕渲染层（PlayerPanel._buildSubtitleLayer）
/// 下次重建时读取生效。
void showSubtitleSettingsPanel(
  BuildContext context, {
  required WinWinPlayerController controller,
  required bool fullscreen,
}) {
  showDialog<void>(
    context: context,
    builder: (context) => _SubtitleSettingsDialog(
      controller: controller,
      fullscreen: fullscreen,
    ),
  );
}

class _SubtitleSettingsDialog extends StatefulWidget {
  const _SubtitleSettingsDialog({
    required this.controller,
    required this.fullscreen,
  });

  final WinWinPlayerController controller;
  final bool fullscreen;

  @override
  State<_SubtitleSettingsDialog> createState() =>
      _SubtitleSettingsDialogState();
}

class _SubtitleSettingsDialogState extends State<_SubtitleSettingsDialog> {
  late double _fontScale;
  late double _bgOpacity;
  late double _strokeWidth;
  late int _fontWeight;
  late int _padH;
  late int _padB;
  late SubtitlePreference _aiPref;

  @override
  void initState() {
    super.initState();
    _fontScale = widget.fullscreen
        ? Pref.subtitleFontScaleFS
        : Pref.subtitleFontScale;
    _bgOpacity = Pref.subtitleBgOpacity;
    _strokeWidth = Pref.subtitleStrokeWidth;
    _fontWeight = Pref.subtitleFontWeight;
    _padH = Pref.subtitlePaddingH;
    _padB = Pref.subtitlePaddingB;
    _aiPref = SubtitlePreference.current;
  }

  void _put(String key, Object value) {
    GStorage.setting.put(key, value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = InheritedUiStyle.of(context);
    final isMiuix = style == UiStyle.miuix;

    return Dialog(
      backgroundColor: isMiuix
          ? theme.colorScheme.surface.withValues(alpha: 0.96)
          : theme.colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isMiuix ? 16 : 24),
        side: isMiuix
            ? BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
              )
            : BorderSide.none,
      ),
      insetPadding: const EdgeInsets.symmetric(
        horizontal: Style.lg,
        vertical: Style.xl,
      ),
      child: ConstrainedBox(
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
                  Text('字幕设置', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: Icon(AppIcons.clear(context)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(height: 1),
              Expanded(child: _buildList(theme)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(ThemeData theme) {
    final sub = widget.controller.subtitle;
    return ListenableBuilder(
      listenable: sub,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: Style.sm),
          children: [
            // ── 字幕轨道选择 ──
            Text('字幕轨道', style: theme.textTheme.labelLarge),
            const SizedBox(height: Style.xs),
            _SubtitleOptionTile(
              label: '关闭字幕',
              selected: sub.current == null,
              onTap: () => sub.select(null),
            ),
            if (sub.available.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: Style.xs,
                  horizontal: Style.md,
                ),
                child: Text(
                  '当前视频暂无可用字幕',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            for (final item in sub.available)
              _SubtitleOptionTile(
                label: item.lanDoc.isEmpty ? item.lan : item.lanDoc,
                badge: item.isAi ? 'AI' : null,
                selected: sub.current?.id == item.id,
                onTap: () => sub.select(item),
              ),
            const Divider(height: Style.lg),

            // ── AI 偏好策略 ──
            Text('AI 字幕策略', style: theme.textTheme.labelLarge),
            const SizedBox(height: Style.xs),
            RadioGroup<SubtitlePreference>(
              groupValue: _aiPref,
              onChanged: (v) {
                if (v == null) return;
                setState(() => _aiPref = v);
                _put(SettingBoxKey.subtitlePreferenceV2, v.value);
              },
              child: Column(
                children: [
                  for (final pref in SubtitlePreference.values)
                    RadioListTile<SubtitlePreference>(
                      value: pref,
                      activeColor: biliPink,
                      dense: true,
                      title: Text(_aiPrefLabel(pref)),
                    ),
                ],
              ),
            ),
            const Divider(height: Style.lg),

            // ── 样式设置 ──
            Text('字幕样式', style: theme.textTheme.labelLarge),
            const SizedBox(height: Style.xs),
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
                    ? SettingBoxKey.subtitleFontScaleFS
                    : SettingBoxKey.subtitleFontScale,
                v,
              ),
              onReset: () {
                final d = widget.fullscreen ? 1.5 : 1.0;
                setState(() => _fontScale = d);
                _put(
                  widget.fullscreen
                      ? SettingBoxKey.subtitleFontScaleFS
                      : SettingBoxKey.subtitleFontScale,
                  d,
                );
              },
            ),
            _SliderRow(
              label: '背景不透明度',
              value: _bgOpacity,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              valueLabel: '${(_bgOpacity * 100).round()}%',
              onChanged: (v) => setState(() => _bgOpacity = v),
              onChangeEnd: (v) =>
                  _put(SettingBoxKey.subtitleBgOpacity, v),
              onReset: () {
                setState(() => _bgOpacity = 0.67);
                _put(SettingBoxKey.subtitleBgOpacity, 0.67);
              },
            ),
            _SliderRow(
              label: '描边宽度',
              value: _strokeWidth,
              min: 0.0,
              max: 6.0,
              divisions: 24,
              valueLabel: _strokeWidth.toStringAsFixed(1),
              onChanged: (v) => setState(() => _strokeWidth = v),
              onChangeEnd: (v) =>
                  _put(SettingBoxKey.subtitleStrokeWidth, v),
              onReset: () {
                setState(() => _strokeWidth = 2.0);
                _put(SettingBoxKey.subtitleStrokeWidth, 2.0);
              },
            ),
            _SliderRow(
              label: '左右边距',
              value: _padH.toDouble(),
              min: 0,
              max: 100,
              divisions: 20,
              valueLabel: '$_padH',
              onChanged: (v) =>
                  setState(() => _padH = v.round()),
              onChangeEnd: (v) => _put(
                SettingBoxKey.subtitlePaddingH,
                v.round(),
              ),
              onReset: () {
                setState(() => _padH = 24);
                _put(SettingBoxKey.subtitlePaddingH, 24);
              },
            ),
            _SliderRow(
              label: '底部边距',
              value: _padB.toDouble(),
              min: 0,
              max: 120,
              divisions: 24,
              valueLabel: '$_padB',
              onChanged: (v) =>
                  setState(() => _padB = v.round()),
              onChangeEnd: (v) => _put(
                SettingBoxKey.subtitlePaddingB,
                v.round(),
              ),
              onReset: () {
                setState(() => _padB = 24);
                _put(SettingBoxKey.subtitlePaddingB, 24);
              },
            ),
            // 字重选择
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Style.xs),
              child: Row(
                children: [
                  Text('字重', style: theme.textTheme.bodyMedium),
                  const Spacer(),
                  DropdownMenu<int>(
                    width: 116,
                    requestFocusOnTap: false,
                    initialSelection: _fontWeight,
                    textStyle: theme.textTheme.bodyMedium,
                    inputDecorationTheme: const InputDecorationTheme(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    dropdownMenuEntries: [
                      for (var i = 0; i < 9; i++)
                        DropdownMenuEntry(value: i, label: 'w${(i + 1) * 100}'),
                    ],
                    onSelected: (v) {
                      if (v == null) return;
                      setState(() => _fontWeight = v);
                      _put(SettingBoxKey.subtitleFontWeight, v);
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static String _aiPrefLabel(SubtitlePreference pref) {
    switch (pref) {
      case SubtitlePreference.off:
        return '关闭字幕';
      case SubtitlePreference.on:
        return '显示所有字幕（含 AI）';
      case SubtitlePreference.withoutAi:
        return '仅显示非 AI 字幕';
      case SubtitlePreference.auto:
        return '优先非 AI，无则用 AI';
    }
  }
}

/// 字幕轨道选项行。
class _SubtitleOptionTile extends StatelessWidget {
  const _SubtitleOptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(
        AppIcons.radio(context, selected: selected),
        color: selected ? biliPink : null,
        size: 20,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? biliPink : null,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          if (badge != null) ...[
            const SizedBox(width: Style.xs),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: biliPink.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(Style.radiusXs),
              ),
              child: Text(
                badge!,
                style: const TextStyle(
                  fontSize: 10,
                  color: biliPink,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
      onTap: onTap,
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
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
              const Spacer(),
              Text(
                valueLabel,
                style: const TextStyle(
                  color: biliPink,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (onReset != null) ...[
                const SizedBox(width: 2),
                IconButton(
                  tooltip: '恢复默认',
                  icon: Icon(AppIcons.refresh(context), size: 15),
                  color: Theme.of(context).colorScheme.outline,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  onPressed: onReset,
                ),
              ],
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            activeColor: biliPink,
            inactiveColor: Colors.white24,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ],
      ),
    );
  }
}
