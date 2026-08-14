import 'package:flutter/material.dart';

/// 通用 hover 视觉容器（对标 BiliPai 所有可交互控件的 hover 效果）。
///
/// 鼠标悬停时显示半透明背景，提供视觉反馈。
/// 可包裹任何可交互控件（按钮、chip、图标等）。
class HoverContainer extends StatefulWidget {
  const HoverContainer({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius = 4.0,
    this.padding = EdgeInsets.zero,
    this.hoverColor,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final Color? hoverColor;
  final bool enabled;

  @override
  State<HoverContainer> createState() => _HoverContainerState();
}

class _HoverContainerState extends State<HoverContainer> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final theme = Theme.of(context);
    final hoverColor = widget.hoverColor ??
        theme.colorScheme.onSurface.withValues(alpha: 0.08);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: _isHovering ? hoverColor : Colors.transparent,
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
