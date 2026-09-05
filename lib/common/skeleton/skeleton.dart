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

/// Returns the standard background color for skeleton blocks according to current theme.
Color skeletonBlockColor(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark
      ? cs.surfaceContainerHighest
      : cs.surfaceContainerHighest.withValues(alpha: 0.6);
}

/// Generic skeleton block placeholder.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
  });

  final double? width;
  final double? height;
  final BorderRadiusGeometry? borderRadius;
  final BoxShape shape;

  @override
  Widget build(BuildContext context) {
    final color = skeletonBlockColor(context);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius:
            shape == BoxShape.circle ? null : (borderRadius ?? BorderRadius.circular(4)),
        shape: shape,
      ),
    );
  }
}

/// Single-line skeleton text placeholder with configurable width and height.
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius,
  });

  final double? width;
  final double height;
  final BorderRadiusGeometry? borderRadius;

  @override
  Widget build(BuildContext context) {
    return SkeletonBox(
      width: width,
      height: height,
      borderRadius: borderRadius ?? BorderRadius.circular(height / 3),
    );
  }
}

/// Circular skeleton placeholder, e.g. for avatars.
class SkeletonCircle extends StatelessWidget {
  const SkeletonCircle({
    super.key,
    double? size,
    double? radius,
  }) : size = radius != null ? radius * 2 : (size ?? 40);

  final double size;

  @override
  Widget build(BuildContext context) {
    return SkeletonBox(
      width: size,
      height: size,
      shape: BoxShape.circle,
    );
  }
}
