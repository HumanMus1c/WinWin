import 'package:flutter/material.dart';

import 'package:winwin/theme/inherited_ui_style.dart';
import 'package:winwin/theme/ui_style.dart';

/// 自适应下拉刷新指示器（对齐双风格设计系统）。
///
/// 按 [UiStyle] 切换：
/// - **Material 3**：标准 [RefreshIndicator]（M3 拉拽指示器，标准 40dp 偏移）。
/// - **Miuix**：[RefreshIndicator] 紧凑扁平视觉（32dp 紧凑偏移，细边框指示环）。
///
/// 用法：
/// ```dart
/// AppRefreshIndicator(
///   onRefresh: controller.onRefresh,
///   child: ListView(...),
/// )
/// ```
class AppRefreshIndicator extends StatelessWidget {
  const AppRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
    this.displacement = 40.0,
    this.edgeOffset = 0.0,
  });

  final RefreshCallback onRefresh;
  final Widget child;
  final double displacement;
  final double edgeOffset;

  @override
  Widget build(BuildContext context) {
    final style = InheritedUiStyle.of(context);

    switch (resolvePrimitiveRenderer(style)) {
      case PrimitiveRenderer.material3:
        return RefreshIndicator(
          onRefresh: onRefresh,
          displacement: displacement,
          edgeOffset: edgeOffset,
          child: child,
        );
      case PrimitiveRenderer.miuix:
        return RefreshIndicator(
          onRefresh: onRefresh,
          // Miuix 紧凑扁平视觉
          displacement: displacement * 0.8,
          strokeWidth: 2.2,
          edgeOffset: edgeOffset,
          child: child,
        );
    }
  }
}

