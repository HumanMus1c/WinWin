import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart' show MiuixMotion;

/// 页面转场时长（AppRoute 与 Material 侧 MiuixPageTransitionsBuilder 共用）。
const Duration kMiuixTransitionDuration = Duration(milliseconds: 300);

/// Miuix 页面转场动画核（**零 Material 依赖**）。
///
/// 设计取向（2026-10-07 实机反馈优化：当前页不加特效 + 转场卡顿）：
///
/// 1. **只有新页有特效；被覆盖的当前页完全静止**——不给它加任何变换/透明度层。
///    旧实现给当前页加 `ScaleTransition 1.0→0.96`：当当前页是视频页（D3D11 外部
///    纹理）或含弹幕画布时，每帧都要对整页做缩放采样重合成，是转场掉帧的主要来源。
///    因此本核**不读取也不使用 `secondaryAnimation`**（勿再补回）。
/// 2. **新页只用「淡入 + 轻微上移」，不做缩放**——位移是纯平移变换，合成器只改图层
///    偏移；而缩放会让整页（含纹理/弹幕）按新比例反复重光栅化并引入过滤采样。
/// 3. 位移幅度 2%（约 16px@800 高）、淡入在进场前 40% 完成——缩短"双页混合"的
///    时间窗，降低填充率压力；两者都不产生视口外的绘制溢出（标题条不受影响）。
class MiuixPageTransition extends StatelessWidget {
  const MiuixPageTransition({
    super.key,
    required this.animation,
    required this.child,
  });

  /// 本路由自身的进场/退场动画（pop 时反向：新页退场、下层页静止显现）。
  final Animation<double> animation;

  final Widget child;

  /// 新页入场位移：自下方 2% 处滑入。
  static final Animatable<Offset> _enterSlide =
      Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero);

  /// 不透明度：进场前 40% 完成淡入；退场在 pop 的前 40% 完成淡出。
  static final Animatable<double> _fade = Tween<double>(begin: 0.0, end: 1.0);

  @override
  Widget build(BuildContext context) {
    // 出现（进场）用标准缓出，消失（退场）用标准缓入（MiuixMotion 规范）。
    final enter = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.0, 0.4, curve: MiuixMotion.standardDecelerate),
      reverseCurve:
          const Interval(0.6, 1.0, curve: MiuixMotion.standardAccelerate),
    );
    return FadeTransition(
      opacity: enter.drive(_fade),
      child: SlideTransition(
        position: enter.drive(_enterSlide),
        child: child,
      ),
    );
  }
}
