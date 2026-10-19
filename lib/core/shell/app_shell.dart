import 'dart:ui' show PointerDeviceKind;

import 'package:cupertino_ui/cupertino_ui.dart' show DefaultCupertinoLocalizations;
import 'package:flutter/widgets.dart';

import 'package:winwin/common/widgets/app_scroll_bar.dart';
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

  /// 全局滚动条口径（**单一来源**，2026-10-17 反馈轮 5）。
  ///
  /// 基类实现（`scroll_configuration.dart`）在 windows/macos/linux 返回
  /// `RawScrollbar(controller: details.controller, child: child)`：其 `radius` 与
  /// `trackRadius` 默认均为 null ⇒ `ScrollbarPainter` 走 `canvas.drawRect` 分支
  /// （**方角硬矩形条**）、颜色 `0x66BCBCBC`、粗细 6.0。这与项目口径（圆角 pill、
  /// hover/拖动三态补间、hover 触发带语义）不一致，也是用户实机反馈「番剧详情页
  /// 两侧内容区域滚动条初始默认态是硬矩形条」的根因。
  ///
  /// 现统一改为项目自有 [AppScrollBar]：一处收口，全应用竖向滚动视图自动获得
  /// 一致样式；[AppScrollBar] 内部的 `_NoFrameworkScrollBar` 会抑制嵌套滚动视图的
  /// 重复挂载，已手动包裹的页面（番剧详情/热门/关注/推荐）不会出现双条。
  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      AppScrollBar.attach(child: child, details: details);
}

/// 应用外壳替身（取代 MaterialApp 组装）。
///
/// 基于 **widgets 层** `WidgetsApp`，把 MaterialApp 时代由框架隐式提供的能力
/// 显式接管：
/// - 路由：`pageRouteBuilder` → [AppRoute]（Miuix 转场，替代 MaterialApp 的
///   `MaterialPageRoute` + `pageTransitionsTheme` 体系）；
/// - 主题：`AppThemeHost`（[AppTokens] 通道，**唯一**主题来源）。B7 起不再提供
///   过渡期 Material `ThemeData`（MD3 库级退役完成：应用侧已无 material_ui
///   消费者；flutter_miuix 内部 SDK TextField 所需的 SDK material 环境由
///   `MiuixCompat` 在需要处局部提供）；
/// - 本地化：仅装配 Cupertino 委托（widgets 层由 `WidgetsApp` 自带
///   `DefaultWidgetsLocalizations`）；material_ui 侧的 `DefaultMaterialLocalizations`
///   随 B7 一并摘除，SDK material 本地化由 `MiuixCompat` 局部注入；
/// - 文本基底：显式设置 `DefaultTextStyle`——WidgetsApp 默认基底是"黄绿双下划线"
///   错误样式（项目在标题条/Toast 上已两次踩坑）；
/// - 保留既有 builder 链（`MiuixThemeScope → MiuixToastHost →
///   ImmersiveTitleBarShell → AppEscapeScope`）与 Navigator 观察者；
/// - 全局滚动行为经 `ScrollConfiguration` 自挂（WidgetsApp 无 `scrollBehavior` 参数）。
///
/// 不含（相对 MaterialApp 的有意差异）：`ScaffoldMessenger`（项目 Toast 走
/// MiuixToastHost；`appScaffoldMessengerKey` 为无消费者的死句柄，已删除）。
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

  /// 当前是否深色（由 ThemeNotifier 解析后传入，替代 Material 的 ThemeMode）。
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
    final brightness = isDark ? Brightness.dark : Brightness.light;
    final tokens = AppThemeHost.tokensFor(brightness);
    final Widget app = WidgetsApp(
      title: title,
      color: tokens.colors.background,
      navigatorKey: navigatorKey,
      navigatorObservers: navigatorObservers,
      pageRouteBuilder: appPageRouteBuilder,
      // 本地化：widgets 层由 WidgetsApp 自带；此处仅保留 Cupertino 委托。
      // material_ui 的 DefaultMaterialLocalizations 随 B7 退役摘除——应用侧已无
      // material_ui 控件；flutter_miuix 内部 SDK TextField 读的是 **SDK 类型**的
      // MaterialLocalizations（与 material_ui 类型不可互换），由 MiuixCompat 提供。
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        DefaultCupertinoLocalizations.delegate,
      ],
      home: home,
      builder: (BuildContext context, Widget? child) {
        final Widget routed = AppEscapeScope(
          navigatorKey: navigatorKey,
          observer: escapeObserver,
          child: child ?? const SizedBox.shrink(),
        );
        return MiuixThemeScope(
          isDark: isDark,
          fontFamily: fontFamily,
          child: MiuixToastHost(
            child: ImmersiveTitleBarShell(
              // 文本基底：显式声明（WidgetsApp 默认为错误样式）。
              // 字体取 MiuixTheme（经 Builder 拿到 scope 内 context）。
              child: Builder(
                builder: (innerContext) => DefaultTextStyle(
                  style: TextStyle(
                    color: tokens.colors.onBackground,
                    fontSize: 14,
                    height: 1.4,
                    decoration: TextDecoration.none,
                    fontFamily: appFontFamilyOf(innerContext),
                  ),
                  child: routed,
                ),
              ),
            ),
          ),
        );
      },
    );
    return AppThemeHost(
      tokens: tokens,
      child: ScrollConfiguration(
        behavior: const AppScrollBehavior(),
        child: app,
      ),
    );
  }
}