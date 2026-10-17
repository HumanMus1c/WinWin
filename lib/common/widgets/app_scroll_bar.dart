import 'package:flutter/widgets.dart';
import 'package:winwin/core/shell/app_theme_host.dart';

/// 关闭**框架自动滚动条**的滚动行为。
///
/// Flutter SDK 的 `ScrollBehavior.buildScrollbar` 在桌面平台（windows/macos/linux）
/// 默认返回 `RawScrollbar` —— 即每个 `Scrollable` 都会自动挂一条框架滚动条，与项目
/// 自有的 [AppScrollBar] 叠加即形成「双滚动条」，且其位置取决于滚动视图（常被页内
/// padding 内缩）而非窗口边缘。
///
/// 本行为在 [AppScrollBar] 子树内返回 `child`，抑制框架条，只保留自有实现。
class _NoFrameworkScrollBar extends ScrollBehavior {
  const _NoFrameworkScrollBar();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child;
}

/// 项目自有滚动条（零 material、零 flutter_miuix 依赖，自绘 painter）。
///
/// 设计要点（对齐实机反馈）：
/// - **处于「内容区域」与「窗口边缘」之间**：为滚动条预留一条独立通道
///   （[_laneThickness] 12px），内容经 [Expanded] 让位、滚动条独占最外侧通道，
///   **永不覆盖内容**；
/// - **贴边**：通道内滑块右缘距通道右缘仅 [edgePadding] 1px；
/// - **状态分档（加粗 + 加深 + 提高不透明度）**：
///   idle 5px / alpha 0.35 → hover 或滚动中 9px / alpha 0.68 → 拖拽 11px / alpha 0.92
///   且拖拽态颜色向黑色加深（`Color.lerp`）；
/// - **hover 只作用于滑轨**：仅在通道上挂 [MouseRegion]，鼠标进入滑轨带才强化；
/// - 支持**拖拽滑块**（`GestureDetector` 拖动 + 点击跳转）与滚轮/拖动滚动时的视觉反馈。
class AppScrollBar extends StatefulWidget {
  const AppScrollBar({
    super.key,
    required this.controller,
    required this.child,
    this.axis = Axis.vertical,
  });

  /// 目标滚动视图的控制器（必须有 clients 才会绘制）。
  final ScrollController controller;

  /// 被包裹的内容区。
  final Widget child;

  /// 滚动条方向，默认竖向。
  final Axis axis;

  /// 滚动条独立通道厚度（同时是 hover 触发带宽度、拖拽滑块上限）。
  static const double laneThickness = 12;

  /// 滑块距通道边缘的间距。
  static const double edgePadding = 1;

  /// idle 态滑块厚度。
  static const double idleThickness = 5;

  /// hover / 滚动中滑块厚度。
  static const double hoverThickness = 9;

  /// 拖拽态滑块厚度。
  static const double activeThickness = 11;

  /// 滑块最小长度。
  static const double minThumbLength = 36;

  @override
  State<AppScrollBar> createState() => _AppScrollBarState();
}

class _AppScrollBarState extends State<AppScrollBar> {
  bool _hovered = false;
  bool _dragging = false;
  bool _scrolling = false;

