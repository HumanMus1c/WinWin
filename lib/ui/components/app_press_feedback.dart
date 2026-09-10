import 'package:flutter/material.dart';

/// 触控与鼠标按压下沉物理微动效（Sink 反馈）。
///
/// 移植自 BiliPai `MiuixPressFeedbackModifier.kt` 与 `AppMotionTokens.kt`：
/// - 按下时（pointer down）缩放到 [targetScale]（默认 0.96x），平滑下沉（Sink）；
/// - 释放时（pointer up/cancel）使用物理弹簧回弹曲线恢复 1.0x；
/// - 提供如同机械实体微动开关般扎实稳健的手感。
class AppPressFeedback extends StatefulWidget {
  const AppPressFeedback({
    super.key,
    required this.child,
    this.onTap,
    this.enabled = true,
    this.targetScale = 0.96,
    this.pressDuration = const Duration(milliseconds: 90),
    this.releaseDuration = const Duration(milliseconds: 200),
    this.curve = Curves.easeOutCubic,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;
  final double targetScale;
  final Duration pressDuration;
  final Duration releaseDuration;
  final Curve curve;

  @override
  State<AppPressFeedback> createState() => _AppPressFeedbackState();
}

class _AppPressFeedbackState extends State<AppPressFeedback>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.pressDuration,
      reverseDuration: widget.releaseDuration,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: widget.targetScale,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: widget.curve,
      reverseCurve: Curves.easeOutBack,
    ));
  }

  @override
  void didUpdateWidget(covariant AppPressFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetScale != widget.targetScale ||
        oldWidget.curve != widget.curve) {
      _scaleAnimation = Tween<double>(
        begin: 1.0,
        end: widget.targetScale,
      ).animate(CurvedAnimation(
        parent: _controller,
        curve: widget.curve,
        reverseCurve: Curves.easeOutBack,
      ));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails _) {
    if (widget.enabled) {
      _controller.forward();
    }
  }

  void _handleTapUp(TapUpDetails _) {
    if (widget.enabled) {
      _controller.reverse();
    }
  }

  void _handleTapCancel() {
    if (widget.enabled) {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) => Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}
