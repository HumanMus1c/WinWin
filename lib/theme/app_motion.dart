import 'package:flutter/animation.dart';
import 'package:flutter_miuix/miuix.dart'
    show MiuixSpringDefaults, MiuixSpringEngine;

/// Miuix「非线性动画」曲线适配器 —— 把 Miuix 的弹簧物理动效喂给 Flutter 隐式动画。
///
/// ## 概念
///
/// Miuix/HyperOS 的「非线性动画」本体是 **弹簧物理动效**（folmeSpring：临界阻尼
/// × 自然周期，见 [MiuixSpringDefaults]），而非多项式缓动曲线。它的位移由
/// [MiuixSpringEngine] 逐帧解算：起手快、长尾收敛，观感比 `Curves.*` /
/// [MiuixMotionEasing] 更「活」。
///
/// ## 为何要这层适配
///
/// Flutter 的隐式动画（`AnimatedSize` / `AnimatedPositioned` /
/// `TweenAnimationBuilder` …）只接受 [Curve]，不接受 `SpringDescription`，
/// 也没有「弹簧曲线」内置实现。本类用 **Miuix 自己的弹簧引擎**离屏跑一遍
/// 0→1 的落定过程并采样成归一化曲线：既不改写调用点的 widget 结构
/// （drop-in），也不自造任何新物理公式（物理仍是 Miuix 的）。
class MiuixSpringCurve extends Curve {
  const MiuixSpringCurve._();

  /// 设计语言令牌单例（与 `Style` / `AppColors` 同层，放 [lib/theme]）。
  static final MiuixSpringCurve standard = MiuixSpringCurve._();

  /// 采样步长 = 引擎单帧最大步长（引擎内部也会把 dt 夹到该值）。
  static const double _dt = MiuixSpringDefaults.maxFrameDeltaSeconds;

  /// 采样量程用「像素级」[1000] 而非归一化 1：引擎的落定判据是「距目标 < 1」，
  /// 若量程就是 0..1，首帧位移一旦为正即满足 |x−1|<1 而被误判落定
  /// （1 单位 = 100%，<1 就停）。放到 1000 后判据等价于「收敛到 99.9%」。
  static const double _scale = 1000;

  /// 上限保护：正常约 40 帧落定，600 帧足够，绝不无限循环。
  static const int _maxSteps = 600;

  /// 弹簧进度采样表：首元素 0、末元素 1。
  static final List<double> _samples = _buildSamples();

  static List<double> _buildSamples() {
    final engine = MiuixSpringEngine();
    engine.start(startValue: 0, targetValue: _scale, initialVelocity: 0);
    final samples = <double>[0];
    for (var i = 0; i < _maxSteps; i++) {
      if (engine.step(_dt)) break;
      samples.add(engine.currentPosition / _scale);
    }
    // 末端补齐到精确 1：隐式动画在 `t == 1` 时必须拿到终值，否则差最后一点。
    samples.add(1);
    return samples;
  }

  @override
  double transformInternal(double t) {
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    final pos = t * (_samples.length - 1);
    final i = pos.floor();
    final frac = pos - i;
    final a = _samples[i];
    final b = _samples[i + 1];
    return a + (b - a) * frac;
  }
}