import 'dart:async' show Timer;

import 'package:flutter/gestures.dart' show DragStartBehavior;
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
/// 布局：为滚动条**预留独立通道**（[_laneThickness] 12px），内容经 `Expanded` 让位，
/// 滚动条独占最外侧通道 ⇒ 处于「内容区域」与「窗口边缘」**之间**、永不覆盖内容；
/// 通道内滑块外缘距窗口边缘仅 [_edgePadding] 1px。
///
/// 交互状态机（`0 空闲 / 1 hover 或滚动中 / 2 拖拽`）：
/// - 由 `ScrollNotification`（仅 `depth == 0`）驱动「滚动中」，停止后 [_idleDelayMs]
///   防抖回落空闲态（避免惯性滚动期间闪烁）；
/// - 拖拽用 [DragStartBehavior.down] 起步（无 slop 迟滞 ⇒ 跟手）、按下即跟随；
/// - 三态之间由单一 [AnimationController] 做**补间**（[_transitionMs]），
///   滑块厚度/不透明度连续插值，不再是硬跳；
/// - 重绘仅作用于滚动条自身（[RepaintBoundary] + 只监听 controller/动画），
///   拖动期间**不触发 setState**，避免整页重建造成卡顿。
class AppScrollBar extends StatefulWidget {
  const AppScrollBar({
    super.key,
    required this.controller,
    required this.child,
    this.axis = Axis.vertical,
  });

  /// 目标滚动视图的控制器（须有 clients 才会绘制）。
  final ScrollController controller;

  /// 被包裹的内容区。
  final Widget child;

  /// 滚动条方向，默认竖向。
  final Axis axis;

  /// 滚动条独立通道厚度（同时是 hover 触发带宽度）。
  static const double laneThickness = 12;

  /// 滑块距通道边缘的间距。
  static const double edgePadding = 1;

  /// 空闲态滑块厚度。
  static const double idleThickness = 5;

  /// hover / 滚动中滑块厚度。
  static const double hoverThickness = 9;

  /// 拖拽态滑块厚度。
  static const double activeThickness = 11;

  /// 滑块最小长度。
  static const double minThumbLength = 40;

  /// 三态补间时长。
  static const int transitionMs = 170;

  /// 滚动结束后回落空闲态的防抖时长。
  static const int idleDelayMs = 700;

  @override
  State<AppScrollBar> createState() => _AppScrollBarState();
}

