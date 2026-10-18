import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// 零 material 的**折叠式 Sliver 头图容器**。
///
/// 等价复刻 Flutter Material
/// `SliverAppBar(pinned: true, toolbarHeight: m, expandedHeight: M)`
/// `+ FlexibleSpaceBar(background: X)` 的默认视觉语义
/// （`CollapseMode.parallax`，无 `title`，无 `leading`/`actions`，透明底、零海拔），
/// 以便在 MD3 库级退役（去 `material_ui`）后保持像素级不变。
///
/// 折叠行为与 [FlexibleSpaceBar] 逐式一致（`delta = M - m`，`t = shrinkOffset / delta`）：
/// * 头图高度恒为 `M`，`top = -(delta / 4) * t`（视差上移，最多 `delta / 4`）；
/// * 不透明度在 `t >= 1 - m / delta` 后由 1 线性淡出至 0（完全折叠时头图隐去）；
/// * 过滚动时按 `StretchMode.zoomBackground` 撑满可用高度；
/// * 外层 `ClipRect` 裁剪，随滚动由 `M` 收拢至 `m` 并 pinned 吸附。
class AppSliverHeader extends StatelessWidget {
  const AppSliverHeader({
    super.key,
    required this.expandedHeight,
    required this.toolbarHeight,
    required this.background,
    this.pinned = true,
  }) : assert(expandedHeight >= toolbarHeight);

  /// 完全展开时的高度（对应 `SliverAppBar.expandedHeight`）。
  final double expandedHeight;

  /// 折叠后吸附的最小高度（对应 `SliverAppBar.toolbarHeight`）。
  final double toolbarHeight;

  /// 头图内容（对应 `FlexibleSpaceBar.background`）。
  final Widget background;

  /// 是否在折叠后吸附于顶部（对应 `SliverAppBar.pinned`）。
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: pinned,
      delegate: _AppSliverHeaderDelegate(
        maxExtent: expandedHeight,
        minExtent: toolbarHeight,
        background: background,
      ),
    );
  }
}

class _AppSliverHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _AppSliverHeaderDelegate({
    required this.maxExtent,
    required this.minExtent,
    required this.background,
  });

  @override
  final double maxExtent;

  @override
  final double minExtent;

  final Widget background;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final double delta = maxExtent - minExtent;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // 展开进度：0.0 = 完全展开，1.0 = 完全折叠到 [minExtent]。
        final double currentExtent = math.max(maxExtent - shrinkOffset, minExtent);
        final double t = delta <= 0
            ? 1.0
            : (1.0 - (currentExtent - minExtent) / delta).clamp(0.0, 1.0).toDouble();

        // 头图高度：过滚动时按 zoomBackground 撑满可用高度，否则恒为 [maxExtent]。
        double height = maxExtent;
        if (constraints.maxHeight > height) {
          height = constraints.maxHeight;
        }

        // 视差上移量（parallax）：最多 delta / 4。
        final double topPadding = delta <= 0 ? 0.0 : -(delta / 4.0) * t;

        // 不透明度：末端 [minExtent] 区间内线性淡出（与 FlexibleSpaceBar 一致）。
        double opacity = 1.0;
        if (delta > 0) {
          final double fadeStart = math.max(0.0, 1.0 - minExtent / delta);
          final double span = 1.0 - fadeStart;
          if (span > 0) {
            opacity = 1.0 - ((t - fadeStart) / span).clamp(0.0, 1.0).toDouble();
          }
        }

        return ClipRect(
          child: Stack(
            children: <Widget>[
              Positioned(
                top: topPadding,
                left: 0.0,
                right: 0.0,
                height: height,
                child: Opacity(
                  opacity: opacity,
                  child: background,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  bool shouldRebuild(covariant _AppSliverHeaderDelegate oldDelegate) {
    return oldDelegate.maxExtent != maxExtent ||
        oldDelegate.minExtent != minExtent ||
        !identical(oldDelegate.background, background);
  }
}