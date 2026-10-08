import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart' show MiuixMotion;

/// 页面转场时长（Miuix 交互节奏；AppRoute 与既有的
/// MiuixPageTransitionsBuilder 共用同一常量，保证替换前后观感一致）。
const Duration kMiuixTransitionDuration = Duration(milliseconds: 300);

/// Miuix 页面转场动画核（**零 Material 依赖**，供 AppRoute 与
/// Material 侧 PageTransitionsBuilder 双轨共用）。
///
/// 动效取自 flutter_miuix 的 [MiuixMotion] 规范：出现用「标准缓出」、
/// 消失/让位用「标准缓入」。
///
/// 关键不变量：**所有缩放 ≤ 1.0 且锚点为 [Alignment.topCenter]** —— 页面绘制
/// 范围恒不超出路由视口（结构上不会覆盖沉浸标题条），且顶边始终贴合内容区
/// 上缘，转场期间标题条正下方不出现缝隙/背景色环。
class MiuixPageTransition extends StatelessWidget {
  const MiuixPageTransition({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  /// 本路由自身的进场/退场动画。
  final Animation<double> animation;

  /// 被上层路由覆盖的动画（0=在最前，1=已被完全覆盖）。
  final Animation<double> secondaryAnimation;

  final Widget child;

  /// 缩放锚点：顶部居中（见类文档的不变量说明）。
  static const Alignment anchor = Alignment.topCenter;

  /// 进场放大区间：0.94 → 1.0（≤ 1，不越界）。
  static final Animatable<double> _enterScale =
      Tween<double>(begin: 0.94, end: 1.0);

  /// 被覆盖回退区间：1.0 → 0.96（≤ 1，不越界）。
  static final Animatable<double> _coverScale =
      Tween<double>(begin: 1.0, end: 0.96);

  /// 不透明度：进场前 45% 完成淡入；退场在 pop 的前 45% 完成淡出。
  static final Animatable<double> _fade = Tween<double>(begin: 0.0, end: 1.0);

  @override
  Widget build(BuildContext context) {
    // 出现（进场 / 回归前台）用标准缓出，消失（退场 / 让位）用标准缓入。
    final enter = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.0, 0.45, curve: MiuixMotion.standardDecelerate),
      reverseCurve:
          const Interval(0.55, 1.0, curve: MiuixMotion.standardAccelerate),
    );
    final cover = CurvedAnimation(
      parent: secondaryAnimation,
      curve: MiuixMotion.standardAccelerate,
      reverseCurve: MiuixMotion.standardDecelerate,
    );

    Widget page = child;
    page = ScaleTransition(
      scale: cover.drive(_coverScale),
      alignment: anchor,
      child: page,
    );
    page = FadeTransition(opacity: enter.drive(_fade), child: page);
    return ScaleTransition(
      scale: enter.drive(_enterScale),
      alignment: anchor,
      child: page,
    );
  }
}
