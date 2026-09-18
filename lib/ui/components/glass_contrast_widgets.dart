import 'dart:ui';
import 'package:flutter/material.dart';

/// 高对比度阴影与排版视觉常量规范。
class ContrastStyle {
  const ContrastStyle._();

  /// 标准多向锐利微距阴影（四向覆盖，防止浅色/白底场景字形吞没）。
  static const List<Shadow> glyphShadows = [
    Shadow(offset: Offset(0, 1.0), blurRadius: 3.0, color: Color(0xCC000000)),
    Shadow(offset: Offset(0, -0.5), blurRadius: 2.0, color: Color(0x99000000)),
    Shadow(offset: Offset(1.0, 0), blurRadius: 2.0, color: Color(0x80000000)),
    Shadow(offset: Offset(-1.0, 0), blurRadius: 2.0, color: Color(0x80000000)),
  ];

  /// 强调型粗体/大尺寸阴影（用于屏幕中央大尺寸反馈图标与重点提示）。
  static const List<Shadow> boldGlyphShadows = [
    Shadow(offset: Offset(0, 1.5), blurRadius: 4.0, color: Color(0xE6000000)),
    Shadow(offset: Offset(0, -1.0), blurRadius: 3.0, color: Color(0xB3000000)),
    Shadow(offset: Offset(1.5, 0), blurRadius: 3.0, color: Color(0x99000000)),
    Shadow(offset: Offset(-1.5, 0), blurRadius: 3.0, color: Color(0x99000000)),
  ];

  /// 默认高对比度文字样式。
  static const TextStyle labelStyle = TextStyle(
    color: Colors.white,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    shadows: glyphShadows,
  );
}

/// 亚克力毛玻璃悬浮胶囊容器（BackdropFilter 消除背景高频细节 + 半透明暗底微边框）。
class GlassCapsule extends StatelessWidget {
  const GlassCapsule({
    super.key,
    required this.child,
    this.borderRadius = 8.0,
    this.padding,
    this.margin,
    this.blur = 12.0,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 0.5,
    this.shape = BoxShape.rectangle,
    this.width,
    this.height,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double blur;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderWidth;
  final BoxShape shape;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final effectiveBg = backgroundColor ?? Colors.black.withValues(alpha: 0.35);
    final effectiveBorderColor =
        borderColor ?? Colors.white.withValues(alpha: 0.15);

    final isCircle = shape == BoxShape.circle;
    final r = isCircle ? BorderRadius.zero : BorderRadius.circular(borderRadius);

    Widget container = Container(
      width: width,
      height: height,
      padding: padding,
      margin: margin,
      decoration: BoxDecoration(
        color: effectiveBg,
        shape: shape,
        borderRadius: isCircle ? null : r,
        border: Border.all(
          color: effectiveBorderColor,
          width: borderWidth,
        ),
      ),
      child: child,
    );

    // 当 blur > 0 时挂载 BackdropFilter 消除背景高频噪点
    if (blur > 0) {
      container = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: container,
      );
    }

    if (isCircle) {
      return ClipOval(child: container);
    }
    return ClipRRect(borderRadius: r, child: container);
  }
}

/// 自带全向高对比度防吞没阴影的 Icon 组件。
class ContrastIcon extends StatelessWidget {
  const ContrastIcon(
    this.icon, {
    super.key,
    this.size,
    this.color = Colors.white,
    this.shadows = ContrastStyle.glyphShadows,
    this.semanticLabel,
  });

  final IconData icon;
  final double? size;
  final Color color;
  final List<Shadow>? shadows;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Icon(
      icon,
      size: size,
      color: color,
      shadows: shadows,
      semanticLabel: semanticLabel,
    );
  }
}

/// 自带全向高对比度防吞没阴影的 Text 组件。
class ContrastText extends StatelessWidget {
  const ContrastText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.shadows = ContrastStyle.glyphShadows,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final List<Shadow>? shadows;

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = (style ?? ContrastStyle.labelStyle).copyWith(
      shadows: shadows ?? (style?.shadows ?? ContrastStyle.glyphShadows),
    );

