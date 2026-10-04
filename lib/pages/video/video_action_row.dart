import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'package:winwin/models/video/video_detail.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/utils/num_utils.dart';

/// 视频详情页互动行（对标 BiliPai
/// `feature/video/ui/section/VideoActionSection.ActionButtonsRow`）。
///
/// B 站官方风格：图标 + 数字竖排按钮等分一行，激活态染 [biliPink]。
/// 点赞按钮支持长按触发「一键三连」进度环（900ms 线性充满后触发
/// [onTriple]，提前松手则回退，参照 BiliPai TripleProgressActionButton）。
///
/// 六个按钮：点赞 / 投币 / 收藏 / 点踩 / 分享 / 稍后再看。
class VideoActionRow extends StatefulWidget {
  const VideoActionRow({
    super.key,
    required this.stat,
    required this.hasLike,
    required this.hasDislike,
    required this.coinNum,
    required this.hasFav,
    required this.inWatchLater,
    required this.onLike,
    required this.onTriple,
    required this.onCoin,
    required this.onDislike,
    required this.onFav,
    required this.onShare,
    required this.onWatchLater,
  });

  /// 稿件统计数据（like/coin/favorite/share 计数）。
  final VideoStat? stat;

  /// 当前用户是否已点赞。
  final bool hasLike;

  /// 当前用户是否已点踩。
  final bool hasDislike;

  /// 当前用户已投币数量。
  final int coinNum;

  /// 当前用户是否已收藏。
  final bool hasFav;

  /// 是否在稍后再看列表（null=未知/未登录，按未添加展示）。
  final bool? inWatchLater;

  final VoidCallback onLike;

  /// 长按点赞进度环充满后触发（一键三连）。
  final VoidCallback onTriple;
  final VoidCallback onCoin;
  final VoidCallback onDislike;
  final VoidCallback onFav;
  final VoidCallback onShare;
  final VoidCallback onWatchLater;

  @override
  State<VideoActionRow> createState() => _VideoActionRowState();
}

