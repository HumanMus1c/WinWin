import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart' show MiuixMotion;

import 'app_transition.dart';

/// 对话框路由替身（取代 Material `showDialog` / `DialogRoute`）。
///
/// 关键契约（与 Material 版一致，保证切换后行为不变）：
/// - 仍是 **`PopupRoute` 子类型** → `AppEscapeScope` 的"栈顶是否弹层"判定
///   （`observer.hasPopupOnTop`，Esc 第一层）自动继续生效，无需改动；
/// - `barrierDismissible` / `barrierColor`（默认 42% 黑）/ `barrierLabel` 语义一致；
/// - 返回 `Future<T?>`，`await` 结果与 `showDialog` 相同。
///
/// 转场走 Miuix 规范（淡入 + 轻微放大；缩放 ≤ 1，不越界）。
class AppDialogRoute<T> extends PopupRoute<T> {
  AppDialogRoute({
    required this.builder,
    this.barrierDismissible = true,
    this.barrierColor = const Color(0x8A000000),
    this.barrierLabel = '关闭',
    super.settings,
  });

  final WidgetBuilder builder;

  @override
  final bool barrierDismissible;

  @override
  final Color? barrierColor;

  @override
  final String barrierLabel;

  @override
  Duration get transitionDuration => kMiuixTransitionDuration;

  @override
  Duration get reverseTransitionDuration =>
      const Duration(milliseconds: 200);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) =>
      builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: MiuixMotion.standardDecelerate,
      reverseCurve: MiuixMotion.standardAccelerate,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
        child: child,
      ),
    );
  }
}

/// 底部面板路由替身（取代 Material `showModalBottomSheet`）。
class AppSheetRoute<T> extends PopupRoute<T> {
  AppSheetRoute({
    required this.builder,
    this.barrierDismissible = true,
    this.barrierColor = const Color(0x8A000000),
    this.barrierLabel = '关闭',
    this.isScrollControlled = false,
    super.settings,
  });

  final WidgetBuilder builder;

  @override
  final bool barrierDismissible;

  @override
  final Color? barrierColor;

  @override
  final String barrierLabel;

  /// true 时内容可超过默认 90% 窗高上限（对齐 Material 同名参数语义）。
  final bool isScrollControlled;

  @override
  Duration get transitionDuration => kMiuixTransitionDuration;

  @override
  Duration get reverseTransitionDuration =>
      const Duration(milliseconds: 200);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final maxHeight = isScrollControlled
        ? double.infinity
        : MediaQuery.sizeOf(context).height * 0.9;
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: builder(context),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: MiuixMotion.standardDecelerate,
      reverseCurve: MiuixMotion.standardAccelerate,
    );
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(curved),
      child: child,
    );
  }
}

/// 弹出对话框（替身：`showDialog`）。默认挂到根 Navigator，与 Material 版一致。
Future<T?> showAppDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useRootNavigator = true,
}) {
  return Navigator.of(context, rootNavigator: useRootNavigator).push<T>(
    AppDialogRoute<T>(
      builder: builder,
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor ?? const Color(0x8A000000),
      barrierLabel: barrierLabel ?? '关闭',
    ),
  );
}

/// 弹出底部面板（替身：`showModalBottomSheet`）。
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool isScrollControlled = false,
  bool useRootNavigator = true,
}) {
  return Navigator.of(context, rootNavigator: useRootNavigator).push<T>(
    AppSheetRoute<T>(
      builder: builder,
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor ?? const Color(0x8A000000),
      barrierLabel: barrierLabel ?? '关闭',
      isScrollControlled: isScrollControlled,
    ),
  );
}
