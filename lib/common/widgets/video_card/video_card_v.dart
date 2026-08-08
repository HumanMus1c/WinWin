import 'package:flutter/material.dart';
import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/common/widgets/p_badge.dart';
import 'package:winwin/pages/member/member_space_page.dart';
import 'package:winwin/theme/app_shapes.dart';
import 'package:winwin/utils/duration_utils.dart';
import 'package:winwin/utils/num_utils.dart';

/// 视频卡片 - 垂直布局（Phase 7.5.3 重构）。
///
/// [videoItem] is dynamic so the card can render both
/// RcmdVideoItemAppModel and RcmdVideoItemModel without a compile-time
/// dependency on the model layer. Expected fields: cover, title, duration,
/// owner.name, stat.view, stat.danmu, rcmdReason, isFollowed, bvid.
///
/// Phase 7.5.3 改进：
/// - 圆角统一通过 [AppShapes] 解析（三风格热切换）。
/// - 时长角标 / rcmdReason 角标改用 [PBadge]。
/// - `withOpacity` → `withValues(alpha:)`（避免 Flutter 弃用警告）。
/// - [heroTag] 支持封面→详情页 Hero 共享元素转场。
class VideoCardV extends StatelessWidget {
  const VideoCardV({
    super.key,
    required this.videoItem,
    this.onTap,
    this.heroTag,
  });

  final dynamic videoItem;
  final VoidCallback? onTap;

  /// Hero 共享元素 tag（非空时启用封面转场）。建议传 `'cover_$bvid'`。
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final int duration = (videoItem.duration as num?)?.toInt() ?? 0;
    final shapes = Theme.of(context).extension<AppShapes>() ?? AppShapes.ios;
    final radius = shapes.medium;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.all(radius),
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
                        borderRadius: BorderRadius.vertical(
                          top: radius,
                        ),
                        heroTag: heroTag,
                      ),
                      if (duration > 0)
                        Positioned(
                          right: 7,
                          bottom: 6,
                          child: PBadge(
                            text: DurationUtils.formatDuration(duration),
                            type: PBadgeType.duration,
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
                if (rcmdReason != null)
                  PBadge(text: rcmdReason, type: PBadgeType.badge),
                if (isFollowed)
                  PBadge(text: '已关注', type: PBadgeType.badge),
                Flexible(
                  child: GestureDetector(
                    onTap: () {
                      final mid = owner?.mid;
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
}