    return Text(
      text,
      style: effectiveStyle,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

/// 播放器高质感毛玻璃交互按钮。
class GlassControlButton extends StatefulWidget {
  const GlassControlButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 20,
    this.iconColor = Colors.white,
    this.useGlass = false,
    this.borderRadius = 6.0,
    this.padding = const EdgeInsets.all(6.0),
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final Color iconColor;
  final bool useGlass;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  @override
  State<GlassControlButton> createState() => _GlassControlButtonState();
}

class _GlassControlButtonState extends State<GlassControlButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final iconWidget = ContrastIcon(
      widget.icon,
      size: widget.size,
      color: widget.iconColor,
      shadows: ContrastStyle.glyphShadows,
    );

    Widget content;
    if (widget.useGlass) {
      content = GlassCapsule(
        borderRadius: widget.borderRadius,
        padding: widget.padding,
        backgroundColor: _hovered
            ? Colors.white.withValues(alpha: 0.22)
            : Colors.black.withValues(alpha: 0.35),
        child: iconWidget,
      );
    } else {
      content = Container(
        padding: widget.padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          color: _hovered ? Colors.white.withValues(alpha: 0.14) : Colors.transparent,
        ),
        child: iconWidget,
      );
    }

    final button = MouseRegion(
      cursor: widget.onPressed != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        behavior: HitTestBehavior.opaque,
        child: content,
      ),
    );

    if (widget.tooltip != null && widget.tooltip!.isNotEmpty) {
      return Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}

/// 渐进模糊方向。
enum GradientBlurDirection {
  topToBottom,
  bottomToTop,
  leftToRight,
  rightToLeft,
}

/// 渐进式毛玻璃容器（Progressive Blur / Gradient Blur）。
///
/// 采用成熟的切片渐进式高斯模糊架构（Sliced Gradient Blur）：
/// 将模糊区域沿渐变方向切分为多段（[slices]），每段独立进行阶梯式平滑插值采样，
/// 避免使用 [ShaderMask] 导致底层离屏缓冲擦除背景视频采样像素（Compositor failure），
/// 确保在 Windows Desktop / Skia / Impeller 全平台上均能稳定呈现真实的渐进式毛玻璃质感。
class ProgressiveGlass extends StatelessWidget {
  const ProgressiveGlass({
    super.key,
    this.child,
    this.blur = 10.0,
    this.maxBlur,
    this.minBlur = 0.0,
    this.slices = 4,
    this.direction,
    this.curve = Curves.linear,
    this.begin = Alignment.topCenter,
    this.end = Alignment.bottomCenter,
    this.stops,
    this.backgroundGradient,
    this.backgroundGradientColors,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius,
    this.clipBehavior = Clip.antiAlias,
  });

  /// 前景内容（按钮行、标题等）。如果为 null，则作为纯背景毛玻璃遮罩使用。
  final Widget? child;

  /// 最大模糊半径（sigma），默认 10.0。若 <= 0.01 则降级为纯渐变无模糊模式。
  final double blur;

  /// 可选显式指定最大模糊半径，优先级高于 [blur]。
  final double? maxBlur;

  /// 最小模糊半径（默认 0.0）。
  final double minBlur;

  /// 切片分段数，默认 4 段。在 40~80px 高度的控制栏与顶栏中，
  /// 4 段切片配合线性渐变遮罩在视觉上极为平滑自然（无肉眼可见断层），
  /// 同时将 GPU BackdropFilter 实例与着色器 Pass 数量降低约 75%，兼顾极高渲染性能。
  final int slices;

  /// 模糊递减方向。若未指定，则根据 [begin] 和 [end] 智能推导。
  final GradientBlurDirection? direction;

  /// 模糊过渡曲线。
  final Curve curve;

  /// 渐变起点（模糊与暗色最深端，默认顶部居中）。
  final AlignmentGeometry begin;

  /// 渐变终点（模糊与暗色消隐端，默认底部居中）。
  final AlignmentGeometry end;

  /// 渐变断点分布。
  final List<double>? stops;

