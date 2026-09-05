import 'package:flutter/material.dart';
import 'package:winwin/common/skeleton/skeleton.dart';
import 'package:winwin/theme/app_shapes.dart';

/// Skeleton placeholder for horizontal video cards ([VideoCardH]).
///
/// 结构对标 [VideoCardH]：
/// - 静态 [Card] 容器与 [AppShapes] 圆角、内边距严格一致；
/// - 仅封面图、标题两行文字、UP 昵称及播放量指标展示 Shimmer 动画；
/// - 支持通过 [inCard] 控制是否包裹 Card 外壳；
/// - 支持自定义 [coverWidth]（默认 140）。
class VideoCardHSkeleton extends StatelessWidget {
  const VideoCardHSkeleton({
    super.key,
    this.coverWidth = 140,
    this.coverHeight,
    this.inCard = true,
  });

  final double coverWidth;
  final double? coverHeight;
  final bool inCard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shapes = theme.extension<AppShapes>() ?? AppShapes.ios;
    final radius = shapes.medium;
    final blockColor = skeletonBlockColor(context);
    final effectiveHeight = coverHeight ?? (coverWidth * 9 / 16);

    final content = Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧封面缩略图骨架
          ClipRRect(
            borderRadius: BorderRadius.all(radius),
            child: SizedBox(
              width: coverWidth,
              height: effectiveHeight,
              child: Container(color: blockColor),
            ),
          ),
          const SizedBox(width: 10),
          // 右侧文本信息骨架
          Expanded(
            child: SizedBox(
              height: effectiveHeight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题两行骨架
                  Container(
                    height: 13,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: blockColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 13,
                    width: 100,
                    decoration: BoxDecoration(
                      color: blockColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const Spacer(),
                  // UP 昵称骨架
                  Container(
                    height: 11,
                    width: 80,
                    decoration: BoxDecoration(
                      color: blockColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // 数据行骨架
                  Row(
                    children: [
                      Container(
                        height: 10,
                        width: 44,
                        decoration: BoxDecoration(
                          color: blockColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        height: 10,
                        width: 44,
                        decoration: BoxDecoration(
                          color: blockColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    final shimmerContent = Skeleton(child: content);

    if (!inCard) {
      return RepaintBoundary(child: shimmerContent);
    }

    return RepaintBoundary(
      child: Card(
        child: shimmerContent,
      ),
    );
  }
}
