import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart'
    show
        MiuixHorizontalScrollBar,
        MiuixScrollBarAdapter,
        MiuixScrollBarColors,
        MiuixVerticalScrollBar;
import 'package:winwin/core/shell/app_theme_host.dart';

/// Material `Scrollbar` 的零 material 替身：flutter_miuix 浮动滚动条 + **独立通道**。
///
/// 与 Material `Scrollbar`（叠加在内容之上）不同，本组件为滚动条**预留一条独立通道**：
/// 内容区经 [Expanded] 左移，滚动条独占面板最外侧 [_laneThickness] 宽的通道 —— 使滚动条
/// 处于「内容区域」与「窗口边缘」**之间**，永不覆盖内容（实机反馈修正）。
///
/// 其余针对实机反馈的差异：
/// - **贴边**：`endPadding = 1`，滑块右缘距面板（≈窗口）右缘仅 1px；
/// - **hover 只作用于滑轨**：仅通道内挂 [MouseRegion]，鼠标进入滑轨带才触发强化样式
///   （Miuix 默认把滚动条铺满整个面板、鼠标进入页面任意处即 hover，语义不符）；
/// - **强化 hover**：滑块不透明度 0.30 → 0.65，叠加 Miuix 自身宽度动画（3.64 → 6），
///   并显示一条可见滑轨（`trackColor`）；过渡用 [TweenAnimationBuilder] 平滑。
class AppScrollBar extends StatefulWidget {
  const AppScrollBar({
    super.key,
    required this.controller,
    required this.child,
    this.axis = Axis.vertical,
  });

  /// 目标滚动视图的控制器。
  final ScrollController controller;

  /// 被包裹的滚动视图（内容区）。
  final Widget child;

  /// 滚动条方向，默认竖向。
  final Axis axis;

  /// 滚动条独立通道的厚度（同时是 hover 触发带宽度）。
  static const double laneThickness = 12;

  /// 滑块距面板边缘的间距（越小越贴边）。
  static const double edgePadding = 1;

  @override
  State<AppScrollBar> createState() => _AppScrollBarState();
}

class _AppScrollBarState extends State<AppScrollBar> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final onSurface = AppThemeHost.of(context).colors.onSurface;
    final vertical = widget.axis == Axis.vertical;

    final barArea = MouseRegion(
      opaque: false,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: _hovered ? 1 : 0),
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        builder: (context, t, _) {
          final colors = MiuixScrollBarColors(
            thumbColor: onSurface.withValues(alpha: 0.30 + 0.35 * t),
            trackColor: t <= 0 ? null : onSurface.withValues(alpha: 0.12 * t),
          );
          return vertical
              ? MiuixVerticalScrollBar(
                  adapter: MiuixScrollBarAdapter(widget.controller),
                  colors: colors,
                  endPadding: AppScrollBar.edgePadding,
                )
              : MiuixHorizontalScrollBar(
                  adapter: MiuixScrollBarAdapter(widget.controller),
                  colors: colors,
                  endPadding: AppScrollBar.edgePadding,
                );
        },
      ),
    );

    // 为滚动条预留独立通道：内容占满剩余空间，滚动条独占最外侧一条。
    return vertical
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: widget.child),
              SizedBox(width: AppScrollBar.laneThickness, child: barArea),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: widget.child),
              SizedBox(height: AppScrollBar.laneThickness, child: barArea),
            ],
          );
  }
}