class _VideoActionRowState extends State<VideoActionRow>
    with SingleTickerProviderStateMixin {
  /// 三连进度：长按点赞时 900ms 线性充满，松手 180ms 回退
  /// （时长对标 BiliPai detailTripleProgress 动画参数）。
  late final AnimationController _tripleCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    reverseDuration: const Duration(milliseconds: 180),
  );

  /// 长按三连是否进行中（松手/触发完成时置 false）。
  bool _triplePressing = false;

  @override
  void initState() {
    super.initState();
    _tripleCtrl.addStatusListener(_onTripleStatus);
  }

  @override
  void dispose() {
    _tripleCtrl.removeStatusListener(_onTripleStatus);
    _tripleCtrl.dispose();
    super.dispose();
  }

  /// 进度充满 → 触觉反馈 + 触发三连（对标 BiliPai finishedListener）。
  void _onTripleStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _triplePressing) {
      _triplePressing = false;
      HapticFeedback.mediumImpact();
      widget.onTriple();
      _tripleCtrl.value = 0;
    }
  }

  void _startTriplePress() {
    _triplePressing = true;
    HapticFeedback.lightImpact();
    _tripleCtrl.forward();
  }

  void _cancelTriplePress() {
    if (!_triplePressing) return;
    _triplePressing = false;
    if (_tripleCtrl.status == AnimationStatus.forward ||
        _tripleCtrl.status == AnimationStatus.completed) {
      _tripleCtrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final stat = widget.stat;
    final inWatchLater = widget.inWatchLater ?? false;
    return Row(
      children: [
        // 点赞 — 长按触发三连进度环（点击交给内层 InkWell，
        // 长按手势由外层 GestureDetector 监听进度环起止）
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPressStart: (_) => _startTriplePress(),
            onLongPressEnd: (_) => _cancelTriplePress(),
            onLongPressCancel: _cancelTriplePress,
            child: _ActionButton(
              icon: AppIcon(
              AppIcons.like(active: widget.hasLike),
              size: 24,
              color: widget.hasLike
                  ? biliPink
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
              text: NumUtils.formatNum(stat?.like),
              isActive: widget.hasLike,
              tooltip: '点赞（长按一键三连）',
              progress: _tripleCtrl,
              onTap: widget.onLike,
            ),
          ),
        ),
        // 投币
        Expanded(
          child: _ActionButton(
            icon: AppIcon(
              AppIcons.coin(active: widget.coinNum > 0),
              size: 24,
              color: widget.coinNum > 0
                  ? biliPink
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            text: NumUtils.formatNum(stat?.coin),
            isActive: widget.coinNum > 0,
            tooltip: '投币',
            onTap: widget.onCoin,
          ),
        ),
        // 收藏
        Expanded(
          child: _ActionButton(
            icon: AppIcon(
              AppIcons.favorite(active: widget.hasFav),
              size: 24,
              color: widget.hasFav
                  ? biliPink
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            text: NumUtils.formatNum(stat?.favorite),
            isActive: widget.hasFav,
            tooltip: '收藏',
            onTap: widget.onFav,
          ),
        ),
        // 点踩
        Expanded(
          child: _ActionButton(
            icon: AppIcon(
              AppIcons.dislike(active: widget.hasDislike),
              size: 24,
              color: widget.hasDislike
                  ? biliPink
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            text: widget.hasDislike ? '已点踩' : '点踩',
            isActive: widget.hasDislike,
            tooltip: '点踩',
            onTap: widget.onDislike,
          ),
        ),
        // 分享（对标 BiliPai resolveVideoDetailShareActionText：
        // 有计数显示计数，否则显示「分享」）
        Expanded(
          child: _ActionButton(
            icon: AppIcon(
              AppIcons.share(),
              size: 24,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            text: (stat?.share ?? 0) > 0
                ? NumUtils.formatNum(stat?.share)
                : '分享',
            isActive: false,
            tooltip: '分享',
            onTap: widget.onShare,
          ),
        ),
        // 稍后再看
        Expanded(
          child: _ActionButton(
            icon: AppIcon(
              AppIcons.watchLater(active: inWatchLater),
              size: 24,
              color: inWatchLater
                  ? biliPink
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            text: inWatchLater ? '已添加' : '稍后看',
            isActive: inWatchLater,
            tooltip: inWatchLater ? '移除稍后再看' : '添加稍后再看',
            onTap: widget.onWatchLater,
          ),
        ),
      ],
    );
  }
}

/// 单个互动按钮：图标 + 计数竖排（对标 BiliPai BiliActionButton）。
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.text,
    required this.isActive,
    required this.tooltip,
    this.onTap,
    this.progress,
  });

  final Widget icon;
  final String text;
  final bool isActive;
  final String tooltip;
  final VoidCallback? onTap;

  /// 三连进度环动画（仅点赞按钮传入）。
  final Animation<double>? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inactive = theme.colorScheme.onSurfaceVariant;
    final color = isActive ? biliPink : inactive;
    Widget iconWidget = icon;
    if (progress != null) {
      iconWidget = AnimatedBuilder(
        animation: progress!,
        builder: (context, child) => SizedBox.square(
          dimension: 28,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (progress!.value > 0)
                CustomPaint(
                  size: const Size.square(28),
                  painter: _TripleRingPainter(
                    progress: progress!.value,
                    color: biliPink,
                  ),
                ),
              child!,
            ],
          ),
        ),
        child: iconWidget,
      );
    }
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              iconWidget,
              const SizedBox(height: 2),
              Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight:
                      isActive ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 三连进度环（对标 BiliPai TripleProgressActionButton 的 Canvas 圆环：
/// 淡色底环 + 从顶部顺时针扫过的主色进度弧）。
class _TripleRingPainter extends CustomPainter {
  const _TripleRingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 2.5;
    final diameter = size.shortestSide - stroke;
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: diameter,
      height: diameter,
    );
    final bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.18);
    canvas.drawArc(rect, 0, 6.283185307179586, false, bgPaint);
    final fgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    // 从顶部（-90°）顺时针扫过 progress * 360°。
    canvas.drawArc(
      rect,
      -1.5707963267948966,
      6.283185307179586 * progress,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(_TripleRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
