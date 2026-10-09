import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart' show MiuixScaffold;

import 'app_theme_host.dart';

/// 页面骨架替身（取代 Material `Scaffold`）。
///
/// 基于 flutter_miuix [MiuixScaffold]（纯 widgets 层实现，自带
/// topBar/bottomBar/FAB/floatingToolbar/snackbarHost/popupHost 槽位与
/// 窗口内边距换算）；本类只补项目口径的默认值：
/// - 背景默认取 [AppTokens] 的 `colors.background`（可由 [backgroundColor] 覆盖）；
/// - `content` 槽位统一承载 [body]（把窗口内边距透传给页面内容）；
/// - **悬浮返回按钮**（[showBackButton]）：可 pop 时在内容左上角悬浮显示，
///   取代页面标题栏里的返回入口（2026-10-08 起项目去除页面标题栏，统一走此入口）。
///
/// L0 阶段：本文件零 Material 依赖，页面在 B5 批次分批从 `Scaffold` 切换过来。
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    this.topBar,
    this.bottomBar,
    this.floatingActionButton,
    this.snackbarHost,
    this.popupHost,
    this.backgroundColor,
    this.showBackButton = true,
    this.actions,
    required this.body,
  });

  /// 顶栏（通常为 MiuixTopAppBar 或页面自绘顶栏）。
  ///
  /// 2026-10-08 起项目**默认不再使用页面标题栏**（窗口标题条 + 左侧导航已表达位置），
  /// 仅保留槽位供个别必需场景（如搜索页的输入框）使用。
  final Widget? topBar;

  /// 底栏。
  final Widget? bottomBar;

  /// 浮动按钮。
  final Widget? floatingActionButton;

  /// Toast/Snackbar 宿主槽位。
  final Widget? snackbarHost;

  /// 弹层宿主槽位（MiuixOverlayDialog 等）。
  final Widget? popupHost;

  /// 背景色；null 时取当前 Token 的应用背景色。
  final Color? backgroundColor;

  /// 是否在内容左上角悬浮返回按钮（[Navigator.canPop] 为真时显示）。
  final bool showBackButton;

  /// 悬浮操作区（右上角）：原顶栏 `actions` 的落点（刷新/清空/分享等）。
  ///
  /// 2026-10-08 起页面不再使用标题栏，顶栏里的操作按钮改由本槽位悬浮承载。
  final List<Widget>? actions;

  /// 页面主体。
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    return MiuixScaffold(
      topBar: topBar,
      bottomBar: bottomBar,
      floatingActionButton: floatingActionButton,
      snackbarHost: snackbarHost,
      popupHost: popupHost,
      containerColor: backgroundColor ?? tokens.colors.background,
      content: (EdgeInsets padding) {
        final content = Padding(padding: padding, child: body);
        final canPop = showBackButton &&
            (Navigator.maybeOf(context)?.canPop() ?? false);
        final hasActions = actions != null && actions!.isNotEmpty;
        if (!canPop && !hasActions) return content;
        return Stack(
          children: [
            content,
            if (canPop)
              Positioned(
                left: 8,
                top: 8,
                child: FloatingBackButton(tokens: tokens),
              ),
            if (hasActions)
              Positioned(
                right: 8,
                top: 8,
                child: Row(mainAxisSize: MainAxisSize.min, children: actions!),
              ),
          ],
        );
      },
    );
  }
}

/// 悬浮返回按钮：小圆形半透明底 + 图标，无标题栏页面的返回入口。
class FloatingBackButton extends StatelessWidget {
  const FloatingBackButton({super.key, required this.tokens, this.onPressed});

  final AppTokens tokens;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '返回',
      child: GestureDetector(
        onTap: onPressed ?? () => Navigator.of(context).maybePop(),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: tokens.colors.surfaceContainerHighest.withValues(alpha: 0.85),
              shape: BoxShape.circle,
            ),
            child: Icon(
              CupertinoIcons.chevron_back,
              size: 20,
              color: tokens.colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
