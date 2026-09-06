import 'package:flutter/material.dart';

import 'package:winwin/theme/app_shapes.dart';

/// 视频详情页头部 Sliver（Phase 7.6.1）。
///
/// 参照 PiliPlus 的 `VideoHeader`：使用 [SliverPersistentHeader] 实现
/// 播放器 pin 效果——滚动时播放器从最大高度（maxExtent）逐渐收缩到
/// 最小高度（minExtent），收缩过程中通过 [onScrollRatioChange] 回调
/// 通知外部当前的滚动比例（0.0 = 完全展开，1.0 = 完全 pin）。
///
/// 与自定义 `RenderSliver` 方案相比，[SliverPersistentHeader] 更简单
/// 且无需手动管理 hitTest / paint，足以满足桌面端 pin 需求。
///
/// 用法：
/// ```dart
/// SliverPersistentHeader(
///   pinned: true,
///   delegate: VideoHeaderDelegate(
///     maxExtent: 320,
///     minExtent: 200,
///     builder: (context, scrollRatio) => PlayerWidget(...),
///     onScrollRatioChange: (ratio) => setState(() => _scrollRatio = ratio),
///   ),
/// )
/// ```
class VideoHeaderDelegate extends SliverPersistentHeaderDelegate {
  VideoHeaderDelegate({
    required this.maxExtent,
    required this.minExtent,
    required this.builder,
    this.child,
    this.onScrollRatioChange,
  })  : assert(maxExtent >= minExtent),
        assert(minExtent >= 0);

  /// 播放器最大高度（展开态，通常为宽度 * 9/16）。
  @override
  final double maxExtent;

  /// 播放器最小高度（pin 态，播放器保持可见的最小高度）。
  @override
  final double minExtent;

  /// 构建 header 内容，[scrollRatio] 为 0.0-1.0 的收缩比例。
  final Widget Function(BuildContext context, double scrollRatio) builder;

  /// 承载的子组件（用于 [shouldRebuild] 准确感知内容变化）。
  final Widget? child;

  /// 收缩比例变化回调（用于顶栏渐变显示等）。
  final ValueChanged<double>? onScrollRatioChange;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final range = maxExtent - minExtent;
    final ratio = range > 0 ? (shrinkOffset / range).clamp(0.0, 1.0) : 0.0;
    // 通知外部当前比例（在微任务中回调，避免在 build 中直接 setState）
    if (onScrollRatioChange != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onScrollRatioChange!(ratio);
      });
    }
    return builder(context, ratio);
  }

  @override
  bool shouldRebuild(VideoHeaderDelegate oldDelegate) =>
      maxExtent != oldDelegate.maxExtent ||
      minExtent != oldDelegate.minExtent ||
      child != oldDelegate.child;
}

/// 构建播放器 header 的便捷封装。
///
/// 自动应用 [AppShapes] 的圆角，并在收缩时隐藏圆角（pin 态全宽）。
class VideoHeader extends StatelessWidget {
  const VideoHeader({
    super.key,
    required this.child,
    required this.maxExtent,
    required this.minExtent,
    this.onScrollRatioChange,
  });

  /// 播放器内容。
  final Widget child;

  /// 最大高度。
  final double maxExtent;

  /// 最小高度（pin 态）。
  final double minExtent;

  /// 收缩比例回调。
  final ValueChanged<double>? onScrollRatioChange;

  @override
  Widget build(BuildContext context) {
    final shapes = Theme.of(context).extension<AppShapes>() ?? AppShapes.ios;
    return SliverPersistentHeader(
      pinned: true,
      delegate: VideoHeaderDelegate(
        maxExtent: maxExtent,
        minExtent: minExtent,
        child: child,
        onScrollRatioChange: onScrollRatioChange,
        builder: (context, scrollRatio) {
          // 收缩时圆角逐渐变为 0（pin 态全宽贴顶）
          final radius = shapes.medium.x * (1.0 - scrollRatio);
          return ClipRRect(
            borderRadius: BorderRadius.vertical(
              bottom: Radius.circular(radius),
            ),
            child: ColoredBox(
              color: Colors.black,
              child: SizedBox(
                width: double.infinity,
                height: maxExtent,
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }
}
