// 芯片（Chip）家族替身（零 material，替代 Material `ChoiceChip` / `FilterChip` /
// `ActionChip` / `InputChip`）。B7-c6-2。
//
// 复刻依据：`material_ui` 1.5.0
//   - `lib/src/chip.dart`：`RawChip`（几何 / 配色 / 勾选绘制 / 删除图标 / 点击靶）；
//   - `lib/src/generated/chip_defaults_m3.g.dart` + `choice_chip.dart` /
//     `filter_chip.dart` / `action_chip.dart` / `input_chip.dart` 内联的
//     `_XxxDefaultsM3`（各形态取值）。
//
// 最终观感来源（项目**未覆写** `chipTheme` ⇒ 全部取 M3 默认）：
//   · 形状：`RoundedRectangleBorder(radius 8)`（非项目 `AppShapes` 口径）。
//   · 高度：`content = max(32 - padding.vertical + labelPadding.vertical,
//     labelHeight + labelPadding.vertical)`；
//     `总高 = content + padding.vertical + densityAdjustment.dy`，其中
//     `densityAdjustment.dy = visualDensity.baseSizeAdjustment.dy / 2`。
//     `ThemeData.visualDensity` 未覆写 ⇒ 桌面端取 `VisualDensity.compact`
//     （`baseSizeAdjustment = (-8,-8)`）⇒ 竖向 -4。本替身用**等价实现**：
//     上下内边距各 -2（`adj/2`），逐像素一致（标签居中位与总高均相同）。
//   · 内边距：`padding` 默认 `EdgeInsets.all(8)`；`labelPadding` 默认
//     `symmetric(horizontal: 8)`，随有效字号放大线性收敛到 4（≥2× 时恒定 4）。
//   · 文案：`textTheme.labelLarge`（`Typography.englishLike2021`：size 14 /
//     w500 / letterSpacing 0.1 / height 1.43）+ 状态色；单行、`TextOverflow.fade`。
//   · 配色（M3 `flat` 变体）：未选 = 透明底 + 1px `outlineVariant` 描边；
//     选中 = `secondaryContainer` 底 + 透明描边；label 选中 `onSecondaryContainer`、
//     未选 `onSurfaceVariant`（ActionChip 恒 `onSurface`、无选中态）。
//   · 勾选：选中时前置于标签。槽位**高 = content**、**宽 = content × 抽屉动画值**；
//     绘制尺寸 = `content × 0.75`、偏移 `content × 0.125`、线宽 `2.0 × content / 24`；
//     两段式描线（`t < 0.5` 画 start→mid，之后画 mid→end）；进场 150ms /
//     退场 50ms / `fastOutSlowIn`；退场时保持 `t = 1` 并整体淡出。
//   · 点击靶：`MaterialTapTargetSize.padded` ⇒ 最小 48×48（密度调整后 40×40）。
//
// 与 Material 的**有意差异**（全站 Miuix 化的既定目标态）：按压反馈由 `InkWell`
// 水波统一为 `MiuixPressable`（2% 内缩），与 `lib/` 内既有 73 处迁移按压件同规格。

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart'
    show MiuixPressable, MiuixPressFeedbackType;

import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/theme/miuix_theme_bridge.dart';

// ── M3 常量（`material_ui/lib/src/chip.dart`） ──
const double _kChipHeight = 32.0;
const double _kChipRadius = 8.0;
const double _kCheckmarkStrokeWidth = 2.0;
const Duration _kSelectDuration = Duration(milliseconds: 195);
const Duration _kDrawerDuration = Duration(milliseconds: 150);
const Duration _kDrawerReverseDuration = Duration(milliseconds: 50);

/// `Typography.englishLike2021` 的 `labelLarge`（项目未覆写 `textTheme`）。
///
/// 项目 `AppTextStyles` 只携带墨色（B7-a 起为内联常量），字号/字重/行高
/// 仍由 Material `textTheme` 提供 —— 本替身按"最终态"内联该基样式，
/// 再叠加状态色，与移除 material 前的渲染逐字段一致。
const TextStyle _kLabelLargeM3 = TextStyle(
  fontSize: 14.0,
  fontWeight: FontWeight.w500,
  letterSpacing: 0.1,
  height: 1.43,
  decoration: TextDecoration.none,
);

