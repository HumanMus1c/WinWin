import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

/// 桌面悬停提示（Miuix 视觉；浮层生命周期由框架托管）。
///
/// 交互口径（对齐 B7-b1 迁移后的 Miuix 观感）：悬停 / 长按即时显示；移出后
/// 经微任务复核隐藏（悬停到提示泡上时保持显示）；显示 1.5s 后自动隐藏；
/// 同一时刻全局至多一个提示泡。
///
/// 修复背景（2026-10-12）：原实现对 flutter_miuix 1.3.0 `MiuixTooltipBox`
/// 的直接封装在“悬停 × 宿主高频重建/结构变化”下存在浮层生命周期竞态——
/// 会向已卸载（DEFUNCT）的浮层条目 markNeedsBuild、并在已停用元素上查找
/// Overlay，在视频页控制栏引发异常雨，并最终在返回弹出路由时触发
/// `_dependents.isEmpty` 框架断言（红屏）。本实现改以 [OverlayPortal] 将
/// 浮层生命周期交还框架托管：宿主元素停用/卸载时浮层自动随动清理，从机制
/// 上消除悬挂条目。定位与动效沿用 flutter_miuix 的 Tooltip 口径
/// （Apache-2.0，源自 compose-miuix-ui/miuix 的 Tooltip.kt 移植版）。
class AppTooltip extends StatefulWidget {
  const AppTooltip({
    super.key,
    required this.message,
    required this.child,
  });

  final String message;
  final Widget child;

  @override
  State<AppTooltip> createState() => _AppTooltipState();
}

