import 'package:flutter/material.dart';

import 'package:winwin/theme/app_chrome.dart';
import 'package:winwin/theme/app_shapes.dart';
import 'package:winwin/theme/inherited_ui_style.dart';
import 'package:winwin/theme/ui_style.dart';

/// 轻量脚手架（Phase 7.5.1）。
///
/// 参照 PiliPlus 的 `SimpleScaffold`：避开 Flutter `Scaffold` 的限制
/// （如 AppBar 高度固定、FAB 位置约束），提供三槽位（appBar + body + fab）
/// 自由组合的轻量容器，用于详情页、子页面等非主 tab 场景。
///
/// 特性：
/// - [appBar]：可空的顶部栏 Widget（非标准 AppBar，可任意自定义）。
/// - [body]：主体内容，自动填充剩余空间。
/// - [fab]：可空的浮动按钮，定位右下角。
/// - 背景：按 [UiStyle] 解析的 [AppChrome] 提供 scaffoldBackgroundColor。
/// - SafeArea：默认启用顶部内边距，避免状态栏遮挡。
class SimpleScaffold extends StatelessWidget {
  const SimpleScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.fab,
    this.fabPosition = FabPosition.end,
    this.topSafeArea = true,
    this.bottomSafeArea = false,
    this.backgroundColor,
    this.extendBodyBehindAppBar = false,
  });

  /// 顶部栏（任意 Widget，建议使用 [SliverAppBar] 或自定义 Row）。
  final Widget? appBar;

  /// 主体内容。
  final Widget body;

  /// 浮动按钮（可空）。
  final Widget? fab;

  /// FAB 位置（end=右下，center=中下，start=左下）。
  final FabPosition fabPosition;

  /// 是否启用顶部 SafeArea。
  final bool topSafeArea;

  /// 是否启用底部 SafeArea。
  final bool bottomSafeArea;

  /// 自定义背景色（默认使用 scaffoldBackgroundColor）。
  final Color? backgroundColor;

  /// body 是否延伸到 appBar 后方（用于透明 appBar + 渐变背景场景）。
  final bool extendBodyBehindAppBar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final chrome = theme.extension<AppChrome>() ?? AppChrome.material3;
    final shapes = theme.extension<AppShapes>() ?? AppShapes.material3;
    final style = InheritedUiStyle.of(context);
    final renderer = resolvePrimitiveRenderer(style);

    final bg = backgroundColor ?? theme.scaffoldBackgroundColor;

    Widget content = body;
    if (topSafeArea || bottomSafeArea) {
      content = SafeArea(
        top: topSafeArea,
        bottom: bottomSafeArea,
        child: content,
      );
    }

    // 两套风格顶栏外观差异：
    // - MD3：表面色 + scrolledUnderElevation
    // - Miuix：透明背景 + 无分割线（扁平通透）
    final effectiveAppBar = appBar != null
        ? _StyleAwareAppBar(
            chrome: chrome,
            shapes: shapes,
            cs: cs,
            renderer: renderer,
            child: appBar!,
          )
        : null;

    final stackedBody = extendBodyBehindAppBar && effectiveAppBar != null
        ? Stack(
            children: [
              Positioned.fill(child: content),
              Positioned(top: 0, left: 0, right: 0, child: effectiveAppBar),
            ],
          )
        : Column(
            children: [
              ?effectiveAppBar,
              Expanded(child: content),
            ],
          );

    return ColoredBox(
      color: bg,
      child: Stack(
        children: [
          Positioned.fill(child: stackedBody),
          if (fab != null)
            Positioned(
              bottom: 16,
              left: fabPosition == FabPosition.start ? 16 : null,
              right: fabPosition == FabPosition.end ? 16 : null,
              child: fab!,
            ),
        ],
      ),
    );
  }
}

/// FAB 位置枚举。
enum FabPosition { start, center, end }

/// 风格感知的顶栏包装器。
class _StyleAwareAppBar extends StatelessWidget {
  const _StyleAwareAppBar({
    required this.child,
    required this.chrome,
    required this.shapes,
    required this.cs,
    required this.renderer,
  });

  final Widget child;
  final AppChrome chrome;
  final AppShapes shapes;
  final ColorScheme cs;
  final PrimitiveRenderer renderer;

  @override
  Widget build(BuildContext context) {
    switch (renderer) {
      case PrimitiveRenderer.material3:
        // MD3：表面色 + scrolledUnderElevation（由 Material 自动处理）
        return Material(
          color: cs.surface,
          elevation: 0,
          child: child,
        );
      case PrimitiveRenderer.miuix:
        // Miuix：透明背景，无分割线
        return child;
    }
  }
}
