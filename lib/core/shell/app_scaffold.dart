import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart' show MiuixScaffold;

import 'app_theme_host.dart';

/// 页面骨架替身（取代 Material `Scaffold`）。
///
/// 基于 flutter_miuix [MiuixScaffold]（纯 widgets 层实现，自带
/// topBar/bottomBar/FAB/floatingToolbar/snackbarHost/popupHost 槽位与
/// 窗口内边距换算）；本类只补项目口径的默认值：
/// - 背景默认取 [AppTokens] 的 `colors.background`（可由 [backgroundColor] 覆盖）；
/// - `content` 槽位统一承载 [body]（把窗口内边距透传给页面内容）。
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
    required this.body,
  });

  /// 顶栏（通常为 MiuixTopAppBar 或页面自绘顶栏）。
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
      content: (EdgeInsets padding) =>
          Padding(padding: padding, child: body),
    );
  }
}
