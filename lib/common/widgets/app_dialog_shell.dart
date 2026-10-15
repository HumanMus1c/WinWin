// 对话框内容替身（零 material，替代 Material `Dialog` / `AlertDialog`）。B7-c6-1。
//
// 复刻依据：`material_ui` 1.5.0 `lib/src/dialog.dart`
//   - `Dialog.build`（L260-318）：`AnimatedPadding(viewInsets + insetPadding)`（默认
//     `EdgeInsets.symmetric(horizontal: 40, vertical: 24)`，时长 100ms / `Curves.decelerate`）
//     → `MediaQuery.removeViewInsets` → `Align(center)` → `ConstrainedBox(minWidth: 280)`
//     → 表面（`Material(type: card, color, elevation, shape)`）；
//   - `AlertDialog.build`（L858-975，M3 分支）：`IntrinsicWidth` + `Column(stretch,
//     mainAxisSize.min)` = [title?, `Flexible(content)`, actions?]，各段 padding：
//       · title：`EdgeInsets.only(left: 24, top: 24, right: 24, bottom: content == null ? 20 : 0)`
//       · content：`EdgeInsets.only(left: 24, top: 16, right: 24, bottom: 24)`（title == null 时 top 参与缩放）
//       · actions：`EdgeInsets.only(left: 24, right: 24, bottom: 24)` + `OverflowBar(spacing: 8, alignment: end)`
//       · padding 缩放：`_scalePadding(textScaler.scale(1.0))`（1.0→1.0，最大 2.0 时收敛到 1/3）
//   - 文案样式：title = `textTheme.headlineSmall`、content = `textTheme.bodyMedium`
//     （本替身取等价的 `AppTextStyles.headlineSmall` / `bodyMedium`，B2-t1 零漂移派生）。
//
// 最终观感来源（`lib/theme/app_theme.dart` 的 `dialogTheme` 覆写）：
//   `elevation: 0` + `shape: RoundedRectangleBorder(_miuixRadiusLarge = 14×1.15 → 16)`；
//   背景仍是 M3 默认 `colorScheme.surfaceContainerHigh`。本替身按上述**最终态**逐项复刻，
//   目标是**零视觉变化**（机械替换口径）。
//
// 与路由的分工：遮罩 / `barrierDismissible` / 淡入缩放转场由 `AppDialogRoute`
// （`core/shell/app_dialogs.dart`）负责；本文件只负责"内容居中 + 内边距 + 表面 + 分段排版"。

import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

import 'package:winwin/core/shell/app_theme_host.dart';

/// 对话框外壳（替代 Material `Dialog` 的纯布局职责）。
///
/// 不引入任何 material 依赖：表面用 `DecoratedBox` + 圆角矩形绘制，
/// 内部控件所需的 `Material` 祖先由 `AppDialogRoute` 的透明层提供。
class AppDialogShell extends StatelessWidget {
  const AppDialogShell({
    super.key,
    this.insetPadding = const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
    this.constraints = const BoxConstraints(minWidth: 280),
    this.backgroundColor,
    this.borderRadius,
    required this.child,
  });

  /// 外边距（叠加键盘 `viewInsets`），对齐 Material 默认 40/24。
  final EdgeInsets insetPadding;

  /// 尺寸约束，对齐 Material 默认 `minWidth: 280`。
  final BoxConstraints constraints;

  /// 表面底色；null ⇒ `AppPalette.surfaceContainerHigh`（M3 对话框默认）。
  final Color? backgroundColor;

