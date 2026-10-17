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

  /// 「页面级」滚动视图判定：主轴向尺寸 ≥ 窗口主轴向 × 该比例，才预留通道。
  ///
  /// 弹层 / 面板 / 局部小列表等滚动视图的主轴向尺寸远小于窗口，为其预留
  /// [_laneThickness] 通道会抢走布局（用户实测：视频卡片「更多操作」弹层布局被破坏）。
  static const double pageLevelExtentRatio = 0.5;

  /// 全局接入点（**单一来源**）：由 [AppScrollBehavior.buildScrollbar] 为桌面平台
  /// 每个**竖向** `Scrollable` 挂本滚动条，取代 SDK 默认的 `RawScrollbar`。
  ///
  /// 基类实现对桌面平台返回 `RawScrollbar(controller: details.controller,
  /// child: child)`，其 `radius`/`trackRadius` 默认均为 null ⇒ `ScrollbarPainter`
  /// 走 `canvas.drawRect` 分支（**方角硬矩形条**）、颜色 `0x66BCBCBC`、粗细 6.0，
  /// 与项目口径（圆角 pill + 三态补间 + hover 触发带）不一致。
  ///
  /// 行为：
  /// - 横向 `Scrollable` 返回 `child`（与框架一致，不预留通道，避免列表页面
  ///   底部凭空多出 12px 空白）；
  /// - `details.controller` 为空（理论上不会，框架有非空断言）时返回 `child`，保守降级；
  /// - 竖向则套 [AppScrollBar]；其内部 [AppScrollBar._NoFrameworkScrollBar] 会抑制
  ///   嵌套 `Scrollable` 的重复挂载 ⇒ 每个滚动视图只保留**一条**项目滚动条。
  static Widget attach({
    required Widget child,
    required ScrollableDetails details,
  }) {
    final controller = details.controller;
    if (controller == null) return child;
    final vertical = details.direction == AxisDirection.down ||
        details.direction == AxisDirection.up;
    if (!vertical) return child;
    return AppScrollBar(
      controller: controller,
      axis: Axis.vertical,
      child: child,
    );
  }

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
    final vertical = widget.axis == Axis.vertical;
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = vertical
            ? constraints.hasBoundedWidth
            : constraints.hasBoundedHeight;
        // 约束不定（例如本滚动视图嵌在横向滚动列表中）⇒ 不预留通道，原样返回：
        // 否则 `Expanded` 会在无界约束下断言失败（全局挂载后此类场景可达）。
        if (!bounded) return _suppressFrameworkBar(widget.child);

        // 仅「页面级」滚动视图预留通道。弹层 / 面板 / 局部小列表的主轴向尺寸远小于
        // 窗口，预留通道会抢布局（用户实测：视频卡片「更多操作」弹层布局被破坏）。
        final mainExtent =
            vertical ? constraints.maxHeight : constraints.maxWidth;
        final windowMain = vertical
            ? MediaQuery.sizeOf(context).height
            : MediaQuery.sizeOf(context).width;
        if (!mainExtent.isFinite ||
            mainExtent < windowMain * AppScrollBar.pageLevelExtentRatio) {
          return _suppressFrameworkBar(widget.child);
        }
        return _buildLane(context, vertical);
      },
    );
  }

  /// 不预留通道、仅关闭框架方角硬条（`RawScrollbar` 的 `radius`/`trackRadius`
  /// 默认 null ⇒ `drawRect`，即用户多轮反馈的「直角硬矩形条」）。
  Widget _suppressFrameworkBar(Widget child) => ScrollConfiguration(
        behavior: const _NoFrameworkScrollBar(),
        child: child,
      );

  /// 通道布局：内容经 `Expanded` 让位，滚动条独占最外侧 [laneThickness] 通道。
  Widget _buildLane(BuildContext context, bool vertical) {
    final onSurface = AppThemeHost.of(context).colors.onSurface;

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
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
    );

    // 滚动条**不预留占位**，改为覆盖层贴在内容最外侧 [laneThickness] 条带上：
    // ① 内容尺寸完全不变 ⇒ 弹层 / 面板的高度与宽度既不会被撑开也不会被挤压
    //    （历史问题：预留通道 + `CrossAxisAlignment.stretch` 会把受高度上限约束的
    //    容器撑满 ⇒ 用户实测「弹层容器高度被撑高」）；
    // ② 不存在独立通道 ⇒ 也不会再有「轨道默认占位显示为灰色直角矩形」。
    // 页面普遍已有等宽内边距，覆盖带落在留白上，观感等同「内容区与窗口边缘之间」。
    return ScrollConfiguration(
      behavior: const _NoFrameworkScrollBar(),
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: Stack(
          children: [
            widget.child,
            if (vertical)
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: AppScrollBar.laneThickness,
                child: lane,
              )
            else
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: AppScrollBar.laneThickness,
                child: lane,
              ),
          ],
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
  });

  final bool vertical;
  final Color onSurface;
  final bool canScroll;
  final double thumbOffset;
  final double thumbLength;
  final double thickness;
  final double alpha;
  final bool deepen;

  @override
  void paint(Canvas canvas, Size size) {
    if (!canScroll) return;

    final base =
        deepen ? Color.lerp(onSurface, const Color(0xFF000000), 0.25)! : onSurface;
    final thumbColor = base.withValues(alpha: alpha);
    final pad = AppScrollBar.edgePadding;
    final radius = Radius.circular(thickness / 2);

    // 只画圆角滑块，**不画轨道**：轨道是通高的近似直角带，在默认态即呈现为
    // 「灰色直角矩形」占位（用户多轮反馈的核心观感问题）。
    if (vertical) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
              size.width - thickness - pad, thumbOffset, thickness, thumbLength),
          radius,
        ),
        Paint()..color = thumbColor,
      );
    } else {
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
      old.canScroll != canScroll ||
      old.onSurface != onSurface;
}