/// 密度（对齐 Material `VisualDensity`）。
///
/// 本应用为 Windows 桌面端且未覆写 `ThemeData.visualDensity` ⇒ 主题默认取
/// `VisualDensity.defaultDensityForPlatform(windows)` = `compact`。
/// `compact` 的 `baseSizeAdjustment = (-8, -8)`：纵向总高 -4，点击靶 48 → 40。
enum AppChipDensity {
  /// `VisualDensity.standard`（移动端默认）。
  standard,

  /// `VisualDensity.compact`（桌面端默认，本应用取值）。
  compact;

  /// 内容框纵向调整（`baseSizeAdjustment.dy / 2`）。
  double get contentAdjustment => this == compact ? -4.0 : 0.0;

  /// 点击靶纵向 / 横向调整（`baseSizeAdjustment`）。
  double get tapAdjustment => this == compact ? -8.0 : 0.0;
}

/// `ChoiceChip` 替身：一组互斥选项中的一项。
class AppChoiceChip extends StatelessWidget {
  const AppChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    this.onSelected,
    this.labelStyle,
    this.padding,
    this.selectedColor,
    this.checkmarkColor,
    this.enabled = true,
    this.density = AppChipDensity.compact,
  });

  final Widget label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final TextStyle? labelStyle;
  final EdgeInsetsGeometry? padding;
  final Color? selectedColor;
  final Color? checkmarkColor;
  final bool enabled;
  final AppChipDensity density;

  @override
  Widget build(BuildContext context) {
    return _AppChipCore(
      variant: _AppChipVariant.choice,
      label: label,
      selected: selected,
      onSelected: onSelected,
      labelStyle: labelStyle,
      padding: padding,
      selectedColor: selectedColor,
      checkmarkColor: checkmarkColor,
      enabled: enabled,
      density: density,
    );
  }
}

/// `FilterChip` 替身：可多选的过滤项。
class AppFilterChip extends StatelessWidget {
  const AppFilterChip({
    super.key,
    required this.label,
    required this.selected,
    this.onSelected,
    this.labelStyle,
    this.padding,
    this.selectedColor,
    this.checkmarkColor,
    this.enabled = true,
    this.density = AppChipDensity.compact,
  });

  final Widget label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final TextStyle? labelStyle;
  final EdgeInsetsGeometry? padding;
  final Color? selectedColor;
  final Color? checkmarkColor;
  final bool enabled;
  final AppChipDensity density;

  @override
  Widget build(BuildContext context) {
    return _AppChipCore(
      variant: _AppChipVariant.filter,
      label: label,
      selected: selected,
      onSelected: onSelected,
      labelStyle: labelStyle,
      padding: padding,
      selectedColor: selectedColor,
      checkmarkColor: checkmarkColor,
      enabled: enabled,
      density: density,
    );
  }
}

/// `ActionChip` 替身：触发一个动作（无选中态）。
class AppActionChip extends StatelessWidget {
  const AppActionChip({
    super.key,
    required this.label,
    this.onPressed,
    this.labelStyle,
    this.padding,
    this.enabled = true,
    this.density = AppChipDensity.compact,
  });

  final Widget label;
  final VoidCallback? onPressed;
  final TextStyle? labelStyle;
  final EdgeInsetsGeometry? padding;
  final bool enabled;
  final AppChipDensity density;

  @override
  Widget build(BuildContext context) {
    return _AppChipCore(
      variant: _AppChipVariant.action,
      label: label,
      onPressed: onPressed,
      labelStyle: labelStyle,
      padding: padding,
      enabled: enabled,
      density: density,
    );
  }
}