class _AppScrollBarState extends State<AppScrollBar>
    with SingleTickerProviderStateMixin {
  /// 强调度：0 = 空闲，1 = hover / 滚动中，2 = 拖拽（由动画平滑逼近）。
  late final AnimationController _emphasis = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: AppScrollBar.transitionMs),
    upperBound: 2,
  );

  bool _hovered = false;
  bool _dragging = false;
  bool _scrollActive = false;
  Timer? _idleTimer;

  /// 拖拽时指针在滑块内的偏移量（保证跟手）。
  double _grabOffset = 0;

  @override
  void dispose() {
    _idleTimer?.cancel();
    _emphasis.dispose();
    super.dispose();
  }

  double get _targetEmphasis {
    if (_dragging) return 2;
    if (_hovered || _scrollActive) return 1;
    return 0;
  }

  void _animateToTarget() {
    _emphasis.animateTo(
      _targetEmphasis,
      duration: const Duration(milliseconds: AppScrollBar.transitionMs),
      curve: Curves.easeOut,
    );
  }

  // ── 滚动中态：由 ScrollNotification 驱动（depth == 0 才属于本滚动视图）──

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification ||
        notification is ScrollUpdateNotification) {
      _idleTimer?.cancel();
      _idleTimer = null;
      if (!_scrollActive) {
        _scrollActive = true;
        _animateToTarget();
      }
    } else if (notification is ScrollEndNotification) {
      _idleTimer?.cancel();
      _idleTimer = Timer(
        const Duration(milliseconds: AppScrollBar.idleDelayMs),
        () {
          if (!mounted) return;
          _scrollActive = false;
          _animateToTarget();
        },
      );
    }
    return false;
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

  void _jumpToThumbOffset(
      double thumbOffset, double trackExtent, ScrollPosition p) {
    final thumbLength = _thumbLength(trackExtent, p);
    final maxThumbTravel = trackExtent - thumbLength;
    if (maxThumbTravel <= 0) return;
    final ratio = (thumbOffset / maxThumbTravel).clamp(0.0, 1.0);
    p.jumpTo(ratio * p.maxScrollExtent);
  }

  void _dragStart(double localOffset, double trackExtent, ScrollPosition p) {
    final thumbLength = _thumbLength(trackExtent, p);
    final thumbOffset = _thumbOffset(trackExtent, p, thumbLength);
    if (localOffset >= thumbOffset && localOffset <= thumbOffset + thumbLength) {
      _grabOffset = localOffset - thumbOffset;
    } else {
      // 点击轨道空白：滑块中心跳到点击处，再继续跟随。
      _grabOffset = thumbLength / 2;
      _jumpToThumbOffset(localOffset - _grabOffset, trackExtent, p);
    }
    _dragging = true;
    _idleTimer?.cancel();
    _idleTimer = null;
    _animateToTarget();
  }

  void _dragEnd() {
    if (!_dragging) return;
    _dragging = false;
    _animateToTarget();
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  Widget build(BuildContext context) {
    final onSurface = AppThemeHost.of(context).colors.onSurface;
    final vertical = widget.axis == Axis.vertical;

    final lane = MouseRegion(
      opaque: false,
      cursor: SystemMouseCursors.basic,
      onEnter: (_) {
        _hovered = true;
        _animateToTarget();
      },
      onExit: (_) {
        _hovered = false;
        _animateToTarget();
      },
      child: LayoutBuilder(
          builder: (context, constraints) {
            final trackExtent =
                vertical ? constraints.maxHeight : constraints.maxWidth;

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              dragStartBehavior: DragStartBehavior.down,
              onVerticalDragStart: vertical
                  ? (d) {
                      final p = _position;
                      if (p == null || p.maxScrollExtent <= 0) return;
                      _dragStart(d.localPosition.dy, trackExtent, p);
                    }
                  : null,
              onVerticalDragUpdate: vertical
                  ? (d) {
                      final p = _position;
                      if (!_dragging || p == null) return;
                      _jumpToThumbOffset(
                          d.localPosition.dy - _grabOffset, trackExtent, p);
                    }
                  : null,
              onVerticalDragEnd: vertical ? (_) => _dragEnd() : null,
              onVerticalDragCancel: vertical ? _dragEnd : null,
              onHorizontalDragStart: !vertical
                  ? (d) {
                      final p = _position;
                      if (p == null || p.maxScrollExtent <= 0) return;
                      _dragStart(d.localPosition.dx, trackExtent, p);
                    }
                  : null,
              onHorizontalDragUpdate: !vertical
                  ? (d) {
                      final p = _position;
                      if (!_dragging || p == null) return;
                      _jumpToThumbOffset(
                          d.localPosition.dx - _grabOffset, trackExtent, p);
                    }
                  : null,
              onHorizontalDragEnd: !vertical ? (_) => _dragEnd() : null,
              onHorizontalDragCancel: !vertical ? _dragEnd : null,
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: Listenable.merge([widget.controller, _emphasis]),
                  builder: (context, _) {
                    final e = _emphasis.value;
                    final position = _position;
                    final canScroll =
                        position != null && position.maxScrollExtent > 0;
                    final thumbLength = canScroll
                        ? _thumbLength(trackExtent, position)
                        : trackExtent;
                    final thumbOffset = canScroll
                        ? _thumbOffset(trackExtent, position, thumbLength)
                        : 0.0;

                    // 三态连续插值：0→1 加粗/加深，1→2 再进一步。
                    final double thickness;
                    final double alpha;
                    if (e <= 1) {
                      thickness = _lerp(AppScrollBar.idleThickness,
                          AppScrollBar.hoverThickness, e);
                      alpha = _lerp(0.35, 0.68, e);
                    } else {
                      thickness = _lerp(AppScrollBar.hoverThickness,
                          AppScrollBar.activeThickness, e - 1);
                      alpha = _lerp(0.68, 0.92, e - 1);
                    }

                    return CustomPaint(
                      size: Size.infinite,
                      painter: _ScrollBarPainter(
                        vertical: vertical,
                        onSurface: onSurface,
                        canScroll: canScroll,
                        thumbOffset: thumbOffset,
                        thumbLength: thumbLength,
                        thickness: thickness,
                        alpha: alpha,
                        deepen: e > 1.2,
                        showTrack: e > 0.15,
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
    );

    final laneBox = vertical
        ? SizedBox(width: AppScrollBar.laneThickness, child: lane)
        : SizedBox(height: AppScrollBar.laneThickness, child: lane);

    // 通道 + 内容；整个子树关闭框架自动滚动条（SDK 桌面默认给每个 Scrollable 挂
    // RawScrollbar，与本滚动条叠加会成为「双滚动条」）。
    return ScrollConfiguration(
      behavior: const _NoFrameworkScrollBar(),
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: vertical
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [Expanded(child: widget.child), laneBox],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [Expanded(child: widget.child), laneBox],
              ),
      ),
    );
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

    final base =
        deepen ? Color.lerp(onSurface, const Color(0xFF000000), 0.25)! : onSurface;
    final thumbColor = base.withValues(alpha: alpha);
    final pad = AppScrollBar.edgePadding;
    final radius = Radius.circular(thickness / 2);

    if (vertical) {
      if (showTrack) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(size.width - thickness - pad, 0, thickness, size.height),
            radius,
          ),
          Paint()..color = onSurface.withValues(alpha: 0.10),
        );
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
              size.width - thickness - pad, thumbOffset, thickness, thumbLength),
          radius,
        ),
        Paint()..color = thumbColor,
      );
    } else {
      if (showTrack) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(0, size.height - thickness - pad, size.width, thickness),
            radius,
          ),
          Paint()..color = onSurface.withValues(alpha: 0.10),
        );
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
              thumbOffset, size.height - thickness - pad, thumbLength, thickness),
          radius,
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