class _AppTooltipState extends State<AppTooltip>
    with SingleTickerProviderStateMixin {
  /// 全局单活动槽：同一时刻至多一个提示泡（对齐 Miuix 语义）。
  static _AppTooltipState? _active;

  static const Duration _autoHideAfter = Duration(milliseconds: 1500);
  static const Duration _animationDuration = Duration(milliseconds: 180);
  static const double _spacing = 8.0;

  final OverlayPortalController _portal = OverlayPortalController();

  /// 实际采用的方位（定位委托在布局期回写，驱动内部 caret 分支）。
  /// 不主动 dispose：定位委托的 postFrame 回写可能晚于宿主卸载，
  /// 写未销毁的 ValueNotifier 是安全的，随 State 一同回收。
  final ValueNotifier<MiuixTooltipAnchorPosition> _actualPosition =
      ValueNotifier(MiuixTooltipAnchorPosition.below);

  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: _animationDuration,
    reverseDuration: _animationDuration,
  )..addStatusListener(_onAnimationStatus);

  Timer? _autoHideTimer;
  bool _hoveringAnchor = false;
  bool _hoveringBubble = false;

  /// 显示时定格的锚点边界（Overlay 坐标系；与 Miuix 口径一致）。
  Rect? _anchor;

  /// 元素活跃性守卫：已停用（inactive）或已卸载后不得再触碰 context 与
  /// 浮层——原实现缺失该守卫，是“deactivated ancestor”异常的直接原因。
  bool get _canTouch => mounted && context.mounted;

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
    if (identical(_active, this)) _active = null;
    // 浮层随本元素卸载由 OverlayPortal 自动清理，无需（也不应）手动触达。
    _anim.dispose();
    super.dispose();
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && _canTouch && _portal.isShowing) {
      _portal.hide();
    }
  }

  void _show() {
    if (!_canTouch) return;
    if (!_portal.isShowing) {
      final overlay = Overlay.maybeOf(context);
      final anchorBox = context.findRenderObject() as RenderBox?;
      final overlayBox = overlay?.context.findRenderObject() as RenderBox?;
      if (overlay == null ||
          anchorBox == null ||
          overlayBox == null ||
          !anchorBox.hasSize) {
        return;
      }
      _anchor =
          anchorBox.localToGlobal(Offset.zero, ancestor: overlayBox) &
              anchorBox.size;
      _actualPosition.value = MiuixTooltipAnchorPosition.below;
    }
    final previous = _active;
    if (previous != null && !identical(previous, this)) {
      previous._dismiss();
    }
    _active = this;
    if (!_portal.isShowing) {
      _portal.show();
    }
    _anim.forward();
    _autoHideTimer?.cancel();
    _autoHideTimer = Timer(_autoHideAfter, _dismiss);
  }

  void _dismiss() {
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
    if (identical(_active, this)) _active = null;
    if (!_canTouch || !_portal.isShowing) return;
    if (_anim.value <= 0.0) {
      _portal.hide();
      return;
    }
    _anim.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      onLongPress: _show,
      onLongPressHint: '显示提示',
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (overlayContext) => _buildOverlayChild(),
        child: MouseRegion(
          onEnter: (_) {
            _hoveringAnchor = true;
            _show();
          },
          onExit: (_) {
            _hoveringAnchor = false;
            scheduleMicrotask(() {
              if (!_hoveringAnchor && !_hoveringBubble) _dismiss();
            });
          },
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            excludeFromSemantics: true,
            onLongPress: _show,
            child: widget.child,
          ),
        ),
      ),
    );
  }

  Widget _buildOverlayChild() {
    final anchor = _anchor;
    if (anchor == null || !_canTouch) return const SizedBox.shrink();
    // 主题/方向取宿主侧（仅在浮层构建这一“显示期”懒读取）；无主题包裹时
    // MiuixTheme.of 回退浅色默认，不会因环境缺失主题报错。
    final theme = MiuixTheme.of(context);
    final direction = Directionality.of(context);
    return MiuixTheme(
      data: theme,
      child: Directionality(
        textDirection: direction,
        child: Stack(
          children: [
            CustomSingleChildLayout(
              delegate: _AppTooltipPositionDelegate(
                anchor: anchor,
                preferred: MiuixTooltipAnchorPosition.below,
                spacing: _spacing,
                textDirection: direction,
                actualPosition: _actualPosition,
              ),
              child: FadeTransition(
                opacity: CurvedAnimation(
                  parent: _anim,
                  curve: Curves.easeOut,
                  reverseCurve: Curves.easeIn,
                ),
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.9, end: 1.0).animate(
                    CurvedAnimation(
                      parent: _anim,
                      curve: Curves.easeOutBack,
                      reverseCurve: Curves.easeIn,
                    ),
                  ),
                  child: MouseRegion(
                    onEnter: (_) => _hoveringBubble = true,
                    onExit: (_) {
                      _hoveringBubble = false;
                      if (!_hoveringAnchor) _dismiss();
                    },
                    child: ValueListenableBuilder<MiuixTooltipAnchorPosition>(
                      valueListenable: _actualPosition,
                      builder: (context, position, _) => MiuixPlainTooltip(
                        scope: MiuixTooltipScope(
                          positioning: position,
                          anchorBounds: anchor,
                        ),
                        child: Text(widget.message),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tooltip 定位委托：below 优先、空间不足翻转到对侧、两轴钳制在视窗内。
///
/// 移植自 flutter_miuix 1.3.0 `_MiuixTooltipPositionDelegate`
/// （Apache-2.0，源自 compose-miuix-ui/miuix 的 Tooltip.kt 移植版），
/// 语义保持一致：锚点与间距判定、翻转、以及 postFrame 回写实际方位。
class _AppTooltipPositionDelegate extends SingleChildLayoutDelegate {
  _AppTooltipPositionDelegate({
    required this.anchor,
    required this.preferred,
    required this.spacing,
    required this.textDirection,
    required this.actualPosition,
  });

  final Rect anchor;
  final MiuixTooltipAnchorPosition preferred;
  final double spacing;
  final TextDirection textDirection;
  final ValueNotifier<MiuixTooltipAnchorPosition> actualPosition;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final resolved = _resolveAnchorPosition(preferred, textDirection);
    final opposite = _oppositeAnchorPosition(resolved);
    final selected = _fits(resolved, size, childSize) ||
            !_fits(opposite, size, childSize)
        ? resolved
        : opposite;
    if (actualPosition.value != selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (actualPosition.value != selected) {
          actualPosition.value = selected;
        }
      });
    }

    double x = anchor.center.dx - childSize.width / 2;
    double y = anchor.center.dy - childSize.height / 2;
    switch (selected) {
      case MiuixTooltipAnchorPosition.above:
        y = anchor.top - childSize.height - spacing;
      case MiuixTooltipAnchorPosition.below:
        y = anchor.bottom + spacing;
      case MiuixTooltipAnchorPosition.left:
        x = anchor.left - childSize.width - spacing;
      case MiuixTooltipAnchorPosition.right:
        x = anchor.right + spacing;
      case MiuixTooltipAnchorPosition.start:
      case MiuixTooltipAnchorPosition.end:
        break;
    }
    return Offset(
      x.clamp(0.0, (size.width - childSize.width).clamp(0.0, size.width)),
      y.clamp(0.0, (size.height - childSize.height).clamp(0.0, size.height)),
    );
  }

  bool _fits(MiuixTooltipAnchorPosition side, Size area, Size child) {
    return switch (side) {
      MiuixTooltipAnchorPosition.above =>
        anchor.top - spacing >= child.height,
      MiuixTooltipAnchorPosition.below =>
        area.height - anchor.bottom - spacing >= child.height,
      MiuixTooltipAnchorPosition.left => anchor.left - spacing >= child.width,
      MiuixTooltipAnchorPosition.right =>
        area.width - anchor.right - spacing >= child.width,
      MiuixTooltipAnchorPosition.start ||
      MiuixTooltipAnchorPosition.end =>
        false,
    };
  }

  @override
  bool shouldRelayout(_AppTooltipPositionDelegate oldDelegate) =>
      anchor != oldDelegate.anchor ||
      preferred != oldDelegate.preferred ||
      spacing != oldDelegate.spacing ||
      textDirection != oldDelegate.textDirection;
}

MiuixTooltipAnchorPosition _resolveAnchorPosition(
  MiuixTooltipAnchorPosition position,
  TextDirection direction,
) {
  if (position == MiuixTooltipAnchorPosition.start) {
    return direction == TextDirection.ltr
        ? MiuixTooltipAnchorPosition.left
        : MiuixTooltipAnchorPosition.right;
  }
  if (position == MiuixTooltipAnchorPosition.end) {
    return direction == TextDirection.ltr
        ? MiuixTooltipAnchorPosition.right
        : MiuixTooltipAnchorPosition.left;
  }
  return position;
}

MiuixTooltipAnchorPosition _oppositeAnchorPosition(
  MiuixTooltipAnchorPosition position,
) {
  return switch (position) {
    MiuixTooltipAnchorPosition.above => MiuixTooltipAnchorPosition.below,
    MiuixTooltipAnchorPosition.below => MiuixTooltipAnchorPosition.above,
    MiuixTooltipAnchorPosition.left => MiuixTooltipAnchorPosition.right,
    MiuixTooltipAnchorPosition.right => MiuixTooltipAnchorPosition.left,
    MiuixTooltipAnchorPosition.start => MiuixTooltipAnchorPosition.end,
    MiuixTooltipAnchorPosition.end => MiuixTooltipAnchorPosition.start,
  };
}
