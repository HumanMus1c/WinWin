import 'package:flutter/widgets.dart';

import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/core/input/app_escape_scope.dart';
import 'package:winwin/core/shell/app_routes.dart';
import 'package:winwin/core/shell/app_shell.dart' show AppScrollBehavior;
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/theme/miuix_theme_bridge.dart';

/// B1b · 统一测试宿主（test 面去 `package:material_ui`）。
///
/// 复刻 `main.dart` / `AppShell` 的**环境装配**（`AppThemeHost` +
/// `MiuixThemeScope` + `MiuixToastHost` + `AppEscapeScope` + `DefaultTextStyle`
/// + 全局滚动行为），使 widget 测试不再以 `MaterialApp` / `Scaffold` 为宿主、
/// 也不再直接依赖 material_ui。
///
/// 与 `AppShell` 的**有意差异**：本宿主**不含** `ImmersiveTitleBarShell`
/// （Windows 窗口标题条属宿主外壳/平台关注点，不应影响 widget 测试的布局与
/// 指针命中）；其余链路与 `AppShell` 同构。
///
/// 迁移口径：
/// - `MaterialApp(home: Scaffold(body: X))` → `AppTestApp(home: AppTestScaffold(body: X))`
/// - 或函数式：`await tester.pumpWidget(appTestHost(X));`
///
/// 注意：本文件**不得** import `package:material_ui`（B1b 门槛）。
Widget appTestHost(
  Widget child, {
  bool dark = false,
  String? fontFamily,
  GlobalKey<NavigatorState>? navigatorKey,
  AppEscapeNavigatorObserver? escapeObserver,
  List<NavigatorObserver> navigatorObservers = const <NavigatorObserver>[],
}) {
  return _buildHost(
    home: child,
    dark: dark,
    fontFamily: fontFamily,
    navigatorKey: navigatorKey,
    escapeObserver: escapeObserver,
    navigatorObservers: navigatorObservers,
  );
}

Widget _buildHost({
  required Widget home,
  required bool dark,
  String? fontFamily,
  GlobalKey<NavigatorState>? navigatorKey,
  AppEscapeNavigatorObserver? escapeObserver,
  List<NavigatorObserver> navigatorObservers = const <NavigatorObserver>[],
}) {
  final Brightness brightness = dark ? Brightness.dark : Brightness.light;
  final AppTokens tokens = AppThemeHost.tokensFor(brightness);
  final GlobalKey<NavigatorState> key =
      navigatorKey ?? GlobalKey<NavigatorState>();
  final AppEscapeNavigatorObserver observer =
      escapeObserver ?? AppEscapeNavigatorObserver();

  return AppThemeHost(
    tokens: tokens,
    child: ScrollConfiguration(
      behavior: const AppScrollBehavior(),
      child: WidgetsApp(
        title: 'AppTestHost',
        color: tokens.colors.background,
        navigatorKey: key,
        navigatorObservers: navigatorObservers,
        pageRouteBuilder: appPageRouteBuilder,
        home: home,
        builder: (BuildContext context, Widget? child) => AppEscapeScope(
          navigatorKey: key,
          observer: observer,
          child: MiuixThemeScope(
            isDark: dark,
            fontFamily: fontFamily,
            child: MiuixToastHost(
              child: DefaultTextStyle(
                style: TextStyle(
                  color: tokens.colors.onBackground,
                  fontSize: 14,
                  height: 1.4,
                  decoration: TextDecoration.none,
                ),
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// `MaterialApp` 的同形零-material 替身（仅覆盖测试所需子集）。
class AppTestApp extends StatelessWidget {
  const AppTestApp({
    super.key,
    this.title = 'AppTestHost',
    this.home,
    this.dark = false,
    this.fontFamily,
    this.navigatorKey,
    this.navigatorObservers = const <NavigatorObserver>[],
    this.escapeObserver,
    this.debugShowCheckedModeBanner = true,
    this.theme,
  });

  final String title;
  final Widget? home;

  /// 明暗（替代 Material 的 ThemeMode）。
  final bool dark;

  /// 应用字体族。
  final String? fontFamily;

  final GlobalKey<NavigatorState>? navigatorKey;
  final List<NavigatorObserver> navigatorObservers;
  final AppEscapeNavigatorObserver? escapeObserver;
  final bool debugShowCheckedModeBanner;

  /// 兼容旧用例传入的 `AppTheme.lightFor()` 等主题对象；本宿主自建等价环境，
  /// 该入参仅为调用签名兼容而保留（不参与装配）。
  final Object? theme;

  @override
  Widget build(BuildContext context) => _buildHost(
        home: home ?? const SizedBox.shrink(),
        dark: dark,
        fontFamily: fontFamily,
        navigatorKey: navigatorKey,
        escapeObserver: escapeObserver,
        navigatorObservers: navigatorObservers,
      );
}

/// `Scaffold` 的同形零-material 替身：仅提供 body/appBar/背景三槽位，
/// 不引入 Material 祖先（宿主环境由 [AppTestApp] / [appTestHost] 提供）。
class AppTestScaffold extends StatelessWidget {
  const AppTestScaffold({
    super.key,
    this.appBar,
    this.body,
    this.backgroundColor,
    this.resizeToAvoidBottomInset,
  });

  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Color? backgroundColor;
  final bool? resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    final Widget content = body ?? const SizedBox.shrink();
    return ColoredBox(
      color: backgroundColor ?? const Color(0x00000000),
      child: appBar == null
          ? content
          : Column(
              children: <Widget>[
                appBar!,
                Expanded(child: content),
              ],
            ),
    );
  }
}