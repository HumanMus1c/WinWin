import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:flutter/widgets.dart';

/// 桌面级微交互装饰组件（自适应悬停高光与聚焦环）。
///
/// 移植自 BiliPai `AppDesktopInteraction.kt`：
/// - 鼠标悬浮时切换为手型光标 [SystemMouseCursors.click]；
/// - **跟随几何轮廓的悬停高光（Outline Hover Glow）**：在组件轮廓内绘制
///   6% alpha 的 [ColorScheme.onSurface] 悬停微光，完美契合组件圆角与边缘；
/// - **精准外缘聚焦环（Focus Ring）**：键盘 Tab 聚焦时，沿轮廓绘制 2.0dp 宽
///   的主色 [ColorScheme.primary] 框线，不挤占内部空间；
/// - 支持传入 [ShapeBorder] 或 [BorderRadius]，缺省默认为 12.0dp 圆角。
class AppDesktopInteraction extends StatefulWidget {
  const AppDesktopInteraction({
    super.key,
    required this.child,
    this.onTap,
    this.shape,
    this.borderRadius,
    this.focusNode,
    this.enabled = true,
    this.hoverAlpha = 0.06,
    this.focusBorderWidth = 2.0,
    this.cursor = SystemMouseCursors.click,
  });

  final Widget child;
  final VoidCallback? onTap;
  final ShapeBorder? shape;
  final BorderRadius? borderRadius;
  final FocusNode? focusNode;
  final bool enabled;
  final double hoverAlpha;
  final double focusBorderWidth;
  final MouseCursor cursor;

  @override
  State<AppDesktopInteraction> createState() => _AppDesktopInteractionState();
}

class _AppDesktopInteractionState extends State<AppDesktopInteraction> {
  bool _isHovered = false;
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final hoverColor = cs.onSurface.withValues(alpha: widget.hoverAlpha);
    final focusColor = cs.primary;

    final effectiveRadius = widget.borderRadius ?? BorderRadius.circular(12);

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (hasFocus) {
        if (_isFocused != hasFocus) {
          setState(() => _isFocused = hasFocus);
        }
      },
      child: MouseRegion(
        cursor: widget.enabled && widget.onTap != null
            ? widget.cursor
            : MouseCursor.defer,
        onEnter: (_) {
          if (!_isHovered) setState(() => _isHovered = true);
        },
        onExit: (_) {
          if (_isHovered) setState(() => _isHovered = false);
        },
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: CustomPaint(
            foregroundPainter: _DesktopInteractionPainter(
              shape: widget.shape,
              borderRadius: effectiveRadius,
              isHovered: _isHovered,
              isFocused: _isFocused,
              hoverColor: hoverColor,
              focusColor: focusColor,
              focusBorderWidth: widget.focusBorderWidth,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _DesktopInteractionPainter extends CustomPainter {
  _DesktopInteractionPainter({
    required this.shape,
    required this.borderRadius,
    required this.isHovered,
    required this.isFocused,
    required this.hoverColor,
    required this.focusColor,
    required this.focusBorderWidth,
  });

  final ShapeBorder? shape;
  final BorderRadius borderRadius;
  final bool isHovered;
  final bool isFocused;
  final Color hoverColor;
  final Color focusColor;
  final double focusBorderWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (!isHovered && !isFocused) return;
    final rect = Offset.zero & size;

    if (shape != null) {
      final path = shape!.getOuterPath(rect);
      if (isHovered) {
        final paint = Paint()
          ..color = hoverColor
          ..style = PaintingStyle.fill;
        canvas.drawPath(path, paint);
      }
      if (isFocused) {
        final paint = Paint()
          ..color = focusColor
          ..strokeWidth = focusBorderWidth
          ..style = PaintingStyle.stroke;
        canvas.drawPath(path, paint);
      }
    } else {
      final rrect = borderRadius.toRRect(rect);
      if (isHovered) {
        final paint = Paint()
          ..color = hoverColor
          ..style = PaintingStyle.fill;
        canvas.drawRRect(rrect, paint);
      }
      if (isFocused) {
        final paint = Paint()
          ..color = focusColor
          ..strokeWidth = focusBorderWidth
          ..style = PaintingStyle.stroke;
        canvas.drawRRect(rrect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DesktopInteractionPainter oldDelegate) {
    return oldDelegate.isHovered != isHovered ||
        oldDelegate.isFocused != isFocused ||
        oldDelegate.hoverColor != hoverColor ||
        oldDelegate.focusColor != focusColor ||
        oldDelegate.shape != shape ||
        oldDelegate.borderRadius != borderRadius;
  }
}