  /// 拖拽时手指在滑块内的偏移量。
  double _grabOffset = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScrollChanged);
  }

  @override
  void didUpdateWidget(covariant AppScrollBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onScrollChanged);
      widget.controller.addListener(_onScrollChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScrollChanged);
    super.dispose();
  }

  void _onScrollChanged() {
    if (!mounted || !widget.controller.hasClients) return;
    final active = widget.controller.position.isScrollingNotifier.value;
    if (active != _scrolling) setState(() => _scrolling = active);
  }

  ScrollPosition? get _position =>
      widget.controller.hasClients ? widget.controller.position : null;

  double _thumbLength(double trackExtent, ScrollPosition p) {
    final content = p.maxScrollExtent + p.viewportDimension;
    if (content <= 0) return trackExtent;
    final fraction = p.viewportDimension / content;
    return (trackExtent * fraction).clamp(AppScrollBar.minThumbLength, trackExtent);
  }

  double _thumbOffset(double trackExtent, ScrollPosition p, double thumbLength) {
    final maxThumbTravel = trackExtent - thumbLength;
    if (maxThumbTravel <= 0 || p.maxScrollExtent <= 0) return 0;
    return (p.pixels / p.maxScrollExtent).clamp(0.0, 1.0) * maxThumbTravel;
  }

  void _jumpTo(double thumbOffset, double trackExtent, ScrollPosition p) {
    final thumbLength = _thumbLength(trackExtent, p);
    final maxThumbTravel = trackExtent - thumbLength;
    if (maxThumbTravel <= 0) return;
    final ratio = (thumbOffset / maxThumbTravel).clamp(0.0, 1.0);
    p.jumpTo(ratio * p.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = AppThemeHost.of(context).colors.onSurface;
    final vertical = widget.axis == Axis.vertical;

    final lane = MouseRegion(
      opaque: false,
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trackExtent = vertical ? constraints.maxHeight : constraints.maxWidth;
          final position = _position;
          final canScroll = position != null && position.maxScrollExtent > 0;

          final thumbLength = canScroll
              ? _thumbLength(trackExtent, position)
              : trackExtent;
          final thumbOffset =
              canScroll ? _thumbOffset(trackExtent, position, thumbLength) : 0.0;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: vertical && canScroll
                ? (d) => _dragStart(d.localPosition.dy, trackExtent, position)
                : null,
            onVerticalDragUpdate: vertical && canScroll
                ? (d) => _jumpTo(d.localPosition.dy - _grabOffset, trackExtent, position)
                : null,
            onVerticalDragEnd: vertical ? (_) => _dragEnd() : null,
            onHorizontalDragStart: !vertical && canScroll
                ? (d) => _dragStart(d.localPosition.dx, trackExtent, position)
                : null,
            onHorizontalDragUpdate: !vertical && canScroll
                ? (d) => _jumpTo(d.localPosition.dx - _grabOffset, trackExtent, position)
                : null,
            onHorizontalDragEnd: !vertical ? (_) => _dragEnd() : null,
            child: AnimatedBuilder(
              animation: widget.controller,
              builder: (context, _) {
                return CustomPaint(
                  size: Size.infinite,
                  painter: _ScrollBarPainter(
                    vertical: vertical,
                    onSurface: onSurface,
                    canScroll: canScroll,
                    thumbOffset: thumbOffset,
                    thumbLength: thumbLength,
                    thickness: _dragging
                        ? AppScrollBar.activeThickness
                        : (_hovered || _scrolling
                            ? AppScrollBar.hoverThickness
                            : AppScrollBar.idleThickness),
                    alpha: _dragging
                        ? 0.92
                        : (_hovered || _scrolling ? 0.68 : 0.35),
                    deepen: _dragging,
                    showTrack: _hovered || _dragging,
                  ),
                );
              },
            ),
          );
        },
      ),
    );

    // 为滚动条预留独立通道：内容经 Expanded 让位，滚动条独占最外侧通道。
    // 并在子树内关闭框架自动滚动条（SDK 桌面默认给每个 Scrollable 挂 RawScrollbar，
    // 与本滚动条叠加会成为「双滚动条」）。
    final laneBox = vertical
        ? SizedBox(width: AppScrollBar.laneThickness, child: lane)
        : SizedBox(height: AppScrollBar.laneThickness, child: lane);

    return ScrollConfiguration(
      behavior: const _NoFrameworkScrollBar(),
      child: vertical
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [Expanded(child: widget.child), laneBox],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [Expanded(child: widget.child), laneBox],
            ),
    );
  }

  void _dragStart(double localOffset, double trackExtent, ScrollPosition p) {
    final thumbLength = _thumbLength(trackExtent, p);
    final thumbOffset = _thumbOffset(trackExtent, p, thumbLength);
    if (localOffset >= thumbOffset && localOffset <= thumbOffset + thumbLength) {
      _grabOffset = localOffset - thumbOffset;
    } else {
      // 点击轨道空白：滑块中心跳到点击处。
      _grabOffset = thumbLength / 2;
      _jumpTo(localOffset - _grabOffset, trackExtent, p);
    }
    setState(() => _dragging = true);
  }

  void _dragEnd() {
    if (_dragging) setState(() => _dragging = false);
  }
}

/// 自绘滚动条：轨道（可选）+ 滑块，右/下对齐并按状态加粗、加深、提高不透明度。
class _ScrollBarPainter extends CustomPainter {
  const _ScrollBarPainter({
    required this.vertical,
    required this.onSurface,
    required this.canScroll,
    required this.thumbOffset,
    required this.thumbLength,
    required this.thickness,
    required this.alpha,
    required this.deepen,
    required this.showTrack,
  });

  final bool vertical;
  final Color onSurface;
  final bool canScroll;
  final double thumbOffset;
  final double thumbLength;
  final double thickness;
  final double alpha;
  final bool deepen;
  final bool showTrack;

  @override
  void paint(Canvas canvas, Size size) {
    if (!canScroll) return;

    final base = deepen ? Color.lerp(onSurface, const Color(0xFF000000), 0.25)! : onSurface;
    final thumbColor = base.withValues(alpha: alpha);
    final pad = AppScrollBar.edgePadding;

    if (vertical) {
      if (showTrack) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(size.width - thickness - pad, 0, thickness, size.height),
            Radius.circular(thickness / 2),
          ),
          Paint()..color = onSurface.withValues(alpha: 0.10),
        );
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
              size.width - thickness - pad, thumbOffset, thickness, thumbLength),
          Radius.circular(thickness / 2),
        ),
        Paint()..color = thumbColor,
      );
    } else {
      if (showTrack) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(0, size.height - thickness - pad, size.width, thickness),
            Radius.circular(thickness / 2),
          ),
          Paint()..color = onSurface.withValues(alpha: 0.10),
        );
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
              thumbOffset, size.height - thickness - pad, thumbLength, thickness),
          Radius.circular(thickness / 2),
        ),
        Paint()..color = thumbColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScrollBarPainter old) =>
      old.thumbOffset != thumbOffset ||
      old.thumbLength != thumbLength ||
      old.thickness != thickness ||
      old.alpha != alpha ||
      old.deepen != deepen ||
      old.showTrack != showTrack ||
      old.canScroll != canScroll ||
      old.onSurface != onSurface;
}