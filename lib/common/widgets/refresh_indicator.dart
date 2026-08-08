import 'package:flutter/cupertino.dart' hide RefreshCallback;
import 'package:flutter/material.dart';

import 'package:winwin/theme/inherited_ui_style.dart';
import 'package:winwin/theme/ui_style.dart';

/// 自适应下拉刷新指示器（Phase 7.5.6）。
///
/// 参照 PiliPlus 的 fork 简化版 RefreshIndicator，按 [UiStyle] 切换：
/// - iOS：[CupertinoActivityIndicator]（旋转圆环），无 displacement 偏移。
/// - MD3：标准 [RefreshIndicator]（M3 拉拽指示器）。
/// - Miuix：[RefreshIndicator] + 较小 displacement，扁平视觉。
///
/// 用法：
/// ```dart
/// AppRefreshIndicator(
///   onRefresh: controller.onRefresh,
///   child: CustomScrollView(...),
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
      case PrimitiveRenderer.ios:
        // iOS 用 Cupertino 风格刷新（CustomScrollView 顶部下拉触发）
        return CupertinoSliverRefreshControlBuilder(
          onRefresh: onRefresh,
          child: child,
        );
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
          // Miuix 扁平视觉，displacement 略小
          displacement: displacement * 0.85,
          edgeOffset: edgeOffset,
          child: child,
        );
    }
  }
}

/// iOS 风格 sliver 刷新控件封装。
///
/// 由于 [CustomScrollView] 直接子项需为 sliver，这里采用
/// [CupertinoSliverRefreshControl] 嵌入到 sliver 列表头部的方式，
/// 但对外暴露与 [RefreshIndicator] 一致的 `child` API：
/// 将 [child] 包裹到 [CustomScrollView] 中，并保证其可滚动。
class CupertinoSliverRefreshControlBuilder extends StatelessWidget {
  const CupertinoSliverRefreshControlBuilder({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final RefreshCallback onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 若 child 已是 ScrollView（带 CustomScrollView/ListView 等），
    // 直接在其 slivers 头部插入 CupertinoSliverRefreshControl。
    // 简化处理：统一用 CustomScrollView 包装。
    if (child is CustomScrollView) {
      final scrollView = child as CustomScrollView;
      return CustomScrollView(
        controller: scrollView.controller,
        scrollDirection: scrollView.scrollDirection,
        reverse: scrollView.reverse,
        physics: scrollView.physics,
        slivers: [
          CupertinoSliverRefreshControl(
            onRefresh: onRefresh,
            refreshTriggerPullDistance: 60.0,
            refreshIndicatorExtent: 48.0,
          ),
          ...scrollView.slivers,
        ],
      );
    }
    // 退化路径：child 非 CustomScrollView 时用 RefreshIndicator
    return RefreshIndicator(onRefresh: onRefresh, child: child);
  }
}
