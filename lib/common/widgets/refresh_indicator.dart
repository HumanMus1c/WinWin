import 'dart:ui' show PointerDeviceKind;

import 'package:flutter_miuix/miuix.dart';
import 'package:material_ui/material_ui.dart';

import 'package:winwin/theme/inherited_ui_style.dart';
import 'package:winwin/theme/ui_style.dart';

/// 自适应下拉刷新指示器（对齐双风格设计系统）。
///
/// - **Material 3**：标准 [RefreshIndicator]（原实现保留；[displacement] /
///   [edgeOffset] 生效）。
/// - **Miuix**：[MiuixPullToRefresh]（flutter_miuix 原生 HyperOS 下拉刷新）。
///
/// 接缝设计：调用点契约（`onRefresh: () async {...}` 返回 [Future]）保持不变——
/// 本组件内部把 Future 语义映射为 [MiuixPullToRefresh.isRefreshing]（触发即置真、
/// Future 完成自动复位），8 处调用点零改动。
///
/// 物理引擎修复（阶段3d 回归修复）：MiuixPullToRefresh 依赖顶部越界的
/// `OverscrollNotification` 驱动下拉视觉与触发；而全局 AppScrollBehavior 的
/// BouncingScrollPhysics 会把下拉位移直接吸收为 overscroll 位置（只剩回弹、
/// 不派发通知），导致"下拉只回弹、不出现刷新提示、不触发刷新"。故在刷新子树内
/// 以 [ScrollConfiguration] 切换到 ClampingScrollPhysics（仍保留鼠标/触控板
/// 拖拽），M3 分支与其余页面不受影响。
class AppRefreshIndicator extends StatefulWidget {
  const AppRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
    this.displacement = 40.0,
    this.edgeOffset = 0.0,
  });

  final RefreshCallback onRefresh;
  final Widget child;

  /// 仅 M3 分支生效。
  final double displacement;
  final double edgeOffset;

  @override
  State<AppRefreshIndicator> createState() => _AppRefreshIndicatorState();
}

class _AppRefreshIndicatorState extends State<AppRefreshIndicator> {
  bool _refreshing = false;

  Future<void> _handleRefresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = InheritedUiStyle.of(context);

    switch (resolvePrimitiveRenderer(style)) {
      case PrimitiveRenderer.material3:
        return RefreshIndicator(
          onRefresh: widget.onRefresh,
          displacement: widget.displacement,
          edgeOffset: widget.edgeOffset,
          child: widget.child,
        );
      case PrimitiveRenderer.miuix:
        return ScrollConfiguration(
          behavior: const _MiuixRefreshScrollBehavior(),
          child: MiuixPullToRefresh(
            isRefreshing: _refreshing,
            onRefresh: _handleRefresh,
            refreshTexts: kMiuixRefreshTexts,
            child: widget.child,
          ),
        );
    }
  }
}

/// 刷新子树滚动行为：Clamping 越界 → 派发 OverscrollNotification
/// （MiuixPullToRefresh 的驱动信号）；同时保留桌面端鼠标/触控板拖拽。
class _MiuixRefreshScrollBehavior extends MaterialScrollBehavior {
  const _MiuixRefreshScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}

/// Miuix 下拉刷新的中文状态文案（顺序对齐 MiuixPullToRefreshDefaults）。
const List<String> kMiuixRefreshTexts = [
  '下拉刷新',
  '松开刷新',
  '刷新中...',
  '刷新完成',
];
