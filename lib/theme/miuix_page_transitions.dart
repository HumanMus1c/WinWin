import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoPageTransitionsBuilder;
import 'package:material_ui/material_ui.dart';

import 'package:winwin/core/shell/app_transition.dart';

/// 转场时长（别名：动画核定义在 `core/shell/app_transition.dart`，
/// Material 侧 Builder 与自建 `AppRoute` 共用同一常量与动画核）。
const Duration kMiuixPageTransitionDuration = kMiuixTransitionDuration;

/// Miuix 页面转场总开关（兜底回退用）。
///
/// 置 `false` 即回退到 material_ui 的平台默认转场（Windows 为
/// [ZoomPageTransitionsBuilder]），无需改动任何结构 —— app_theme 依此决定
/// 是否注册 [kMiuixPageTransitions]。
///
/// 注：B7（material_ui 摘除）后本开关随本文件一并退役，转场统一由
/// `AppRoute`（core/shell/app_routes.dart）承载。
const bool kUseMiuixPageTransitions = true;

/// Miuix 转场主题：windows/linux/android/fuchsia 走 [MiuixPageTransitionsBuilder]。
///
/// iOS/macOS 显式保留 [CupertinoPageTransitionsBuilder]（其边缘侧滑返回手势
/// 语义不被破坏，不参与 Miuix 单轨；不依赖 material_ui 的平台兜底表）。
const PageTransitionsTheme kMiuixPageTransitions = PageTransitionsTheme(
  builders: <TargetPlatform, PageTransitionsBuilder>{
    TargetPlatform.windows: MiuixPageTransitionsBuilder(),
    TargetPlatform.linux: MiuixPageTransitionsBuilder(),
    TargetPlatform.android: MiuixPageTransitionsBuilder(),
    TargetPlatform.fuchsia: MiuixPageTransitionsBuilder(),
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
  },
);

/// Material 侧的 Miuix 页面转场注册器（动效核见 [MiuixPageTransition]）。
///
/// 修复「进出视频页时页面瞬间叠在沉浸标题条之上」的根因：material_ui 默认
/// Zoom 转场会缩放越界（push 旧页 1.05 / pop 被弹出页 1.10），而本转场的
/// **所有缩放 ≤ 1.0 且锚点 topCenter**，绘制范围恒不超出路由视口。
///
/// 本类只负责"把动画核挂到 Material 转场主题上"；B3 批次起调用点改用
/// `AppRoute`（内嵌同一动画核），B7 随 material_ui 一并删除本文件。
class MiuixPageTransitionsBuilder extends PageTransitionsBuilder {
  const MiuixPageTransitionsBuilder();

  @override
  Duration get transitionDuration => kMiuixPageTransitionDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // 注：不使用 secondaryAnimation —— 被覆盖的当前页保持静止（性能取向，
    // 见 MiuixPageTransition 文档）。label/configuredMs 供转场探针记录。
    return MiuixPageTransition(
      animation: animation,
      label: route.settings.name ?? '${route.runtimeType}',
      configuredMs: route.transitionDuration.inMilliseconds,
      child: child,
    );
  }
}
