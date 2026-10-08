import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart' show MiuixMotion;

import 'package:winwin/core/perf/transition_probe.dart';

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
///
/// 另：本核同时驱动 [TransitionProbe]（转场用时 + 逐帧 build/raster 耗时），
/// 探针默认关闭（`Documents/logs/transition_probe.json`），关闭时零开销。
class MiuixPageTransition extends StatefulWidget {
  const MiuixPageTransition({
    super.key,
    required this.animation,
    required this.child,
    this.label,
    this.configuredMs,
  });

  /// 本路由自身的进场/退场动画（pop 时反向：新页退场、下层页静止显现）。
  final Animation<double> animation;

  final Widget child;

  /// 路由标签（探针用；通常取 `settings.name ?? runtimeType`）。
  final String? label;

  /// 路由配置的转场时长（毫秒，探针对照用）。
  final int? configuredMs;

  @override
  State<MiuixPageTransition> createState() => _MiuixPageTransitionState();
}

class _MiuixPageTransitionState extends State<MiuixPageTransition> {
  /// 新页入场位移：自下方 2% 处滑入。
  static final Animatable<Offset> _enterSlide =
      Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero);

  /// 不透明度：进场前 40% 完成淡入；退场在 pop 的前 40% 完成淡出。
  static final Animatable<double> _fade = Tween<double>(begin: 0.0, end: 1.0);

  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_onAnimationStatus);
    // 首帧即挂载时，"forward/reverse" 状态事件可能已经发出（路由 didPush 先于本
    // 组件构建），这里补一次当前状态，保证探针窗口不丢开窗。
    _onAnimationStatus(widget.animation.status);
  }

  @override
  void didUpdateWidget(MiuixPageTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation.removeStatusListener(_onAnimationStatus);
      widget.animation.addStatusListener(_onAnimationStatus);
      _onAnimationStatus(widget.animation.status);
    }
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_onAnimationStatus);
    super.dispose();
  }

  /// 转场生命周期 → 探针窗口（forward/reverse 开始，completed/dismissed 结束）。
  void _onAnimationStatus(AnimationStatus status) {
    switch (status) {
      case AnimationStatus.forward:
        TransitionProbe.instance.begin(
          widget.label ?? 'unknown',
          reverse: false,
          configuredMs: widget.configuredMs ?? 0,
          ticker: widget.animation,
        );
      case AnimationStatus.reverse:
        TransitionProbe.instance.begin(
          widget.label ?? 'unknown',
          reverse: true,
          configuredMs: widget.configuredMs ?? 0,
          ticker: widget.animation,
        );
      case AnimationStatus.completed:
      case AnimationStatus.dismissed:
        TransitionProbe.instance.end();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 出现（进场）用标准缓出，消失（退场）用标准缓入（MiuixMotion 规范）。
    final enter = CurvedAnimation(
      parent: widget.animation,
      curve: const Interval(0.0, 0.4, curve: MiuixMotion.standardDecelerate),
      reverseCurve:
          const Interval(0.6, 1.0, curve: MiuixMotion.standardAccelerate),
    );
    return FadeTransition(
      opacity: enter.drive(_fade),
      child: SlideTransition(
        position: enter.drive(_enterSlide),
        child: widget.child,
      ),
    );
  }
}
