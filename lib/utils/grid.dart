import 'dart:math';

import 'package:flutter/rendering.dart';
import 'package:winwin/theme/style.dart';

/// 网格布局辅助代理集（对齐 PiliPlus Grid 与 BiliPai 响应式多列规范）。
abstract final class Grid {
  static const double smallCardWidth = 240.0;

  /// 纵向卡片网格代理（如推荐流/热门流/关注流/动态视频流），适用于 [VideoCardV]。
  static SliverGridDelegateWithExtentAndRatio videoCardVDelegate({
    double maxCrossAxisExtent = 240.0,
    double mainAxisExtent = 90.0,
    double childAspectRatio = Style.aspectRatio,
    double mainAxisSpacing = Style.cardSpace,
    double crossAxisSpacing = Style.cardSpace,
  }) =>
      SliverGridDelegateWithExtentAndRatio(
        maxCrossAxisExtent: maxCrossAxisExtent,
        mainAxisSpacing: mainAxisSpacing,
        crossAxisSpacing: crossAxisSpacing,
        childAspectRatio: childAspectRatio,
        mainAxisExtent: mainAxisExtent,
      );

  /// 横向卡片网格代理（如收藏夹详情视频列表/历史记录等），适用于 [VideoCardH]。
  static SliverGridDelegateWithMaxCrossAxisExtent videoCardHDelegate({
    double maxCrossAxisExtent = 420.0,
    double mainAxisExtent = 108.0,
    double mainAxisSpacing = Style.cardSpace,
    double crossAxisSpacing = Style.cardSpace,
  }) =>
      SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxCrossAxisExtent,
        mainAxisExtent: mainAxisExtent,
        mainAxisSpacing: mainAxisSpacing,
        crossAxisSpacing: crossAxisSpacing,
      );

  /// 文件夹卡片网格代理（如我的收藏夹列表），适用于文件夹封面卡片。
  static SliverGridDelegateWithMaxCrossAxisExtent folderCardDelegate({
    double maxCrossAxisExtent = 380.0,
    double mainAxisExtent = 104.0,
    double mainAxisSpacing = Style.cardSpace,
    double crossAxisSpacing = Style.cardSpace,
  }) =>
      SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxCrossAxisExtent,
        mainAxisExtent: mainAxisExtent,
        mainAxisSpacing: mainAxisSpacing,
        crossAxisSpacing: crossAxisSpacing,
      );

  /// 全动态多列卡片网格代理（如「全部」动态流），适用于 [_DynCard]。
  static SliverGridDelegateWithMaxCrossAxisExtent dynCardDelegate({
    double maxCrossAxisExtent = 520.0,
    double? mainAxisExtent,
    double mainAxisSpacing = Style.cardSpace,
    double crossAxisSpacing = Style.cardSpace,
  }) =>
      SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxCrossAxisExtent,
        mainAxisExtent: mainAxisExtent,
        mainAxisSpacing: mainAxisSpacing,
        crossAxisSpacing: crossAxisSpacing,
      );
}

/// A [SliverGridDelegate] that lays out tiles with a maximum cross-axis
/// extent while honoring both [childAspectRatio] and an additional fixed
/// [mainAxisExtent] (added on top of the ratio-derived extent).
class SliverGridDelegateWithExtentAndRatio extends SliverGridDelegate {
  /// Creates a delegate that makes grid layouts with tiles that have a
  /// maximum cross-axis extent.
  ///
  /// The [maxCrossAxisExtent], [mainAxisExtent], [mainAxisSpacing],
  /// and [crossAxisSpacing] arguments must not be negative.
  /// The [childAspectRatio] argument must be greater than zero.
  SliverGridDelegateWithExtentAndRatio({
    required this.maxCrossAxisExtent,
    this.mainAxisSpacing = 0.0,
    this.crossAxisSpacing = 0.0,
    this.childAspectRatio = 1.0,
    this.mainAxisExtent = 0.0,
  }) : assert(maxCrossAxisExtent > 0),
       assert(mainAxisSpacing >= 0),
       assert(crossAxisSpacing >= 0),
       assert(childAspectRatio > 0);

  /// The maximum extent of tiles in the cross axis.
  ///
  /// This delegate will select a cross-axis extent for the tiles that is as
  /// large as possible subject to the following conditions:
  ///
  ///  - The extent evenly divides the cross-axis extent of the grid.
  ///  - The extent is at most [maxCrossAxisExtent].
  final double maxCrossAxisExtent;

  /// The number of logical pixels between each child along the main axis.
  final double mainAxisSpacing;

  /// The number of logical pixels between each child along the cross axis.
  final double crossAxisSpacing;

  /// The ratio of the cross-axis to the main-axis extent of each child.
  final double childAspectRatio;

  /// The extent of each tile in the main axis. It is added after
  /// [childAspectRatio] is used.
  final double mainAxisExtent;

  bool _debugAssertIsValid(double crossAxisExtent) {
    assert(crossAxisExtent > 0.0);
    assert(maxCrossAxisExtent > 0.0);
    assert(mainAxisSpacing >= 0.0);
    assert(crossAxisSpacing >= 0.0);
    assert(childAspectRatio > 0.0);
    return true;
  }

  SliverGridLayout? layoutCache;
  double? crossAxisExtentCache;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    // Invoked before each frame.
    assert(_debugAssertIsValid(constraints.crossAxisExtent));
    if (layoutCache != null &&
        constraints.crossAxisExtent == crossAxisExtentCache) {
      return layoutCache!;
    }
    crossAxisExtentCache = constraints.crossAxisExtent;
    int crossAxisCount =
        ((constraints.crossAxisExtent - crossAxisSpacing) /
                (maxCrossAxisExtent + crossAxisSpacing))
            .ceil();
    // Ensure a minimum count of 1, can be zero and result in an infinite
    // extent below when the window size is 0.
    crossAxisCount = max(1, crossAxisCount);
    final double usableCrossAxisExtent = max(
      0.0,
      constraints.crossAxisExtent - crossAxisSpacing * (crossAxisCount - 1),
    );
    final double childCrossAxisExtent =
        usableCrossAxisExtent / crossAxisCount;
    final double childMainAxisExtent =
        childCrossAxisExtent / childAspectRatio + mainAxisExtent;
    return layoutCache = SliverGridRegularTileLayout(
      crossAxisCount: crossAxisCount,
      mainAxisStride: childMainAxisExtent + mainAxisSpacing,
      crossAxisStride: childCrossAxisExtent + crossAxisSpacing,
      childMainAxisExtent: childMainAxisExtent,
      childCrossAxisExtent: childCrossAxisExtent,
      reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
    );
  }

  @override
  bool shouldRelayout(SliverGridDelegateWithExtentAndRatio oldDelegate) {
    final flag =
        oldDelegate.maxCrossAxisExtent != maxCrossAxisExtent ||
        oldDelegate.mainAxisSpacing != mainAxisSpacing ||
        oldDelegate.crossAxisSpacing != crossAxisSpacing ||
        oldDelegate.childAspectRatio != childAspectRatio ||
        oldDelegate.mainAxisExtent != mainAxisExtent;
    if (flag) layoutCache = null;
    return flag;
  }
}
