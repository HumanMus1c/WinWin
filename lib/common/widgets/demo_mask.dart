import 'dart:math';

import 'package:flutter_miuix/miuix.dart' show MiuixCard, MiuixPressFeedbackType, MiuixPressable;
import 'package:flutter/widgets.dart';

import 'package:winwin/common/skeleton/skeleton.dart';
import 'package:winwin/common/widgets/p_badge.dart';
import 'package:winwin/common/widgets/video_card/video_card_adapter.dart';
import 'package:winwin/common/widgets/video_card/video_context_menu.dart';
import 'package:winwin/common/widgets/video_card/video_cover_stat_badge.dart';
import 'package:winwin/core/demo/demo_overrides.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/utils/duration_utils.dart';
import 'package:winwin/core/shell/app_theme_host.dart';

/// 演示模式：演示卡片右键/长按"更多选项"菜单（使用占位数据，不触发云端写操作）。
void _showDemoCardMenu(BuildContext context, Offset position, int seed) {
  showVideoContextMenu(
    context: context,
    position: position,
    data: VideoCardData(
      bvid: 'BV1demo$seed',
      aid: 0,
      mid: 10000,
      cover: 'https://demo.winwin.local/cover_$seed.jpg',
      ownerName: kDemoDisplayName,
      title: '演示视频',
    ),
  );
}

/// 演示模式内容遮罩：演示开启时整块替换为 [skeleton]。
///
/// 用法：
/// ```dart
/// DemoMask(
///   skeleton: () => _buildSkeleton(),
///   child: () => switch (state) { ... },
/// )
/// ```
/// 演示模式下无论页面处于 Loading / Success / Error，均显示骨架
/// （统一观感，不泄露内容与错误信息）；关闭后立即按当前状态恢复真实内容。
class DemoMask extends StatelessWidget {
  const DemoMask({super.key, required this.skeleton, required this.child});

  /// 演示模式下显示的内容（通常为该页现有骨架屏）。
  final Widget Function() skeleton;

  /// 正常状态下显示的内容。
  final Widget Function() child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Pref.demoModeNotifier,
      builder: (context, demo, _) => demo ? skeleton() : child(),
    );
  }
}

/// 演示模式播放器遮罩：覆盖真实画面（视频帧 / 弹幕 / 直播画面）。
///
/// 纯视觉覆盖层：`IgnorePointer` 不拦截交互，不暂停、不改变播放状态；
/// 使用不透明渐变色块，保证截图不含任何真实画面。
class DemoVideoOverlay extends StatelessWidget {
  const DemoVideoOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = AppThemeHost.of(context).colors;
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cs.surfaceContainerHighest, cs.outlineVariant],
          ),
        ),
        alignment: Alignment.center,
        child: AppIcon(
          AppIcons.playCircleOutline(),
          size: 56,
          color: cs.onSurfaceVariant.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}

/// 演示模式：通用列表骨架（封面块 + 两行文本，近似卡片列表）。
class DemoListSkeleton extends StatelessWidget {
  const DemoListSkeleton({
    super.key,
    this.itemCount = 8,
    this.coverWidth = 150,
    this.coverHeight = 88,
  });

  final int itemCount;
  final double coverWidth;
  final double coverHeight;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(Style.safeSpace),
      itemCount: itemCount,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: Style.md),
        child: Skeleton(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: coverWidth, height: coverHeight),
              const SizedBox(width: Style.md),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonLine(width: double.infinity, height: 13),
                    SizedBox(height: 8),
                    SkeletonLine(width: 120, height: 11),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 演示模式：本地生成的竖版视频卡片（可交互，无云端数据）。
///
/// 封面灰色占位、标题灰色占位、作者统一为程序图标 + 程序名「WinWin」，
/// 时长/播放数/关注状态/热门胶囊等元素使用"控件美术素材 + 稳定随机值"。
class DemoVideoCard extends StatelessWidget {
  const DemoVideoCard({super.key, required this.seed, this.onTap});

  /// 稳定随机种子（通常为列表索引）。
  final int seed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final followed = Random(seed).nextBool();
    final hotLabel =
        const ['高播放', '1万点赞', '热门', '宝藏新作'][Random(seed ^ 5).nextInt(4)];
    final durationText = DurationUtils.formatDuration(
      DemoOverrides.durationSeconds('demo.card.$seed'),
    );