/// `InputChip` 替身：承载输入块（可带删除图标）。
class AppInputChip extends StatelessWidget {
  const AppInputChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onSelected,
    this.deleteIcon,
    this.onDeleted,
    this.labelStyle,
    this.padding,
    this.selectedColor,
    this.checkmarkColor,
    this.enabled = true,
    this.density = AppChipDensity.compact,
  });

  final Widget label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final Widget? deleteIcon;
  final VoidCallback? onDeleted;
  final TextStyle? labelStyle;
  final EdgeInsetsGeometry? padding;
  final Color? selectedColor;
  final Color? checkmarkColor;
  final bool enabled;
  final AppChipDensity density;

  @override
  Widget build(BuildContext context) {
    return _AppChipCore(
      variant: _AppChipVariant.input,
      label: label,
      selected: selected,
      onSelected: onSelected,
      deleteIcon: deleteIcon,
      onDeleted: onDeleted,
      labelStyle: labelStyle,
      padding: padding,
      selectedColor: selectedColor,
      checkmarkColor: checkmarkColor,
      enabled: enabled,
      density: density,
    );
  }
}

enum _AppChipVariant { choice, filter, action, input }

class _AppChipCore extends StatefulWidget {
  const _AppChipCore({
    required this.variant,
    required this.label,
    this.selected = false,
    this.onSelected,
    this.onPressed,
    this.deleteIcon,
    this.onDeleted,
    this.labelStyle,
    this.padding,
    this.selectedColor,
    this.checkmarkColor,
    this.enabled = true,
    required this.density,
  });

  final _AppChipVariant variant;
  final Widget label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final VoidCallback? onPressed;
  final Widget? deleteIcon;
  final VoidCallback? onDeleted;
  final TextStyle? labelStyle;
  final EdgeInsetsGeometry? padding;
  final Color? selectedColor;
  final Color? checkmarkColor;
  final bool enabled;
  final AppChipDensity density;

  @override
  State<_AppChipCore> createState() => _AppChipCoreState();
}

