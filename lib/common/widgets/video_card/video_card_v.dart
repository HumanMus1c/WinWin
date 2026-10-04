import 'package:material_ui/material_ui.dart';
import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/common/widgets/p_badge.dart';
import 'package:winwin/common/widgets/video_card/video_card_adapter.dart';
import 'package:winwin/common/widgets/video_card/video_context_menu.dart';
import 'package:winwin/pages/member/member_space_page.dart';
import 'package:winwin/theme/app_shapes.dart';
import 'package:winwin/utils/duration_utils.dart';
import 'package:winwin/utils/num_utils.dart';

/// 视频卡片 - 垂直布局（高性能适配版）。
///
/// 通过 [VideoCardData.from] 进行强类型模型适配，彻底消除每张卡片调用数十次
/// `try-catch` 导致的 `NoSuchMethodError` 与闭包构造开销。
/// 外层包裹 [RepaintBoundary] 以实现高效重绘隔离。
class VideoCardV extends StatelessWidget {
  const VideoCardV({
    super.key,
    required this.videoItem,
    this.onTap,
    this.heroTag,
    this.onRemove,
  });

  final dynamic videoItem;
  final VoidCallback? onTap;

  /// Hero 共享元素 tag（非空时启用封面转场）。建议传 `'cover_$bvid'`。
  final Object? heroTag;

  /// 卡片移除回调（如不感兴趣、拉黑 UP 主后触发列表局部移除）。
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final data = VideoCardData.from(videoItem);
    final shapes = Theme.of(context).extension<AppShapes>() ?? AppShapes.miuix;
    final radius = shapes.medium;
    Offset? lastTapPosition;

    return RepaintBoundary(
      child: Card(
        child: InkWell(
          onTap: onTap,
          onSecondaryTapDown: (details) {
            lastTapPosition = details.globalPosition;
          },
          onSecondaryTapUp: (details) {
            showVideoContextMenu(
              context: context,
              position: details.globalPosition,
              data: data,
              videoItem: videoItem,
              onRemove: onRemove,
            );
          },
          onLongPress: () {
            if (lastTapPosition != null) {
              showVideoContextMenu(
                context: context,
                position: lastTapPosition!,
                data: data,
                videoItem: videoItem,
                onRemove: onRemove,
              );
            }
          },
          borderRadius: BorderRadius.all(radius),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 10,
                child: LayoutBuilder(
                  builder: (context, boxConstraints) {
                    final double maxWidth = boxConstraints.maxWidth;
                    final double maxHeight = boxConstraints.maxHeight;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        NetworkImgLayer(
                          src: data.cover,
                          width: maxWidth,
                          height: maxHeight,
                          borderRadius: BorderRadius.vertical(
                            top: radius,
                          ),
                          heroTag: heroTag,
                        ),
                        if (data.duration > 0)
                          Positioned(
                            right: 7,
                            bottom: 6,
                            child: PBadge(
                              text: DurationUtils.formatDuration(data.duration),
                              type: PBadgeType.duration,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              _content(context, data),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, VideoCardData data) {
    final theme = Theme.of(context);
    final String title = data.title;
    final String? rcmdReason = data.rcmdReason;
    final bool isFollowed = data.isFollowed;
    final String ownerName = data.ownerName;
    final int? mid = data.mid;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(height: 1.38),
              ),
            ),
            _videoStat(theme, data),
            Row(
              spacing: 2,
              children: [
                if (rcmdReason != null && rcmdReason.isNotEmpty)
                  PBadge(text: rcmdReason, type: PBadgeType.highlight),
                if (isFollowed)
                  const PBadge(text: '已关注', type: PBadgeType.status),
                if (ownerName.isNotEmpty)
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: GestureDetector(
                        onTap: () {
                          if (mid != null && mid > 0) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MemberSpacePage(mid: mid),
                              ),
                            );
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondaryContainer
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            ownerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            semanticsLabel: 'UP：$ownerName',
                            style: TextStyle(
                              height: 1.5,
                              fontSize: theme.textTheme.labelMedium?.fontSize,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  const Spacer(),
                VideoPopupMenu(
                  data: data,
                  videoItem: videoItem,
                  onRemove: onRemove,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _videoStat(ThemeData theme, VideoCardData data) {
    final Color color = theme.colorScheme.outline.withValues(alpha: 0.8);
    final TextStyle style = TextStyle(fontSize: 12, color: color);
    return Row(
      spacing: 2,
      children: [
        Icon(Icons.play_circle_outlined, size: 13, color: color),
        Text(
          NumUtils.formatNum(data.playCount),
          style: style,
        ),
        const SizedBox(width: 4),
        Icon(Icons.subtitles_outlined, size: 13, color: color),
        Text(
          NumUtils.formatNum(data.danmakuCount),
          style: style,
        ),
      ],
    );
  }
}
