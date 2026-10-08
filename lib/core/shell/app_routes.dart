import 'package:flutter/widgets.dart';

import 'app_transition.dart';

/// 页面路由替身（取代 Material `MaterialPageRoute`）。
///
/// 基于 **widgets 层** [PageRouteBuilder]，转场动画复用 [MiuixPageTransition]
/// （与既有 Material 侧 `MiuixPageTransitionsBuilder` 同一动画核，替换前后观感一致：
/// 新页淡入 + 轻微放大 0.94→1.0，被覆盖页 1.0→0.96 回退复原，缩放恒 ≤ 1 不越界）。
///
/// L0 阶段：本文件零 Material 依赖；调用点在 B3 批次分批从 `MaterialPageRoute`
/// 切换为 `AppRoute`（124 处 / 35 文件）。
class AppRoute<T> extends PageRouteBuilder<T> {
  AppRoute({
    required WidgetBuilder builder,
    super.settings,
    super.fullscreenDialog,
    this.title,
  }) : super(
          pageBuilder: (BuildContext context, Animation<double> animation,
                  Animation<double> secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (BuildContext context,
                  Animation<double> animation,
                  Animation<double> secondaryAnimation,
                  Widget child) =>
              // 只用本路由的 animation：被覆盖页静止（性能取向）。
              MiuixPageTransition(animation: animation, child: child),
          transitionDuration: kMiuixTransitionDuration,
          reverseTransitionDuration: kMiuixTransitionDuration,
        );

  /// 页面标题（供无障碍/调试；不参与渲染）。
  final String? title;
}

/// WidgetsApp 的 `pageRouteBuilder` 工厂：把所有 `home`/`routes` 生成的路由
/// 统一替换为 [AppRoute]（应用壳切换时使用）。
PageRoute<T> appPageRouteBuilder<T>(
  RouteSettings settings,
  WidgetBuilder builder,
) =>
    AppRoute<T>(settings: settings, builder: builder);
