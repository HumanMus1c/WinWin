import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter_miuix/miuix.dart' show MiuixMotion;
import 'package:material_ui/material_ui.dart';

/// Miuix 页面转场总开关（兜底回退用）。
///
/// 置 `false` 即回退到 material_ui 的平台默认转场（Windows 为
/// [ZoomPageTransitionsBuilder]），无需改动任何结构 —— app_theme 依此决定
/// 是否注册 [kMiuixPageTransitions]。
const bool kUseMiuixPageTransitions = true;

/// Miuix 页面转场时长（与替换前观感一致；如需更贴近 folme 节奏可调 350ms）。
const Duration kMiuixPageTransitionDuration = Duration(milliseconds: 300);

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

/// Miuix 页面转场（替代 material_ui 平台默认 Zoom 转场）。
///
/// 动效参数直接取自 flutter_miuix 的动效规范 [MiuixMotion]（源自
/// compose-miuix-ui 的 `anim/`）：出现用「标准缓出」、消失/让位用「标准缓入」。
/// flutter_miuix 1.3.0 自身不含页面转场组件，故按其规范落地本构建器。
///
/// 关键不变量（修复「进出页面时页面瞬间叠在沉浸标题条之上」的根因）：
/// **所有缩放 ≤ 1.0 且锚点为 [Alignment.topCenter]** —— 页面绘制范围恒不超出
/// 路由视口，结构上不可能再覆盖到标题条；同时顶边始终贴合内容区上缘，
/// 标题条正下方不会在转场期间出现缝隙或背景色环。
///
/// 说明：material_ui 默认 Zoom 转场的「旧页缩到 1.05 / 被弹出页涨到 1.10」
/// 会向视口外溢出（且 Flutter 不裁剪子节点绘制），是本次问题的直接来源。
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
    return _MiuixPageTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }
}

/// 转场动画核：新页「淡入 + 轻微放大」，被覆盖页「轻微缩小回退」。
class _MiuixPageTransition extends StatelessWidget {
  const _MiuixPageTransition({
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  /// 本路由自身的进场/退场动画。
  final Animation<double> animation;

  /// 被上层路由覆盖的动画（0=在最前，1=已被完全覆盖）。
  final Animation<double> secondaryAnimation;

  final Widget child;

  /// 缩放锚点：顶部居中（见 [MiuixPageTransitionsBuilder] 的不变量说明）。
  static const Alignment _anchor = Alignment.topCenter;

  /// 进场放大区间：0.94 → 1.0（≤ 1，不越界）。
  static final Animatable<double> _enterScale = Tween<double>(begin: 0.94, end: 1.0);

  /// 被覆盖回退区间：1.0 → 0.96（≤ 1，不越界）。
  static final Animatable<double> _coverScale = Tween<double>(begin: 1.0, end: 0.96);

  /// 不透明度：进场前 45% 完成淡入；退场在 pop 的前 45% 完成淡出。
  static final Animatable<double> _fade = Tween<double>(begin: 0.0, end: 1.0);

  @override
  Widget build(BuildContext context) {
    // 出现（进场 / 回归前台）用标准缓出，消失（退场 / 让位）用标准缓入。
    final enter = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.0, 0.45, curve: MiuixMotion.standardDecelerate),
      reverseCurve: const Interval(0.55, 1.0, curve: MiuixMotion.standardAccelerate),
    );
    final cover = CurvedAnimation(
      parent: secondaryAnimation,
      curve: MiuixMotion.standardAccelerate,
      reverseCurve: MiuixMotion.standardDecelerate,
    );

    Widget page = child;
    page = ScaleTransition(
      scale: cover.drive(_coverScale),
      alignment: _anchor,
      child: page,
    );
    page = FadeTransition(opacity: enter.drive(_fade), child: page);
    return ScaleTransition(
      scale: enter.drive(_enterScale),
      alignment: _anchor,
      child: page,
    );
  }
}
