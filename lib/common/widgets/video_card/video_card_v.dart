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
import 'package:winwin/theme/app_typography.dart';
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
    this.showPublishTime = true,
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

  /// 是否在 UP 行右侧展示发布时间（`showOwner` 关闭时仅显示时间）。
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
                          // 封面底部：播放 / 弹幕 / 点赞三合胶囊 + 时长胶囊。
                          // 两枚胶囊按标题字号渲染，放不下时自动回落字号避让。
                          Positioned(
                            left: 7,
                            right: 7,
                            bottom: 6,
                            child: VideoCoverStatBar(
                              showStat: demo || showStat,
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
                                      min: 1000,
                                      max: 9999,
                                    )
                                  : data.danmakuCount,
                              likeCount: demo
                                  ? DemoOverrides.count(
                                      'demo.vlike.${data.bvid ?? ''}',
                                      min: 1000,
                                      max: 99999,
                                    )
                                  : data.likeCount,
                              durationText: demo || data.duration > 0
                                  ? DurationUtils.formatDuration(
                                      demo
                                          ? DemoOverrides.durationSeconds(
                                              'demo.vcard.${data.bvid ?? ''}',
                                            )
                                          : data.duration,
                                    )
                                  : '',
                            ),
                          ),
                          // 「热门」官方章现在交给底部信息行；封面只留其他定性理由。
                          if (_showReasonOnCover(_reasonOf(data, demo)))
                            Positioned(
                              left: 7,
                              top: 6,
                              child: PBadge(
                                text: _reasonOf(data, demo)!,
                                type: PBadgeType.highlight,
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
    final bool isFollowed = data.isFollowed;
    final String ownerName = data.ownerName;
    final int? mid = data.mid;

    /// 与标题同源的名义字号（标题自身不设 fontSize，随基底继承）。
    final double titleFontSize =
        DefaultTextStyle.of(context).style.fontSize ?? appBaseFontSize;
    final String? officialReason = _reasonOf(data, demo);

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
            softWrap: true,
            overflow: TextOverflow.ellipsis,
            textWidthBasis: TextWidthBasis.parent,
            style: const TextStyle(height: 1.38),
          );

    final String publishedText =
        VideoCardInfoText.publishedShort(data.publishedAt);

    // UP 行：UP + 已关注 + 发布时间（发布日期不再占独立整行）。
    final Widget ownerRow;
    if (demo) {
      ownerRow = Row(
        children: [
          if (showOwner) ...[
            AppIcon(
              AppIcons.profile(),
              size: appRowIconSizeInherited(context),
              color: tokens.colors.outline,
            ),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                kDemoDisplayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens.text.labelSmall?.copyWith(
                  color: tokens.colors.outline,
                ),
              ),
            ),
            if (Random((data.bvid ?? '').hashCode).nextBool()) ...[
              const SizedBox(width: 4),
              const PBadge(text: '已关注', type: PBadgeType.followed),
            ],
          ] else
            const Spacer(),
          if (showPublishTime) ...[
            const SizedBox(width: 6),
            const SkeletonLine(width: 36, height: 10),
          ],
        ],
      );
    } else {
      ownerRow = Row(
        children: [
          if (showOwner && ownerName.isNotEmpty)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
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
                child: Row(
                  children: [
                    AppIcon(
                      AppIcons.profile(),
                      size: appRowIconSizeInherited(context),
                      color: tokens.colors.outline,
                    ),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        ownerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        semanticsLabel: 'UP：$ownerName',
                        style: tokens.text.labelSmall?.copyWith(
                          color: tokens.colors.outline,
                        ),
                      ),
                    ),
                    if (isFollowed) ...[
                      const SizedBox(width: 4),
                      const PBadge(text: '已关注', type: PBadgeType.followed),
                    ],
                  ],
                ),
              ),
            )
          else
            const Spacer(),
          if (showPublishTime && publishedText.isNotEmpty) ...[
            const SizedBox(width: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  AppIcons.calendar(),
                  size: 11,
                  color: tokens.colors.outline,
                ),
                const SizedBox(width: 2),
                Text(
                  publishedText,
                  maxLines: 1,
                  style: tokens.text.labelSmall?.copyWith(
                    color: tokens.colors.outline,
                    fontSize: 11,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ],
        ],
      );
    }

    // 热门行：官方「热门」章（仅 rcmd_reason 明确为「热门」时显示）+ 更多。
    // 点赞量已并入封面统计胶囊，这里不再重复。
    final Widget hotRow = Row(
      spacing: 2,
      children: [
        if (_isOfficialHotReason(officialReason))
          PBadge(
            text: '热门',
            type: PBadgeType.highlight,
            fontSize: titleFontSize,
            padding: EdgeInsets.symmetric(
              horizontal: titleFontSize * 0.42,
              vertical: titleFontSize * 0.14,
            ),
          ),
        const Spacer(),
        if (showMenu)
          VideoPopupMenu(
            data: data,
            videoItem: videoItem,
            onRemove: onRemove,
          ),
      ],
    );

    final Widget info = Padding(
      padding: const EdgeInsets.fromLTRB(6, 5, 8, 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
        children: [
          if (shrinkWrap)
            titleWidget
          else
            Expanded(child: titleWidget),
          ownerRow,
          const SizedBox(height: 2),
          hotRow,
        ],
      ),
    );

    return shrinkWrap ? info : Expanded(child: info);
  }

  /// 卡片展示用的推荐理由：演示模式取稳定随机占位，真实数据取接口原值。
  static String? _reasonOf(VideoCardData data, bool demo) => demo
      ? const ['热门', '高播放', '宝藏新作'][
          Random((data.bvid ?? '').hashCode ^ 5).nextInt(3)]
      : data.rcmdReason;

  /// 是否官方接口明确打上「热门」章。
  ///
  /// 仅认 `rcmd_reason` 原值为「热门」；「百万播放 / 人气飙升 / 高播放」等
  /// 其他定性理由仍留在封面左上角，不在底部重复。
  static bool _isOfficialHotReason(String? reason) =>
      reason != null && reason.trim() == '热门';

  /// 封面左上角只放**定性**推荐理由（高播放 / 百万播放 …）。
  ///
  /// 点赞量理由（如「3万点赞」）改由封面统计胶囊展示（数据源改用 `stat.like`
  /// 的精确值）；关注态理由由 UP 行的「已关注」徽章展示；「热门」章移到
  /// 底部官方章位置——同一信息只在卡上出现一次。
  static bool _showReasonOnCover(String? reason) {
    if (reason == null || reason.isEmpty) return false;
    if (_isOfficialHotReason(reason)) return false;
    if (reason.contains('赞')) return false;
    return !const {'已关注', '新关注'}.contains(reason);
  }
}
