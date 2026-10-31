import 'dart:math';

import 'package:flutter_miuix/miuix.dart' show MiuixCard, MiuixPressFeedbackType, MiuixPressable;
import 'package:flutter/widgets.dart';
import 'package:winwin/common/skeleton/skeleton.dart';
import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/common/widgets/p_badge.dart';
import 'package:winwin/common/widgets/video_card/video_card_adapter.dart';
import 'package:winwin/common/widgets/video_card/video_card_info.dart';
import 'package:winwin/common/widgets/video_card/video_context_menu.dart';
import 'package:winwin/common/widgets/video_card/video_cover_stat_badge.dart';
import 'package:winwin/core/demo/demo_overrides.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/pages/member/member_space_page.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/utils/duration_utils.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/core/shell/app_routes.dart';

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
    this.showOwner = true,
    this.showMenu = true,
    this.showStat = true,
    this.showPublishTime = false,
    this.enableContextMenu = true,
    this.shrinkWrap = false,
  });

  final dynamic videoItem;
  final VoidCallback? onTap;

  /// Hero 共享元素 tag（非空时启用封面转场）。建议传 `'cover_$bvid'`。
  final Object? heroTag;

  /// 卡片移除回调（如不感兴趣、拉黑 UP 主后触发列表局部移除）。
  final VoidCallback? onRemove;

  /// 是否展示底部 UP 胶囊（用户空间内可关闭，避免重复展示空间主人）。
  final bool showOwner;

  /// 是否展示右下角「更多」菜单。
  final bool showMenu;

  /// 是否在封面左下角展示播放 / 弹幕数角标。
  final bool showStat;

  /// 是否在底栏展示发布时间（用户空间投稿 / 点赞场景）。
  final bool showPublishTime;

  /// 是否响应右键 / 长按卡片菜单（用户空间等无操作场景可关闭）。
  final bool enableContextMenu;

  /// 是否按内容高度收缩（聊天消息等无固定网格高度的宿主）。
  ///
  /// 网格宿主为 false：标题区用 [Expanded] 吃掉固定瓦片高度；
  /// 自由高度宿主为 true：整卡按封面 + 标题 + 底栏自然高度排列。
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final data = VideoCardData.from(videoItem);
    final shapes = AppThemeHost.of(context).shapes;
    final radius = shapes.medium;

    // 演示模式：卡片保留完整交互（左键进入详情 / 右键菜单），
    // 文本与封面角标换为静态占位（无云端数据）。
    return ValueListenableBuilder<bool>(
      valueListenable: Pref.demoModeNotifier,
      builder: (context, demo, _) => RepaintBoundary(
        child: MiuixCard(
          child: GestureDetector(
            onSecondaryTapUp: enableContextMenu
                ? (details) {
                    showVideoContextMenu(
                      context: context,
                      position: details.globalPosition,
                      data: data,
                      videoItem: videoItem,
                      onRemove: onRemove,
                    );
                  }
                : null,
            onLongPressStart: enableContextMenu
                ? (details) {
                    showVideoContextMenu(
                      context: context,
                      position: details.globalPosition,
                      data: data,
                      videoItem: videoItem,
                      onRemove: onRemove,
                    );
                  }
                : null,
            child: MiuixPressable(
            feedbackType: MiuixPressFeedbackType.sink,
            sinkAmount: 0.98,
            onPressed: onTap,
            borderRadius: BorderRadius.all(radius),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
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
                          if (demo || data.duration > 0)
                            Positioned(
                              right: 7,
                              bottom: 6,
                              child: PBadge(
                                text: demo
                                    ? DurationUtils.formatDuration(
                                        DemoOverrides.durationSeconds(
                                          'demo.vcard.${data.bvid ?? ''}',
                                        ),
                                      )
                                    : DurationUtils.formatDuration(
                                        data.duration,
                                      ),
                                type: PBadgeType.duration,
                              ),
                            ),
                          if (demo || showStat)
                            Positioned(
                              left: 7,
                              bottom: 6,
                              child: VideoCoverStatBadge(
                              playCount: demo
                                  ? DemoOverrides.count(
                                      'demo.vplay.${data.bvid ?? ''}',
                                      min: 1000,
                                      max: 9999999,
                                    )
                                  : data.playCount,
                              danmakuCount: demo
                                  ? DemoOverrides.count(
                                      'demo.vdm.${data.bvid ?? ''}',
                                      min: 10,
                                      max: 99999,
                                    )
                                  : data.danmakuCount,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                _content(context, data, demo: demo),
              ],
            ),
          
            )
          ),
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    VideoCardData data, {
    required bool demo,
  }) {
    final tokens = AppThemeHost.of(context);
    final String title = data.title;
    final String? rcmdReason = data.rcmdReason;
    final bool isFollowed = data.isFollowed;
    final String ownerName = data.ownerName;
    final int? mid = data.mid;

    final Widget titleWidget = demo
        ? const Align(
            alignment: Alignment.topLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLine(width: double.infinity, height: 13),
                SizedBox(height: 6),
                SkeletonLine(width: 150, height: 13),
              ],
            ),
          )
        : Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(height: 1.38),
          );

    final Widget info = Padding(
      padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
        children: [
          if (shrinkWrap)
            titleWidget
          else
            Expanded(child: titleWidget),
          Row(
              spacing: 2,
              children: [
                if (demo) ...[
                  // 与正常模式一致：仅"已关注"时显示该胶囊（不存在"未关注"胶囊）。
                  if (Random((data.bvid ?? '').hashCode).nextBool())
                    const PBadge(
                      text: '已关注',
                      type: PBadgeType.status,
                    ),
                  PBadge(
                    text: const ['高播放', '1万点赞', '热门', '宝藏新作'][
                        Random((data.bvid ?? '').hashCode ^ 5).nextInt(4)],
                    type: PBadgeType.highlight,
                  ),
                  if (showOwner)
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.colors.secondaryContainer
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AppIcon(
                                AppIcons.profile(),
                                size: appRowIconSizeInherited(context),
                                color: tokens.colors.outline,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                kDemoDisplayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  height: 1.5,
                                  fontSize:
                                      tokens.text.labelMedium?.fontSize,
                                  color: tokens.colors.outline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                ] else ...[
                  if (rcmdReason != null && rcmdReason.isNotEmpty)
                    PBadge(text: rcmdReason, type: PBadgeType.highlight),
                  if (isFollowed)
                    const PBadge(text: '已关注', type: PBadgeType.status),
                  if (showPublishTime && data.publishedAt != null)
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _publishTimePill(context, tokens, data),
                      ),
                    )
                  else if (showOwner && ownerName.isNotEmpty)
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: GestureDetector(
                          onTap: () {
                            if (mid != null && mid > 0) {
                              Navigator.push(
                                context,
                                AppRoute(
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
                              color: tokens.colors.secondaryContainer
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
                                fontSize: tokens.text.labelMedium?.fontSize,
                                color: tokens.colors.outline,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                ],
                if (showMenu)
                  VideoPopupMenu(
                    data: data,
                    videoItem: videoItem,
                    onRemove: onRemove,
                  ),
              ],
            ),
          ],
        ),
      );

    return shrinkWrap ? info : Expanded(child: info);
  }

  /// 用户空间底栏发布时间胶囊：与 UP 胶囊同壳，仅换日历图标 + 时间文案。
  Widget _publishTimePill(
    BuildContext context,
    AppTokens tokens,
    VideoCardData data,
  ) {
    final text = VideoCardInfoText.publishedAt(data.publishedAt);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: tokens.colors.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(
            AppIcons.calendar(),
            size: appRowIconSizeInherited(context),
            color: tokens.colors.outline,
          ),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              semanticsLabel: text,
              style: TextStyle(
                height: 1.5,
                fontSize: tokens.text.labelMedium?.fontSize,
                color: tokens.colors.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
