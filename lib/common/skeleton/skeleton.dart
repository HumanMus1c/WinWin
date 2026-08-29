import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Wraps [child] with a repeating shimmer/sweep animation, commonly used as
/// the loading state for list cards.
class Skeleton extends StatefulWidget {
  final Widget child;

  const Skeleton({super.key, required this.child});

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final _matrix = Matrix4.identity();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(vsync: this)
      ..repeat(
        min: -0.5,
        max: 1.5,
        period: const Duration(milliseconds: 1000),
      );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final shimmerColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.white.withValues(alpha: 0.75);
    final colors = [
      Colors.transparent,
      shimmerColor,
      shimmerColor,
      Colors.transparent,
    ];
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (Rect bounds) {
            final width = bounds.width;
            final height = bounds.height;
            _matrix[12] = width * _controller.value;
            return ui.Gradient.linear(
              Offset(0, 0.35 * height),
              Offset(width, 0.95 * height),
              colors,
              const [0.1, 0.3, 0.5, 0.7],
              TileMode.clamp,
              _matrix.storage,
            );
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
