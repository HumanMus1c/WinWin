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
