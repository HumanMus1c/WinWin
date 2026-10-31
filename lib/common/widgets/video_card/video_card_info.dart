import 'package:flutter/widgets.dart';

import 'package:winwin/common/skeleton/skeleton.dart';
import 'package:winwin/core/demo/demo_overrides.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/utils/date_utils.dart';
import 'package:winwin/utils/duration_utils.dart';

/// 视频卡片时间 / 进度文案的唯一口径。
///
/// 历史、稍后再看、收藏夹、用户空间、消息卡片均从这里取文案，
/// 避免各页面自行拼接导致「观看于 / 发布于」口径与格式漂移。
abstract final class VideoCardInfoText {
  /// 播放（观看）时间：历史记录专用。
  ///
  /// 历史时间是「最近一次观看」的时刻，用 [DateFormatUtils.chatFormat]
  /// 保留时分（今天 21:30 / 昨天 20:15 / 10-28 21:30），比纯日期更可读。
  static String playedAt(int? viewAt) {
    if (viewAt == null || viewAt <= 0) return '';
    return '观看于 ${DateFormatUtils.chatFormat(viewAt, isHistory: true)}';
  }

  /// 稿件发布时间：稍后再看 / 收藏夹 / 用户空间专用。
  static String publishedAt(int? pubdate) {
    if (pubdate == null || pubdate <= 0) return '';
    return '发布于 ${DateFormatUtils.dateFormat(pubdate)}';
  }

  /// 播放进度文案：`已看 12:34 / 29:00`；`-1` 表示已看完。
  static String progress(int? progressSeconds, int? durationSeconds) {
    final p = progressSeconds;
    if (p == null) return '';
    if (p == -1) return '已看完';
    if (p <= 0) return '';
    if (durationSeconds != null && durationSeconds > 0) {
      return '已看 ${DurationUtils.formatDuration(p)} / '
          '${DurationUtils.formatDuration(durationSeconds)}';
    }
    return '已看 ${DurationUtils.formatDuration(p)}';
  }
}

/// 视频卡片信息列（横向卡片右侧文本区）。
///
/// 统一层级：标题（最多 2 行）→ UP 行（右侧时间）→ 进度行（右侧动作）。
/// 历史 / 稍后再看 / 收藏夹详情 / 相关推荐 / 搜索结果共用，
/// 保证同一张卡片在不同页面只有「有没有某项数据」的差异，没有排版差异。
class VideoCardInfoColumn extends StatelessWidget {
  const VideoCardInfoColumn({
    super.key,
    required this.title,
    this.ownerName = '',
    this.onOwnerTap,
    this.timeText = '',
    this.progressText = '',
    this.trailing,
    this.demo = false,
    this.titleColor,
    this.titleDecoration,
  });

  final String title;
  final String ownerName;
  final VoidCallback? onOwnerTap;

  /// 时间文案（观看时间 / 发布时间），空字符串表示不展示。
  final String timeText;

  /// 进度文案（已看 12:34 / 29:00），空字符串表示不展示。
  final String progressText;

  /// 右侧动作区（更多 / 删除 / 移除等）。
  final Widget? trailing;

  /// 演示模式：标题显示骨架占位，UP 名称固定为「WinWin」。
  final bool demo;

  /// 标题颜色覆盖（如收藏夹失效稿件置灰）。
  final Color? titleColor;

  /// 标题装饰（失效稿件可用删除线表示档案恢复）。
  final TextDecoration? titleDecoration;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final effectiveOwner = demo ? kDemoDisplayName : ownerName;

    // 标题固定预留两行高度：单行标题不再让 UP / 时间 / 进度行整体上移，
    // 保证同一网格行内的卡片信息行纵向对齐（一行与两行标题处理一致）。
    final double titleSlotHeight = MediaQuery.textScalerOf(context).scale(
          (tokens.text.bodyMedium?.fontSize ?? 14) * 1.35,
        ) *
        2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (demo)
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: titleSlotHeight),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLine(width: double.infinity, height: 13),
                SizedBox(height: 6),
                SkeletonLine(width: 150, height: 13),
              ],
            ),
          )
        else
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: titleSlotHeight),
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: tokens.text.bodyMedium?.copyWith(
                  height: 1.35,
                  color: titleColor,
                  decoration: titleDecoration,
                ),
              ),
            ),
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (effectiveOwner.isNotEmpty || timeText.isNotEmpty)
              Row(
                children: [
                  if (effectiveOwner.isNotEmpty)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: demo ? null : onOwnerTap,
                        child: Row(
                          children: [
                            AppIcon(
                              AppIcons.profile(),
                              size: _metaIconSize,
                              color: cs.outline,
                            ),
                            const SizedBox(width: 2),
                            Flexible(
                              child: Text(
                                effectiveOwner,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                semanticsLabel: 'UP：$effectiveOwner',
                                style: _metaTextStyle(tokens, cs),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  if (timeText.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(
                        timeText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _metaTextStyle(tokens, cs),
                      ),
                    ),
                ],
              ),
            if (progressText.isNotEmpty || trailing != null) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  if (progressText.isNotEmpty)
                    Flexible(
                      child: Text(
                        progressText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _metaTextStyle(tokens, cs),
                      ),
                    ),
                  const Spacer(),
                  ?trailing,
                ],
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// 信息行统一字号：与历史/稍后再看既有 11 口径一致，避免继承 14 撑破行高。
  static const double _metaIconSize = 12;

  static TextStyle? _metaTextStyle(AppTokens tokens, AppPalette cs) =>
      tokens.text.labelSmall?.copyWith(
        color: cs.outline,
        fontSize: 11,
        height: 1.2,
      );
}
