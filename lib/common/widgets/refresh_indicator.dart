import 'package:flutter_miuix/miuix.dart';
import 'package:material_ui/material_ui.dart';

import 'package:winwin/theme/inherited_ui_style.dart';
import 'package:winwin/theme/ui_style.dart';

/// 自适应下拉刷新指示器（对齐双风格设计系统）。
///
/// - **Material 3**：标准 [RefreshIndicator]（原实现保留；[displacement] /
///   [edgeOffset] 生效）。
/// - **Miuix**：[MiuixPullToRefresh]（flutter_miuix 原生 HyperOS 下拉刷新；
///   阶段3d 起替换原 RefreshIndicator 紧凑近似）。
///
/// 接缝设计：调用点契约（`onRefresh: () async {...}` 返回 [Future]）保持不变——
/// 本组件内部把 Future 语义映射为 [MiuixPullToRefresh.isRefreshing]（触发即置真、
/// Future 完成自动复位），8 处调用点零改动。
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
        return MiuixPullToRefresh(
          isRefreshing: _refreshing,
          onRefresh: _handleRefresh,
          refreshTexts: kMiuixRefreshTexts,
          child: widget.child,
        );
    }
  }
}

/// Miuix 下拉刷新的中文状态文案（顺序对齐 MiuixPullToRefreshDefaults）。
const List<String> kMiuixRefreshTexts = [
  '下拉刷新',
  '松开刷新',
  '刷新中...',
  '刷新完成',
];
