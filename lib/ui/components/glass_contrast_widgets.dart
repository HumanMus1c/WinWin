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

/// 渐进式毛玻璃容器（Progressive Blur / Gradient Blur）。
///
/// 通过 [ShaderMask]（BlendMode.dstIn）与 [BackdropFilter] 的结合，使毛玻璃模糊层与暗色渐变
/// 从一边到另一边产生平滑连续的 Alpha 衰减，彻底消除传统 [BackdropFilter] 边缘生硬切断的视觉缺陷。
/// 前景 [child] 位于背景毛玻璃图层之上，不受渐隐遮罩影响，保持图标与文字的 100% 锐利高对比度。
class ProgressiveGlass extends StatelessWidget {
  const ProgressiveGlass({
    super.key,
    this.child,
    this.blur = 16.0,
    this.begin = Alignment.topCenter,
    this.end = Alignment.bottomCenter,
    this.stops,
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

  /// 最大模糊半径（sigma），默认 16.0。若 <= 0.01 则降级为纯渐变无模糊模式。
  final double blur;

  /// 模糊渐变起点（模糊度与暗度最强端，或依场景反向）。
  final AlignmentGeometry begin;

  /// 模糊渐变终点（模糊度与暗度衰减端）。
  final AlignmentGeometry end;

  /// 渐变断点分布。
  final List<double>? stops;

  /// 背景装饰色渐变色板。若不传，默认从 75% 黑色渐变到透明。
  final List<Color>? backgroundGradientColors;

  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final effectiveColors = backgroundGradientColors ??
        [
          Colors.black.withValues(alpha: 0.75),
          Colors.transparent,
        ];

    // 当 blur 近似为 0 时降级为普通渐变容器，完全绕过 BackdropFilter Offscreen 消耗
    if (blur <= 0.01) {
      final fallbackContainer = Container(
        width: width,
        height: height,
        margin: margin,
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          gradient: LinearGradient(
            begin: begin,
            end: end,
            stops: stops,
            colors: effectiveColors,
          ),
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

    // 渐进毛玻璃背景层：BackdropFilter 提供底层高斯模糊，
    // ShaderMask(BlendMode.dstIn) 依方向施加 Alpha 衰减遮罩，
    // 使得模糊强度在视觉上从一端平滑渐变消隐至另一端。
    Widget glassLayer = ShaderMask(
      shaderCallback: (Rect bounds) {
        return LinearGradient(
          begin: begin,
          end: end,
          stops: stops,
          colors: const [
            Colors.white,
            Colors.transparent,
          ],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: begin,
              end: end,
              stops: stops,
              colors: effectiveColors,
            ),
          ),
        ),
      ),
    );

    if (borderRadius != null) {
      glassLayer = ClipRRect(
        borderRadius: borderRadius!,
        clipBehavior: clipBehavior,
        child: glassLayer,
      );
    } else {
      glassLayer = ClipRect(
        clipBehavior: clipBehavior,
        child: glassLayer,
      );
    }

    if (child == null) {
      return Container(
        width: width,
        height: height,
        margin: margin,
        child: glassLayer,
      );
    }

    return Container(
      width: width,
      height: height,
      margin: margin,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(child: glassLayer),
          Padding(
            padding: padding ?? EdgeInsets.zero,
            child: child!,
          ),
        ],
      ),
    );
  }
}
