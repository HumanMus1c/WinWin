import 'package:flutter/material.dart';
import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/utils/duration_utils.dart';
import 'package:winwin/utils/num_utils.dart';

/// 视频卡片 - 垂直布局
///
/// [videoItem] is dynamic so the card can render both
/// RcmdVideoItemAppModel and RcmdVideoItemModel without a compile-time
/// dependency on the model layer. Expected fields: cover, title, duration,
/// owner.name, stat.view, stat.danmu, rcmdReason, isFollowed.
class VideoCardV extends StatelessWidget {
  const VideoCardV({super.key, required this.videoItem, this.onTap});

  final dynamic videoItem;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final int duration = (videoItem.duration as num?)?.toInt() ?? 0;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                        src: videoItem.cover as String?,
                        width: maxWidth,
                        height: maxHeight,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                      ),
                      if (duration > 0)
                        Positioned(
                          right: 7,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              DurationUtils.formatDuration(duration),
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            _content(context),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    final String title = videoItem.title?.toString() ?? '';
    final String? rcmdReason = videoItem.rcmdReason as String?;
    final bool isFollowed = videoItem.isFollowed == true;
    final dynamic owner = videoItem.owner;
    final String ownerName = owner?.name?.toString() ?? '';

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(height: 1.38),
              ),
            ),
            _videoStat(theme),
            Row(
              spacing: 2,
              children: [
                if (rcmdReason != null) _badge(context, rcmdReason),
                if (isFollowed) _badge(context, '已关注'),
                Expanded(
                  child: Text(
                    ownerName,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    semanticsLabel: 'UP：$ownerName',
                    style: TextStyle(
                      height: 1.5,
                      fontSize: theme.textTheme.labelMedium?.fontSize,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _videoStat(ThemeData theme) {
    final dynamic stat = videoItem.stat;
    final Color color = theme.colorScheme.outline.withValues(alpha: 0.8);
    final TextStyle style = TextStyle(fontSize: 12, color: color);
    return Row(
      spacing: 2,
      children: [
        Icon(Icons.play_circle_outlined, size: 13, color: color),
        Text(
          NumUtils.formatNum((stat?.view as num?)?.toInt()),
          style: style,
        ),
        const SizedBox(width: 4),
        Icon(Icons.subtitles_outlined, size: 13, color: color),
        Text(
          NumUtils.formatNum((stat?.danmu as num?)?.toInt()),
          style: style,
        ),
      ],
    );
  }

  Widget _badge(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          height: 1.4,
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
