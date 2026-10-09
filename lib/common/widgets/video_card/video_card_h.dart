import 'package:flutter_miuix/miuix.dart' show MiuixCard, MiuixPressable;
import 'package:material_ui/material_ui.dart';

import 'package:winwin/theme/app_colors.dart';
import 'package:winwin/common/skeleton/skeleton.dart';
import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/common/widgets/p_badge.dart';
import 'package:winwin/common/widgets/video_card/video_card_adapter.dart';
import 'package:winwin/common/widgets/video_card/video_context_menu.dart';
import 'package:winwin/common/widgets/video_card/video_cover_stat_badge.dart';
import 'package:winwin/core/demo/demo_overrides.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/utils/duration_utils.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/core/shell/app_theme_host.dart';

/// 视频卡片 - 水平布局（高性能适配版）。
///
/// 用于「稍后再看」/「历史记录」/「相关推荐」/「搜索结果列表」等
/// 横向列表场景。左侧封面（16:9 固定宽度）+ 右侧文本信息。
///
/// 通过 [VideoCardData.from] 进行强类型模型适配，彻底消除内部反复调用
/// `try-catch` 导致的 `NoSuchMethodError` 与闭包构造开销。
/// 外层包裹 [RepaintBoundary] 以实现高效重绘隔离。
class VideoCardH extends StatelessWidget {
  const VideoCardH({
    super.key,
    required this.videoItem,
    this.onTap,
    this.heroTag,
    this.coverWidth = 160,
    this.showStat = true,
    this.onRemove,
  });

  final dynamic videoItem;
  final VoidCallback? onTap;

  /// Hero 共享元素 tag（非空时启用封面转场）。
  final Object? heroTag;

  /// 封面宽度（默认 160，可按场景调整）。
  final double coverWidth;

  /// 是否显示播放/弹幕数统计。
  final bool showStat;

  /// 卡片移除回调（如不感兴趣、拉黑 UP 主后触发列表局部移除）。
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final data = VideoCardData.from(videoItem);
    final tokens = AppThemeHost.of(context);
    final shapes = tokens.shapes;
    final radius = shapes.medium;
    final int duration = data.duration;
    final double? progress = data.progress;
    Offset? lastTapPosition;

    // 演示模式：卡片保留完整交互（左键进入详情 / 右键菜单），
    // 文本与封面角标换为静态占位（无云端数据）。
    return ValueListenableBuilder<bool>(
      valueListenable: Pref.demoModeNotifier,
      builder: (context, demo, _) => RepaintBoundary(
        child: MiuixCard(
          child: GestureDetector(
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
            child: MiuixPressable(
            onPressed: onTap,
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
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 左：封面缩略图
                  ClipRRect(
                    borderRadius: BorderRadius.all(radius),
                    child: SizedBox(
                      width: coverWidth,
                      height: coverWidth * 9 / 16,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: NetworkImgLayer(
                              src: data.cover,
                              width: coverWidth,
                              height: coverWidth * 9 / 16,
                              borderRadius: BorderRadius.all(radius),
                              heroTag: heroTag,
                            ),
                          ),
                          if (demo || duration > 0)
                            Positioned(
                              right: 4,
                              bottom: 4,
                              child: PBadge(
                                text: demo
                                    ? DurationUtils.formatDuration(
                                        DemoOverrides.durationSeconds(
                                          'demo.hcard.${data.bvid ?? ''}',
                                        ),
                                      )
                                    : DurationUtils.formatDuration(duration),
                                type: PBadgeType.duration,
                              ),
                            ),
                          if (demo || showStat)
                            Positioned(
                              left: 4,
                              bottom: 4,
                              child: VideoCoverStatBadge(
                                playCount: demo
                                    ? DemoOverrides.count(
                                        'demo.hplay.${data.bvid ?? ''}',
                                        min: 1000,
                                        max: 9999999,
                                      )
                                    : data.playCount,
                                danmakuCount: demo
                                    ? DemoOverrides.count(
                                        'demo.hdm.${data.bvid ?? ''}',
                                        min: 10,
                                        max: 99999,
                                      )
                                    : data.danmakuCount,
                              ),
                            ),
                          if (progress != null && progress > 0)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: LinearProgressIndicator(
                                value: progress.clamp(0.0, 1.0),
                                minHeight: 2,
                                backgroundColor: AppColors.transparent,
                                valueColor: AlwaysStoppedAnimation(
                                  tokens.colors.primary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 右：标题 + UP + 统计
                  Expanded(child: _buildTextContent(tokens, data, demo: demo)),
                ],
              ),
            ),
          
            )
          ),
        ),
      ),
    );
  }

  Widget _buildTextContent(
    AppTokens tokens,
    VideoCardData data, {
    required bool demo,
  }) {
    final String title = data.title;
    final cs = tokens.colors;
    final String ownerName = data.ownerName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        demo
            ? const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonLine(width: double.infinity, height: 13),
                  SizedBox(height: 6),
                  SkeletonLine(width: 150, height: 13),
                ],
              )
            : Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: tokens.text.bodyMedium?.copyWith(height: 1.35),
              ),
        const SizedBox(height: 6),
        Row(
          children: [
            if (demo) ...[
              AppIcon(AppIcons.profile(), size: 13, color: cs.outline),
              const SizedBox(width: 3),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    kDemoDisplayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        tokens.text.labelSmall?.copyWith(color: cs.outline),
                  ),
                ),
              ),
            ] else ...[
              if (ownerName.isNotEmpty) ...[
                AppIcon(AppIcons.profile(), size: 13, color: cs.outline),
                const SizedBox(width: 3),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      ownerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          tokens.text.labelSmall?.copyWith(color: cs.outline),
                    ),
                  ),
                ),
              ] else
                const Spacer(),
            ],
            VideoPopupMenu(
              data: data,
              videoItem: videoItem,
              onRemove: onRemove,
            ),
          ],
        ),
      ],
    );
  }
}
