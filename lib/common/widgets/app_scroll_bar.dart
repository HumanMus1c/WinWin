import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart'
    show
        MiuixHorizontalScrollBar,
        MiuixScrollBarAdapter,
        MiuixScrollBarColors,
        MiuixVerticalScrollBar;
import 'package:winwin/core/shell/app_theme_host.dart';

/// Material `Scrollbar` 的零 material 替身：flutter_miuix 浮动滚动条 + 「贴边 / 强化 hover」。
///
/// 与 Miuix 默认行为的差异（针对实机反馈修正）：
/// - **贴边**：`endPadding = 1`，滑块右缘距面板（≈窗口）右缘仅 1px（默认 3.46px 偏内）；
/// - **hover 只作用于滑轨**：滚动条被收进右侧 [_hitThickness] 窄条内，并在该窄条上挂
///   [MouseRegion] —— 只有鼠标进入滑轨带才触发强化样式。Miuix 默认把滚动条铺满整个面板、
///   其内部 MouseRegion 覆盖整面板，鼠标进入页面任意处即 hover，语义不符；
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

  /// 被包裹的滚动视图。
  final Widget child;

  /// 滚动条方向，默认竖向。
  final Axis axis;

  /// 滑轨命中带厚度（hover 触发区宽度）。
  static const double hitThickness = 14;

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

    final bar = TweenAnimationBuilder<double>(
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
    );

    return Stack(
      children: [
        widget.child,
        Positioned(
          top: vertical ? 0 : null,
          bottom: 0,
          left: vertical ? null : 0,
          right: 0,
          width: vertical ? AppScrollBar.hitThickness : null,
          height: vertical ? null : AppScrollBar.hitThickness,
          child: MouseRegion(
            opaque: false,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: bar,
          ),
        ),
      ],
    );
  }
}