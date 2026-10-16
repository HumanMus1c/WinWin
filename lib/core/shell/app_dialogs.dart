import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart' show MiuixMotion;
import 'package:winwin/core/shell/app_theme_host.dart';

import 'app_transition.dart';
import 'app_transparent_host.dart';

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
  ) {
    // 2026-10-09 收口-3：对话框内容统一包一层透明祖先（对齐 AppSheetRoute 做法与
    // Material 原版 DialogRoute 契约）。此前无此祖先时，对话框内的 Material 控件
    // （TextButton/TextField 等，约 40 个 showAppDialog 调用点）在 debug 下红屏、
    // release 下 hover 空崩（当日崩溃日志实锤，含 2 起 _TextFieldState.build）。
    // B7-c7 第二批：material_ui 的透明 Material 层退役，替换为 [AppTransparentHost]
    // （等价"Material 祖先 + 默认文本样式"，见该文件复刻依据）；视觉零变化。
    return AppTransparentHost(child: builder(context));
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
    this.backgroundColor,
    super.settings,
  });

  final WidgetBuilder builder;

  /// 面板底色（对齐 Material 同名参数；null = 由内容自绘底色）。
  final Color? backgroundColor;

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
    // 高度上限对齐 Material：
    // - isScrollControlled=false → 9/16 屏高（_ModalBottomSheetLayout 默认比例）；
    // - isScrollControlled=true  → 整屏高度（**有界**，不是无限——否则内容里的
    //   Column + Expanded 会因无界高度塌陷，见 2026-10-08 收藏面板回归）。
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxHeight = isScrollControlled ? screenHeight : screenHeight * 9 / 16;
    // 宽度上限对齐 M3 默认（BottomSheetThemeData.constraints = maxWidth 640）：
    // 宽窗口下面板居中且不占满整屏。
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight, maxWidth: 640),
        // Material 的面板会给内容套一层表面（底色 + 裁剪 + **Material 祖先**）；
        // 缺这层祖先时，面板内的 Material 控件（如 CheckboxListTile）会构建失败，
        // release 下渲染为大灰块（见 2026-10-08 收藏面板回归）。
        // B7-c7 第二批：material_ui 的 Material 表面退役 → `ClipRRect`（圆角 28 +
        // antiAlias 裁剪，逐项对齐 M3 BottomSheet 口径）+ `ColoredBox`（面板底色）
        // + [AppTransparentHost]（补"祖先 + 默认文本样式"），视觉零变化。
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: ColoredBox(
            color: backgroundColor ??
                AppThemeHost.of(context).colors.surfaceContainerLow,
            child: AppTransparentHost(child: builder(context)),
          ),
        ),
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
///
/// 签名与 Material 版对齐：`context` 为**具名必填**参数。
Future<T?> showAppDialog<T>({
  required BuildContext context,
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
///
/// 签名与 Material 版对齐：`context` 为**具名必填**参数。
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool isScrollControlled = false,
  Color? backgroundColor,
  bool useRootNavigator = true,
}) {
  return Navigator.of(context, rootNavigator: useRootNavigator).push<T>(
    AppSheetRoute<T>(
      builder: builder,
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor ?? const Color(0x8A000000),
      barrierLabel: barrierLabel ?? '关闭',
      isScrollControlled: isScrollControlled,
      backgroundColor: backgroundColor,
    ),
  );
}