class _AppChipCoreState extends State<_AppChipCore>
    with TickerProviderStateMixin {
  /// 背景色淡入淡出（`_kSelectDuration`）。
  late final AnimationController _select = AnimationController(
    vsync: this,
    duration: _kSelectDuration,
  );

  /// 勾选槽位抽屉（进场 150ms / 退场 50ms）。
  late final AnimationController _drawer = AnimationController(
    vsync: this,
    duration: _kDrawerDuration,
    reverseDuration: _kDrawerReverseDuration,
  );

  late final CurvedAnimation _selectionFade =
      CurvedAnimation(parent: _select, curve: Curves.fastOutSlowIn);
  late final CurvedAnimation _drawerFade =
      CurvedAnimation(parent: _drawer, curve: Curves.fastOutSlowIn);

  @override
  void initState() {
    super.initState();
    if (widget.selected) {
      _select.value = 1.0;
      _drawer.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(_AppChipCore oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      if (widget.selected) {
        _select.forward();
        _drawer.forward();
      } else {
        _select.reverse();
        _drawer.reverse();
      }
    }
  }

  @override
  void dispose() {
    _selectionFade.dispose();
    _drawerFade.dispose();
    _select.dispose();
    _drawer.dispose();
    super.dispose();
  }

  /// 是否可点击（且有回调）。
  bool get _cancellable => widget.onPressed != null || widget.onSelected != null;

  void _handleTap() {
    if (!widget.enabled) {
      return;
    }
    switch (widget.variant) {
      case _AppChipVariant.choice:
      case _AppChipVariant.filter:
        widget.onSelected?.call(!widget.selected);
      case _AppChipVariant.action:
        widget.onPressed?.call();
      case _AppChipVariant.input:
        widget.onSelected?.call(!widget.selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppThemeHost.of(context);
    final AppPalette cs = tokens.colors;
    final _AppChipVariant variant = widget.variant;
    final bool isAction = variant == _AppChipVariant.action;
    final bool enabled = widget.enabled;

    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_select, _drawer]),
      builder: (BuildContext context, Widget? child) {
        final double fade = _selectionFade.value;
        final bool isSelected = widget.selected;

        // ── 背景色（M3 flat：未选透明，选中 secondaryContainer；ActionChip 恒透明） ──
        final Color selectedBg = widget.selectedColor ?? cs.secondaryContainer;
        final Color background =
            isAction ? const Color(0x00000000) : Color.lerp(
              const Color(0x00000000),
              selectedBg,
              fade,
            )!;

        // ── 描边（flat：未选 outlineVariant，选中透明） ──
        final bool outlineShown = isAction
            ? true
            : (variant == _AppChipVariant.input ? !isSelected : !isSelected);
        final BorderSide side = BorderSide(
          color: outlineShown ? cs.outlineVariant : const Color(0x00000000),
        );

        // ── 文案样式（`textTheme.labelLarge` + 状态色） ──
        final Color labelColor;
        if (!enabled) {
          labelColor = cs.onSurface;
        } else if (isAction) {
          labelColor = cs.onSurface;
        } else if (variant == _AppChipVariant.input) {
          labelColor = isSelected ? cs.onSecondaryContainer : cs.onSurfaceVariant;
        } else {
          labelColor = isSelected ? cs.onSecondaryContainer : cs.onSurfaceVariant;
        }
        final TextStyle effectiveLabelStyle = _kLabelLargeM3
            .copyWith(color: labelColor)
            .merge(widget.labelStyle);

        final double fontSize = effectiveLabelStyle.fontSize ?? 14.0;
        final double lineHeightFactor = effectiveLabelStyle.height ?? 1.43;
        final TextScaler scaler = MediaQuery.textScalerOf(context);
        final double scaledFontSize = scaler.scale(fontSize);
        // 单行标签高度（显式 height ⇒ `字号 × 行高系数`，与 Text 实际排版一致）。
        final double labelHeight = scaledFontSize * lineHeightFactor;

        // `labelPadding`：水平 8 → 4（≥2× 文本缩放时恒定 4），纵向 0。
        final double textScaleRatio = scaledFontSize / 14.0;
        final EdgeInsets defaultLabelPadding = EdgeInsets.symmetric(
          horizontal:
              lerpDouble(8.0, 4.0, (textScaleRatio - 1.0).clamp(0.0, 1.0))!,
        );

        // 内容框高（不含 padding；勾选槽位与最小高度口径）。
        final EdgeInsets padding =
            (widget.padding ?? const EdgeInsets.all(8.0)).resolve(
              Directionality.maybeOf(context),
            );
        final double contentHeight = math.max(
          _kChipHeight - padding.vertical,
          labelHeight,
        );

        // 密度调整：上下内边距各 -2（compact）——等价于
        // `总高 = content + padding.vertical + densityAdjustment.dy`。
        final double halfAdjust = widget.density.contentAdjustment / 2.0;
        final EdgeInsets effectivePadding = EdgeInsets.only(
          left: padding.left,
          right: padding.right,
          top: padding.top + halfAdjust,
          bottom: padding.bottom + halfAdjust,
        );

        // ── 勾选槽位（选中且非 ActionChip；退场时保持满勾并淡出） ──
        final double drawerValue = _drawerFade.value;
        final bool reversing = _drawer.status == AnimationStatus.reverse ||
            _drawer.status == AnimationStatus.dismissed;
        final Color checkColor;
        if (widget.checkmarkColor != null) {
          checkColor = widget.checkmarkColor!;
        } else if (variant == _AppChipVariant.input) {
          checkColor = isSelected ? cs.primary : cs.onSurfaceVariant;
        } else {
          checkColor = isSelected ? cs.onSecondaryContainer : cs.primary;
        }

        final List<Widget> children = <Widget>[];
        if (!isAction && isSelected && drawerValue > 0.0) {
          children.add(
            SizedBox(
              width: contentHeight * drawerValue,
              height: contentHeight,
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: contentHeight,
                maxWidth: contentHeight,
                minHeight: contentHeight,
                maxHeight: contentHeight,
                child: CustomPaint(
                  size: Size.square(contentHeight),
                  painter: _AppCheckmarkPainter(
                    boxSize: contentHeight,
                    t: reversing ? 1.0 : drawerValue,
                    alpha: reversing ? drawerValue : 1.0,
                    color: checkColor,
                  ),
                ),
              ),
            ),
          );
        }

        children.add(
          Padding(
            padding: widget.labelStyle == null
                ? defaultLabelPadding
                : (const EdgeInsets.symmetric(horizontal: 8.0)),
            child: DefaultTextStyle(
              style: effectiveLabelStyle.copyWith(
                fontFamily: appFontFamilyOf(context),
              ),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
              textAlign: TextAlign.start,
              child: widget.label,
            ),
          ),
        );

        if (widget.deleteIcon != null) {
          children.add(
            SizedBox(
              width: contentHeight,
              height: contentHeight,
              child: MiuixPressable(
                onPressed: enabled ? widget.onDeleted : null,
                feedbackType: MiuixPressFeedbackType.sink,
                sinkAmount: 0.98,
                borderRadius: BorderRadius.circular(contentHeight / 2.0),
                child: Center(
                  child: IconTheme(
                    data: IconThemeData(
                      size: 18.0,
                      color: isSelected
                          ? cs.onSecondaryContainer
                          : cs.onSurfaceVariant,
                    ),
                    child: widget.deleteIcon!,
                  ),
                ),
              ),
            ),
          );
        }

        final Widget chip = MiuixPressable(
          onPressed: enabled && _cancellable ? _handleTap : null,
          feedbackType: MiuixPressFeedbackType.sink,
          sinkAmount: 0.98,
          borderRadius: BorderRadius.circular(_kChipRadius),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: background,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(_kChipRadius),
                side: side,
              ),
            ),
            child: Padding(
              padding: effectivePadding,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: contentHeight),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: children,
                ),
              ),
            ),
          ),
        );

        final double tapAdjust = widget.density.tapAdjustment;
        return Semantics(
          button: _cancellable,
          container: true,
          selected: isAction ? null : isSelected,
          enabled: enabled && _cancellable,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: 48.0 + tapAdjust,
              minHeight: 48.0 + tapAdjust,
            ),
            child: Center(
              widthFactor: 1.0,
              heightFactor: 1.0,
              child: chip,
            ),
          ),
        );
      },
    );
  }
}

