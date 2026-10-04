import 'package:material_ui/material_ui.dart';

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