  /// 圆角半径；null ⇒ `AppShapes.large`（= 主题 `dialogTheme` 的 `_miuixRadiusLarge`）。
  final Radius? borderRadius;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    // 对齐 Material：`MediaQuery.viewInsetsOf(context) + insetPadding`。
    final EdgeInsets effectivePadding =
        MediaQuery.viewInsetsOf(context) + insetPadding;
    return AnimatedPadding(
      padding: effectivePadding,
      duration: const Duration(milliseconds: 100),
      curve: Curves.decelerate,
      child: MediaQuery.removeViewInsets(
        removeLeft: true,
        removeTop: true,
        removeRight: true,
        removeBottom: true,
        context: context,
        child: Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: constraints,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: backgroundColor ?? tokens.colors.surfaceContainerHigh,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(
                    borderRadius ?? tokens.shapes.large,
                  ),
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// 警告对话框（替代 Material `AlertDialog`）。
///
/// 参数面按现有 19 处调用点裁剪：`title` / `content` / `actions` 外，保留
/// `backgroundColor`（直播弹幕发送框用过深色底）与四组 padding 覆盖口。
class AppAlertDialog extends StatelessWidget {
  const AppAlertDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.actionsAlignment = MainAxisAlignment.end,
    this.backgroundColor,
    this.insetPadding,
    this.constraints,
    this.titlePadding,
    this.contentPadding,
    this.actionsPadding,
  });

  final Widget? title;

  final Widget? content;

  final List<Widget>? actions;

  /// 动作区对齐（对齐 Material `actionsAlignment`，默认靠右）。
  final MainAxisAlignment actionsAlignment;

  final Color? backgroundColor;

  final EdgeInsets? insetPadding;

  final BoxConstraints? constraints;

  final EdgeInsetsGeometry? titlePadding;

  final EdgeInsetsGeometry? contentPadding;

  final EdgeInsets? actionsPadding;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final TextDirection? textDirection = Directionality.maybeOf(context);
    final double paddingScaleFactor =
        _scalePadding(MediaQuery.textScalerOf(context).scale(1.0));

    Widget? titleWidget;
    if (title != null) {
      final EdgeInsets defaultTitlePadding = EdgeInsets.only(
        left: 24,
        top: 24,
        right: 24,
        bottom: content == null ? 20 : 0,
      );
      final EdgeInsets effective =
          titlePadding?.resolve(textDirection) ?? defaultTitlePadding;
      titleWidget = Padding(
        padding: EdgeInsets.only(
          left: effective.left * paddingScaleFactor,
          right: effective.right * paddingScaleFactor,
          top: effective.top * paddingScaleFactor,
          bottom: effective.bottom,
        ),
        child: DefaultTextStyle(
          style: tokens.text.headlineSmall ?? const TextStyle(),
          textAlign: TextAlign.start,
          child: Semantics(container: true, child: title),
        ),
      );
    }

    Widget? contentWidget;
    if (content != null) {
      const EdgeInsets defaultContentPadding = EdgeInsets.only(
        left: 24,
        top: 16,
        right: 24,
        bottom: 24,
      );
      final EdgeInsets effective =
          contentPadding?.resolve(textDirection) ?? defaultContentPadding;
      contentWidget = Padding(
        padding: EdgeInsets.only(
          left: effective.left * paddingScaleFactor,
          right: effective.right * paddingScaleFactor,
          top: title == null
              ? effective.top * paddingScaleFactor
              : effective.top,
          bottom: effective.bottom,
        ),
        child: DefaultTextStyle(
          style: tokens.text.bodyMedium ?? const TextStyle(),
          child: Semantics(container: true, explicitChildNodes: true, child: content),
        ),
      );
    }

    Widget? actionsWidget;
    if (actions != null) {
      const EdgeInsets effectiveActionsPadding =
          EdgeInsets.only(left: 24, right: 24, bottom: 24);
      actionsWidget = Padding(
        padding: actionsPadding ?? effectiveActionsPadding,
        // 替代 Material `OverflowBar`：M3 下 spacing = (buttonPadding ?? 16)/2 = 8。
        // 现有调用点的动作数 ≤ 3，不会触发溢出换行，`Wrap` 单行即等价。
        child: Wrap(
          alignment: _wrapAlignment(actionsAlignment),
          spacing: 8,
          runSpacing: 0,
          children: actions!,
        ),
      );
    }

    return AppDialogShell(
      insetPadding:
          insetPadding ?? const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      constraints: constraints ?? const BoxConstraints(minWidth: 280),
      backgroundColor: backgroundColor,
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ?titleWidget,
            if (contentWidget != null) Flexible(child: contentWidget),
            ?actionsWidget,
          ],
        ),
      ),
    );
  }
}

/// 对齐 Material `_scalePadding`：文本放大时按比例收缩 padding（1.0 → 1.0，2.0 → 1/3）。
double _scalePadding(double textScaleFactor) {
  final double clamped = textScaleFactor.clamp(1.0, 2.0);
  return lerpDouble(1.0, 1.0 / 3.0, clamped - 1.0)!;
}

WrapAlignment _wrapAlignment(MainAxisAlignment alignment) {
  switch (alignment) {
    case MainAxisAlignment.start:
      return WrapAlignment.start;
    case MainAxisAlignment.end:
      return WrapAlignment.end;
    case MainAxisAlignment.center:
      return WrapAlignment.center;
    case MainAxisAlignment.spaceBetween:
      return WrapAlignment.spaceBetween;
    case MainAxisAlignment.spaceAround:
      return WrapAlignment.spaceAround;
    case MainAxisAlignment.spaceEvenly:
      return WrapAlignment.spaceEvenly;
  }
}