import 'package:flutter/material.dart';

import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/common/widgets/p_badge.dart';
import 'package:winwin/theme/app_shapes.dart';
import 'package:winwin/utils/duration_utils.dart';
import 'package:winwin/utils/num_utils.dart';

/// 视频卡片 - 水平布局（Phase 7.5.5）。
///
/// 用于「稍后再看」/「历史记录」/「相关推荐」/「搜索结果列表」等
/// 横向列表场景。左侧封面（16:9 固定宽度）+ 右侧文本信息。
///
/// [videoItem] 为 dynamic，兼容多种模型（RelatedVideoItem / HistoryItem /
/// LaterItem / FavDetailItem / RcmdVideoItemModel 等）。预期字段：
/// cover/pic, title, duration, owner.name（回退 upper.name / authorName）,
/// stat.view（回退 cntInfo.play）, stat.danmu/danmaku（回退 cntInfo.danmaku）,
/// bvid, progress（可选，0-1 比例或已看秒数，后者需配合 duration 归一化）。
///
/// 三风格自适应：圆角由 [AppShapes] 解析，时长/进度角标用 [PBadge]。
class VideoCardH extends StatelessWidget {
  const VideoCardH({
    super.key,
    required this.videoItem,
    this.onTap,
    this.heroTag,
    this.coverWidth = 160,
    this.showStat = true,
  });

  final dynamic videoItem;
  final VoidCallback? onTap;

  /// Hero 共享元素 tag（非空时启用封面转场）。
  final Object? heroTag;

  /// 封面宽度（默认 160，可按场景调整）。
  final double coverWidth;

  /// 是否显示播放/弹幕数统计。
  final bool showStat;

  /// 从 videoItem 中取封面 URL（兼容 cover/pic 字段）。
  /// 不同模型字段名不同：HistoryItem 用 cover，RelatedVideoItem 用 pic。
  /// 任一缺失均不能抛 NoSuchMethodError，故两边都用 [_opt] 容错。
  String? get _cover =>
      _opt(() => videoItem.cover as String?) ??
      _opt(() => videoItem.pic as String?);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shapes = theme.extension<AppShapes>() ?? AppShapes.ios;
    final radius = shapes.medium;
    final int duration =
        (_opt(() => videoItem.duration as num?) ?? 0).toInt();
    // progress 为可选字段（仅 HistoryItem / LaterItem 提供），缺失时返回 null。
    // HistoryItem 存已看秒数（>1），需配合 duration 归一化为 0-1 比例。
    double? progress = _opt(() => videoItem.progress as num?)?.toDouble();
    if (progress != null && progress > 1 && duration > 0) {
      progress = progress / duration;
    }

    return Card(
      child: InkWell(
        onTap: onTap,
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
                          src: _cover,
                          width: coverWidth,
                          height: coverWidth * 9 / 16,
                          borderRadius: BorderRadius.all(radius),
                          heroTag: heroTag,
                        ),
                      ),
                      if (duration > 0)
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: PBadge(
                            text: DurationUtils.formatDuration(duration),
                            type: PBadgeType.duration,
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
                            backgroundColor: Colors.transparent,
                            valueColor: AlwaysStoppedAnimation(
                              theme.colorScheme.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // 右：标题 + UP + 统计
              Expanded(child: _buildTextContent(theme)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextContent(ThemeData theme) {
    final String title = videoItem.title?.toString() ?? '';
    final cs = theme.colorScheme;

    // UP 主名多模型回退：owner.name → upper.name（FavDetailItem）→
    // authorName（HistoryItem）。字段缺失时 [_opt] 归一化为 null。
    final dynamic owner = _opt(() => videoItem.owner);
    final String ownerName = owner?.name?.toString() ??
        _opt(() => videoItem.upper?.name as String?) ??
        _opt(() => videoItem.authorName as String?) ??
        '';

    // 统计数回退：stat.view/danmu → cntInfo.play/danmaku（FavDetailItem）。
    final dynamic stat = _opt(() => videoItem.stat);
    final dynamic cntInfo = _opt(() => videoItem.cntInfo);
    final int? playCount = (stat?.view as num?)?.toInt() ??
        _opt(() => (cntInfo?.play as num?)?.toInt());
    final int? danmakuCount = (stat?.danmu as num?)?.toInt() ??
        (stat?.danmaku as num?)?.toInt() ??
        _opt(() => (cntInfo?.danmaku as num?)?.toInt());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
        ),
        const SizedBox(height: 6),
        if (ownerName.isNotEmpty)
          Row(
            children: [
              Icon(Icons.person_outline, size: 13, color: cs.outline),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  ownerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: cs.outline),
                ),
              ),
            ],
          ),
        if (showStat) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.play_circle_outlined, size: 13, color: cs.outline),
              const SizedBox(width: 3),
              Text(
                NumUtils.formatNum(playCount),
                style: theme.textTheme.labelSmall?.copyWith(color: cs.outline),
              ),
              const SizedBox(width: 8),
              Icon(Icons.subtitles_outlined, size: 13, color: cs.outline),
              const SizedBox(width: 3),
              Text(
                NumUtils.formatNum(danmakuCount),
                style: theme.textTheme.labelSmall?.copyWith(color: cs.outline),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 安全读取 [obj] 上的可选字段。
///
/// [VideoCardH] 通过 dynamic 接收多种模型（RelatedVideoItem /
/// HistoryItem / RcmdVideoItemModel 等），部分字段（如 cover/pic/progress）
/// 仅在某些模型上存在。直接 `obj.field` 会在缺失时抛 NoSuchMethodError，
/// 此包装用 try/catch 把这类异常归一化为 null。
T? _opt<T>(T? Function() read) {
  try {
    return read();
  } catch (_) {
    return null;
  }
}