  /// 显式传入的背景渐变。
  final Gradient? backgroundGradient;

  /// 背景装饰色渐变色板。若不传，默认从 75% 黑色渐变到透明。
  final List<Color>? backgroundGradientColors;

  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final Clip clipBehavior;

  GradientBlurDirection _resolveDirection() {
    if (direction != null) return direction!;
    if (begin is Alignment && end is Alignment) {
      final b = begin as Alignment;
      final e = end as Alignment;
      if (b.y > e.y) return GradientBlurDirection.bottomToTop;
      if (b.y < e.y) return GradientBlurDirection.topToBottom;
      if (b.x > e.x) return GradientBlurDirection.rightToLeft;
      if (b.x < e.x) return GradientBlurDirection.leftToRight;
    }
    return GradientBlurDirection.topToBottom;
  }

  Gradient _resolveGradient() {
    if (backgroundGradient != null) return backgroundGradient!;
    final colors = backgroundGradientColors ??
        [
          Colors.black.withValues(alpha: 0.75),
          Colors.transparent,
        ];
    return LinearGradient(
      begin: begin,
      end: end,
      stops: stops,
      colors: colors,
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveMaxBlur = maxBlur ?? blur;
    final effectiveGradient = _resolveGradient();

    // 当 blur 近似为 0 时降级为普通渐变容器，完全绕过 BackdropFilter
    if (effectiveMaxBlur <= 0.01) {
      final fallbackContainer = Container(
        width: width,
        height: height,
        margin: margin,
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          gradient: effectiveGradient,
        ),
        child: child,
      );
      if (borderRadius != null) {
        return ClipRRect(
          borderRadius: borderRadius!,
          clipBehavior: clipBehavior,
          child: fallbackContainer,
        );
      }
      return fallbackContainer;
    }

    final effectiveDir = _resolveDirection();
    final isVertical = effectiveDir == GradientBlurDirection.topToBottom ||
        effectiveDir == GradientBlurDirection.bottomToTop;
    final isReversed = effectiveDir == GradientBlurDirection.bottomToTop ||
        effectiveDir == GradientBlurDirection.rightToLeft;

    final count = slices.clamp(2, 32);
    final blurSlices = <Widget>[];

    for (int i = 0; i < count; i++) {
      final t = (count > 1) ? i / (count - 1) : 0.0;
      final curvedT = curve.transform(t);
      // isReversed 为 true 时（如 bottomToTop），顶部(i=0)为 minBlur(0)，底部(i=count-1)为 maxBlur(16)
      final double blurAmount = lerpDouble(
        isReversed ? minBlur : effectiveMaxBlur,
        isReversed ? effectiveMaxBlur : minBlur,
        curvedT,
      )!;

      if (blurAmount <= 0.05) {
        blurSlices.add(const Expanded(child: SizedBox.expand()));
      } else {
        blurSlices.add(
          Expanded(
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: blurAmount,
                  sigmaY: blurAmount,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
      }
    }

    Widget blurStack = RepaintBoundary(
      child: Flex(
        direction: isVertical ? Axis.vertical : Axis.horizontal,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: blurSlices,
      ),
    );

    Widget content = Stack(
      fit: StackFit.passthrough,
      children: [
        // 1. 分片真实渐进式毛玻璃层（直接采样底层视频画面）
        Positioned.fill(child: blurStack),
        // 2. 渐变半透明暗色蒙版（确保对比度与视觉融合）
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(gradient: effectiveGradient),
          ),
        ),
        // 3. 前景组件（控制按钮、文字，不受滤镜影响）
        if (child != null)
          Padding(
            padding: padding ?? EdgeInsets.zero,
            child: child!,
          ),
      ],
    );

    if (borderRadius != null) {
      content = ClipRRect(
        borderRadius: borderRadius!,
        clipBehavior: clipBehavior,
        child: content,
      );
    } else {
      content = ClipRect(
        clipBehavior: clipBehavior,
        child: content,
      );
    }

    return Container(
      width: width,
      height: height,
      margin: margin,
      child: content,
    );
  }
}

