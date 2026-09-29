import 'package:material_ui/material_ui.dart';
import 'package:winwin/common/skeleton/skeleton.dart';
import 'package:winwin/theme/app_shapes.dart';

/// Skeleton placeholder for the vertical video card.
///
/// 结构严格对齐 [VideoCardV]：静态外壳复用 [Card] 与 [AppShapes] 圆角，
/// 仅内部封面图片、标题行及 UP 昵称展示 Shimmer 骨架动画，
/// 消除网络数据到达替换时的卡片尺寸与圆角跳动（Zero Layout Shift）。
class VideoCardVSkeleton extends StatelessWidget {
  const VideoCardVSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shapes = theme.extension<AppShapes>() ?? AppShapes.material3;
    final radius = shapes.medium;
    final blockColor = skeletonBlockColor(context);

    return RepaintBoundary(
      child: Card(
        child: Skeleton(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 10,
                child: ClipRRect(
                  borderRadius: BorderRadius.vertical(top: radius),
                  child: Container(color: blockColor),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 12,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: blockColor,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Container(
                              height: 12,
                              width: 110,
                              decoration: BoxDecoration(
                                color: blockColor,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: blockColor,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            height: 11,
                            width: 70,
                            decoration: BoxDecoration(
                              color: blockColor,
                              borderRadius: BorderRadius.circular(3),
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
        ),
      ),
    );
  }
}