/// 勾选标记绘制（复刻 Material `_RenderChip._paintCheck`）。
class _AppCheckmarkPainter extends CustomPainter {
  const _AppCheckmarkPainter({
    required this.boxSize,
    required this.t,
    required this.alpha,
    required this.color,
  });

  /// 勾选槽位边长（= Material `avatar.size.height`）。
  final double boxSize;

  /// 描线进度（0 → 1 两段式）。
  final double t;

  /// 整体不透明度（退场淡出）。
  final double alpha;

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0.0 || alpha <= 0.0) {
      return;
    }
    final double s = boxSize * 0.75;
    final double o = boxSize * 0.125;
    final Offset start = Offset(o + s * 0.15, o + s * 0.45);
    final Offset mid = Offset(o + s * 0.4, o + s * 0.7);
    final Offset end = Offset(o + s * 0.85, o + s * 0.25);

    final Paint paint = Paint()
      ..color = color.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _kCheckmarkStrokeWidth * boxSize / 24.0;

    final Path path = Path();
    if (t < 0.5) {
      final Offset drawMid = Offset.lerp(start, mid, t * 2.0)!;
      path.moveTo(start.dx, start.dy);
      path.lineTo(drawMid.dx, drawMid.dy);
    } else {
      final Offset drawEnd = Offset.lerp(mid, end, (t - 0.5) * 2.0)!;
      path.moveTo(start.dx, start.dy);
      path.lineTo(mid.dx, mid.dy);
      path.lineTo(drawEnd.dx, drawEnd.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_AppCheckmarkPainter oldDelegate) =>
      oldDelegate.t != t ||
      oldDelegate.alpha != alpha ||
      oldDelegate.color != color ||
      oldDelegate.boxSize != boxSize;
}