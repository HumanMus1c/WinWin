import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/widgets.dart';

import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/core/input/app_escape_scope.dart';
import 'package:winwin/theme/miuix_theme_bridge.dart';
import 'package:winwin/ui/components/immersive_title_bar.dart';

import 'app_routes.dart';
import 'app_theme_host.dart';

/// 全局滚动/指针行为（**widgets 层**实现，取代 main.dart 中基于
/// MaterialScrollBehavior 的版本）：Windows 桌面开启平滑滚动与全设备指针。
class AppScrollBehavior extends ScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}

/// 应用外壳替身（取代 MaterialApp 组装）。
///
/// 基于 **widgets 层** `WidgetsApp`，把 MaterialApp 时代由框架隐式提供的能力
/// 显式接管：
/// - 路由：`pageRouteBuilder` → [AppRoute]（Miuix 转场，替代 MaterialApp 的
///   `MaterialPageRoute` + `pageTransitionsTheme` 体系）；
/// - 主题：`AppThemeHost`（[AppTokens] 通道）替代 `Theme`/`ThemeData`/
///   `ThemeExtension`；
/// - 文本基底：显式设置 `DefaultTextStyle`——WidgetsApp 默认基底是"黄绿双下划线"
///   错误样式（项目在标题条/Toast 上已两次踩坑）；
/// - 保留既有 builder 链（`MiuixThemeScope → MiuixToastHost →
///   ImmersiveTitleBarShell → AppEscapeScope`）与 Navigator 观察者；
/// - 全局滚动行为经 `ScrollConfiguration` 自挂（WidgetsApp 无 `scrollBehavior` 参数）。
///
/// L0 阶段：本文件零 material_ui 依赖；B1 批次在 main.dart 以本壳替换 MaterialApp。
class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.title,
    required this.home,
    required this.isDark,
    required this.navigatorKey,
    required this.escapeObserver,
    this.navigatorObservers = const <NavigatorObserver>[],
    this.fontFamily,
  });

  /// 应用标题（任务栏/路由名）。
  final String title;

  /// 首屏内容。
  final Widget home;

  /// 当前是否深色（由 ThemeNotifier 解析后传入，替代 ThemeMode）。
  final bool isDark;

  /// 根 Navigator 键（同时供 [AppEscapeScope] 执行 maybePop）。
  final GlobalKey<NavigatorState> navigatorKey;

  /// 路由栈观察者（Esc 分层语义）。
  final AppEscapeNavigatorObserver escapeObserver;

  /// 额外 Navigator 观察者（如全局 routeObserver）。
  final List<NavigatorObserver> navigatorObservers;

  /// 应用字体族（AppFontNotifier）。
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.tokensFor(
      isDark ? Brightness.dark : Brightness.light,
    );
    return AppThemeHost(
      tokens: tokens,
      child: ScrollConfiguration(
        behavior: const AppScrollBehavior(),
        child: WidgetsApp(
          title: title,
          color: tokens.colors.background,
          navigatorKey: navigatorKey,
          navigatorObservers: navigatorObservers,
          pageRouteBuilder: appPageRouteBuilder,
          home: home,
          builder: (BuildContext context, Widget? child) {
            final Widget app = AppEscapeScope(
              navigatorKey: navigatorKey,
              observer: escapeObserver,
              child: child ?? const SizedBox.shrink(),
            );
            return MiuixThemeScope(
              isDark: isDark,
              fontFamily: fontFamily,
              child: MiuixToastHost(
                child: ImmersiveTitleBarShell(
                  // 文本基底：显式声明（默认为 WidgetsApp 的错误样式）。
                  child: DefaultTextStyle(
                    style: TextStyle(
                      color: tokens.colors.onBackground,
                      fontSize: 14,
                      height: 1.4,
                      decoration: TextDecoration.none,
                    ),
                    child: app,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
