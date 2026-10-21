import 'package:flutter/widgets.dart';

/// 贴触发器的浮层定位（B7-c6-4 反馈轮：音量条 / 投币浮层共用）。
///
/// 把 [child] 水平居中于锚点、垂直置于锚点**上方**；上方放不下则翻转到
/// 下方；两轴均夹取进 [edge] 边距内，避免越出可视区域。
///
/// [anchor] 必须与浮层处于**同一坐标系**：浮层与页面同栈时取"同一 Stack
/// 坐标系"，浮层独占整页时取"整页（根 Overlay）坐标系"。
///
/// 用法：作为 [Stack] 的直接子节点。内部以 `Positioned.fill` 占满 Stack，
/// 再由 [CustomSingleChildLayout] 定位；本组件自身不产生渲染对象，故不影响
/// `Positioned` 对父级必须为 Stack 的校验。
class AppAnchoredPopup extends StatelessWidget {
  const AppAnchoredPopup({
    super.key,
    required this.anchor,
    required this.child,
    this.gap = 8,
    this.edge = 8,
  });

  /// 触发按钮在目标坐标系中的矩形。
  final Rect anchor;

  /// 浮层与锚点之间的间距。
  final double gap;

  /// 浮层与可用区域边缘的最小留白。
  final double edge;

  /// 浮层内容（须自带尺寸：由委托给出 loose 约束）。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: CustomSingleChildLayout(
        delegate: _AppAnchoredPopupLayout(anchor: anchor, gap: gap, edge: edge),
        child: child,
      ),
    );
  }
}

/// 取 [anchorContext] 相对 [ancestorContext] 的矩形（浮层锚点）。
///
/// 任一 RenderObject 缺失/尚未布局时返回 null，调用方据此跳过渲染。
Rect? anchorRectOf(
  BuildContext anchorContext, {
  required BuildContext ancestorContext,
}) {
  final anchorBox = anchorContext.findRenderObject() as RenderBox?;
  final ancestorBox = ancestorContext.findRenderObject() as RenderBox?;
  if (anchorBox == null || ancestorBox == null) return null;
  if (!anchorBox.hasSize || !ancestorBox.hasSize) return null;
  return anchorBox.localToGlobal(Offset.zero, ancestor: ancestorBox) &
      anchorBox.size;
}

/// 取 [anchorContext] 在**根 Overlay** 坐标系中的矩形（整页浮层的锚点）。
Rect? anchorRectInRootOverlay(BuildContext anchorContext) {
  final overlay = Overlay.maybeOf(anchorContext, rootOverlay: true);
  if (overlay == null) return null;
  return anchorRectOf(anchorContext, ancestorContext: overlay.context);
}

/// 贴触发器浮层的**开/关动画壳**（二级浮层统一口径：音量弹层等）。
///
/// 在 [AppAnchoredPopup] 的定位之上补两段动画，补齐此前"只在打开瞬间突现、
/// 关闭时硬移除"的缺环：
/// - 展开：`Fade + Scale`（0.92→1，easeOutCubic，180ms）；
/// - 收起：同动效反向（140ms）——**保留在树上播完再卸载**，故由 [visible]
///   驱动（而非调用方 `if (open) popup` 增删子树）。
/// - 缩放原点取贴近触发器的一角（[alignment]，默认 [Alignment.bottomRight]
///   ——浮层位于触发器上方时的就近对角），与表情面板 / 弹层菜单同一
///   "对角线展开"范式。
///
/// 完全收起后返回空组件：不占布局、不参与命中。用法同 [AppAnchoredPopup]，
/// 作为 [Stack] 的直接子节点。
class MiuixAnchoredPopup extends StatefulWidget {
  const MiuixAnchoredPopup({
    super.key,
    required this.visible,
    required this.anchor,
    required this.child,
    this.alignment = Alignment.bottomRight,
    this.gap = 8,
    this.edge = 8,
  });

  /// 是否展开（true→正向动画；false→反向动画后卸载）。
  final bool visible;

  /// 触发按钮在目标坐标系中的矩形。
  final Rect anchor;

  /// 浮层内容（须自带尺寸；通常为 `MiuixOverlayPanel`）。
  final Widget child;

  /// 对角缩放的锚点角（贴触发器一侧）。
  final Alignment alignment;

  final double gap;
  final double edge;

  @override
  State<MiuixAnchoredPopup> createState() => _MiuixAnchoredPopupState();
}

class _MiuixAnchoredPopupState extends State<MiuixAnchoredPopup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    reverseDuration: const Duration(milliseconds: 140),
    value: widget.visible ? 1.0 : 0.0,
  );

  @override
  void initState() {
    super.initState();
    // 收起动画播完后触发一次重建，使 build 返回空组件真正卸载子树。
    _anim.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant MiuixAnchoredPopup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        _anim.forward();
      } else {
        _anim.reverse();
      }
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible && _anim.isDismissed) return const SizedBox.shrink();
    final curved = CurvedAnimation(
      parent: _anim,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return AppAnchoredPopup(
      anchor: widget.anchor,
      gap: widget.gap,
      edge: widget.edge,
      child: IgnorePointer(
        ignoring: !widget.visible,
        child: FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
            alignment: widget.alignment,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _AppAnchoredPopupLayout extends SingleChildLayoutDelegate {
  const _AppAnchoredPopupLayout({
    required this.anchor,
    required this.gap,
    required this.edge,
  });

  final Rect anchor;
  final double gap;
  final double edge;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    // 水平：居中于锚点后夹取进可用宽度。
    final maxDx = size.width - edge - childSize.width;
    var dx = anchor.center.dx - childSize.width / 2;
    if (dx > maxDx) dx = maxDx;
    if (dx < edge) dx = edge;
    // 垂直：上方优先，放不下则翻转到下方。
    var dy = anchor.top - gap - childSize.height;
    if (dy < edge) {
      final below = anchor.bottom + gap;
      dy = (below + childSize.height <= size.height - edge)
          ? below
          : (size.height - edge - childSize.height);
    }
    final maxDy = size.height - edge - childSize.height;
    if (dy > maxDy) dy = maxDy;
    if (dy < edge) dy = edge;
    return Offset(dx, dy);
  }

  @override
  bool shouldRelayout(_AppAnchoredPopupLayout oldDelegate) =>
      oldDelegate.anchor != anchor ||
      oldDelegate.gap != gap ||
      oldDelegate.edge != edge;
}
