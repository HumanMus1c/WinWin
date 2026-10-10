import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:material_ui/material_ui.dart'
    show RefreshCallback, RefreshIndicator;

/// 下拉刷新指示器（阶段5d-L1：M3 分支已移除，紧凑扁平视觉为唯一实现）。
///
/// 视觉与功能口径（用户偏好定格）：紧凑偏移（32dp 等效）与细边框指示环，
/// 拖拽触发行为保持历史实现不变。
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
    return RefreshIndicator(
      onRefresh: onRefresh,
      // 紧凑扁平视觉（原 Miuix 分支取值）
      displacement: displacement * 0.8,
      strokeWidth: 2.2,
      edgeOffset: edgeOffset,
      child: child,
    );
  }
}

/// Miuix 库下拉刷新（`MiuixPullToRefresh` 薄封装：中文文案）。
///
/// B7 反馈轮#2：评论区 / 消息中心等"刷新即清列表"的场景改用本组件 ——
/// 下拉反馈 = Miuix 库自身的指示器（圆环 + 状态文案，内容下推），
/// 不再与居中加载环同屏叠加（刷新期间调用方保留现有内容）。
class AppMiuixRefresh extends StatelessWidget {
  const AppMiuixRefresh({
    super.key,
    required this.isRefreshing,
    required this.onRefresh,
    required this.child,
  });

  /// 刷新状态（由调用方提升管理；`onRefresh` 内应尽快置 true）。
  final bool isRefreshing;

  /// 越过阈值松手后回调。
  final VoidCallback onRefresh;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MiuixPullToRefresh(
      isRefreshing: isRefreshing,
      onRefresh: onRefresh,
      refreshTexts: const ['下拉刷新', '释放刷新', '正在刷新…', '刷新完成'],
      child: child,
    );
  }
}