    return RepaintBoundary(
      child: MiuixCard(
        child: GestureDetector(
          onSecondaryTapUp: (details) =>
              _showDemoCardMenu(context, details.globalPosition, seed),
          onLongPressStart: (details) =>
              _showDemoCardMenu(context, details.globalPosition, seed),
          child: MiuixPressable(
          feedbackType: MiuixPressFeedbackType.sink,
          sinkAmount: 0.98,
          onPressed: onTap,
          borderRadius: BorderRadius.circular(Style.radiusMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 10,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Positioned.fill(
                      child: SkeletonBox(
                        width: double.infinity,
                        height: double.infinity,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(Style.radiusMd),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 7,
                      bottom: 6,
                      child: PBadge(
                        text: durationText,
                        type: PBadgeType.duration,
                      ),
                    ),
                    Positioned(
                      left: 7,
                      bottom: 6,
                      child: VideoCoverStatBadge(
                        playCount: DemoOverrides.count(
                          'demo.play.$seed',
                          min: 1000,
                          max: 9999999,
                        ),
                        danmakuCount: DemoOverrides.count(
                          'demo.dm.$seed',
                          min: 10,
                          max: 99999,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonLine(
                              width: double.infinity,
                              height: 13,
                            ),
                            SizedBox(height: 6),
                            SkeletonLine(width: 150, height: 13),
                          ],
                        ),
                      ),
                      Row(
                        spacing: 2,
                        children: [
                          // 与正常模式一致：仅"已关注"时显示该胶囊。
                          if (followed)
                            const PBadge(
                              text: '已关注',
                              type: PBadgeType.status,
                            ),
                          PBadge(
                            text: hotLabel,
                            type: PBadgeType.highlight,
                          ),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.secondaryContainer
                                      .withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(100),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    AppIcon(
                                      AppIcons.profile(),
                                      size: 12,
                                      color: cs.outline,
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
                                        color: cs.outline,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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
        
          )
        ),
      ),
    );
  }
}

/// 演示模式：本地生成的横版视频卡片（相关推荐/列表场景，可交互）。
class DemoVideoCardH extends StatelessWidget {
  const DemoVideoCardH({super.key, required this.seed, this.onTap});

  final int seed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final durationText = DurationUtils.formatDuration(
      DemoOverrides.durationSeconds('demo.hcard.$seed'),
    );

    return RepaintBoundary(
      child: MiuixCard(
        child: GestureDetector(
          onSecondaryTapUp: (details) =>
              _showDemoCardMenu(context, details.globalPosition, seed),
          onLongPressStart: (details) =>
              _showDemoCardMenu(context, details.globalPosition, seed),
          child: MiuixPressable(
          feedbackType: MiuixPressFeedbackType.sink,
          sinkAmount: 0.98,
          onPressed: onTap,
          borderRadius: BorderRadius.circular(Style.radiusMd),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(Style.radiusMd),
                  child: SizedBox(
                    width: 140,
                    height: 140 * 9 / 16,
                    child: Stack(
                      children: [
                        const Positioned.fill(
                          child: SkeletonBox(
                            width: double.infinity,
                            height: double.infinity,
                          ),
                        ),
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: PBadge(
                            text: durationText,
                            type: PBadgeType.duration,
                          ),
                        ),
                        Positioned(
                          left: 4,
                          bottom: 4,
                          child: VideoCoverStatBadge(
                            playCount: DemoOverrides.count(
                              'demo.hplay.$seed',
                              min: 1000,
                              max: 9999999,
                            ),
                            danmakuCount: DemoOverrides.count(
                              'demo.hdm.$seed',
                              min: 10,
                              max: 99999,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SkeletonLine(width: double.infinity, height: 13),
                      const SizedBox(height: 6),
                      const SkeletonLine(width: 150, height: 13),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          AppIcon(
                            AppIcons.profile(),
                            size: 12,
                            color: cs.outline,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                kDemoDisplayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tokens.text.labelSmall
                                    ?.copyWith(color: cs.outline, fontSize: 11),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // 时间 / 进度信息行的骨架占位（对齐真实卡片的三段结构）。
                      const SkeletonLine(width: 96, height: 10),
                    ],
                  ),
                ),
              ],
            ),
          ),
        
          )
        ),
      ),
    );
  }
}
