import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart'
    show
        MiuixHorizontalScrollBar,
        MiuixScrollBarAdapter,
        MiuixVerticalScrollBar;

/// Material `Scrollbar` 的零 material 替身：改用 flutter_miuix 的浮动滚动条。
///
/// 差异：Miuix 的 [MiuixVerticalScrollBar] / [MiuixHorizontalScrollBar] 是
/// **叠加层**（依据 [MiuixScrollBarAdapter] 绘制的浮动滑块），并非包裹式组件；
/// 因此这里用 [Stack] 把滚动条压在内容之上，对外仍保持
/// `Scrollbar(controller:, child:)` 的调用形态，便于逐处无痛替换。
///
/// 命中行为：叠加层使用 translucent 命中策略，仅消费滑块区拖拽手势，
/// 滚动视图的滚轮 / 点击仍可穿透，与 Material `Scrollbar` 语义一致。
class AppScrollBar extends StatelessWidget {
  const AppScrollBar({
    super.key,
    required this.controller,
    required this.child,
    this.axis = Axis.vertical,
  });

  /// 目标滚动视图的控制器（Miuix 通过它读取滚动位置）。
  final ScrollController controller;

  /// 被包裹的滚动视图。
  final Widget child;

  /// 滚动条方向，默认竖向。
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final Widget bar = axis == Axis.vertical
        ? MiuixVerticalScrollBar(adapter: MiuixScrollBarAdapter(controller))
        : MiuixHorizontalScrollBar(adapter: MiuixScrollBarAdapter(controller));
    return Stack(
      children: [child, Positioned.fill(child: bar)],
    );
  }
}