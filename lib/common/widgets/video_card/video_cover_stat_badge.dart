import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:winwin/theme/app_colors.dart';
import 'package:winwin/theme/app_typography.dart';
import 'package:winwin/common/widgets/p_badge.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/utils/num_utils.dart';

/// 视频封面左下角统计角标（播放量 + 弹幕数）。
///
/// 样式对齐封面右下角时长角标（[PBadge] duration）：黑底半透明 + 白字；
/// 供 [VideoCardH] / 收藏 / 稍后再看等横向卡片复用。
class VideoCoverStatBadge extends StatelessWidget {
  const VideoCoverStatBadge({
    super.key,
    required this.playCount,
    required this.danmakuCount,
  });

  final int? playCount;
  final int? danmakuCount;

  @override
  Widget build(BuildContext context) {
    const TextStyle style = TextStyle(
      fontSize: 10,
      color: AppColors.white,
      height: 1.2,
    );
    return POverlayBadge(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(AppIcons.viewCount(), size: 11, color: AppColors.white),
          const SizedBox(width: 3),
          Text(NumUtils.formatNum(playCount), style: style),
          const SizedBox(width: 6),
          AppIcon(AppIcons.danmakuCount(), size: 11, color: AppColors.white),
          const SizedBox(width: 3),
          Text(NumUtils.formatNum(danmakuCount), style: style),
        ],
      ),
    );
  }
}

/// 竖卡封面底部叠层：播放 / 弹幕 / 点赞三合胶囊 + 时长胶囊。
///
/// 两枚胶囊默认按卡片标题字号渲染；封面宽度不足以同时容纳两枚胶囊时，
/// 按同一比例逐级回落字号与内边距，保证二者不会互相侵入或叠加
/// （2026-11-05 实机反馈）。
///
/// 三项数据共用同一深色底胶囊，用三种**低亮度、低饱和度**的彩字区分：
/// 播放 = 低饱和钢蓝、弹幕 = 低饱和青绿、点赞 = 低饱和玫红。
class VideoCoverStatBar extends StatelessWidget {
  const VideoCoverStatBar({
    super.key,
    required this.playCount,
    required this.danmakuCount,
    this.likeCount,
    required this.durationText,
    this.showStat = true,
  });

  final int? playCount;
  final int? danmakuCount;
  final int? likeCount;

  /// 时长文案（空串表示不显示时长胶囊）。
  final String durationText;

  /// 是否显示左侧统计胶囊。
  final bool showStat;

  /// 播放量：低饱和柔蓝（深色胶囊上仍可辨，不抢画面）。
  static const Color playColor = Color(0xFF8FB4CC);

  /// 弹幕数：低饱和柔青绿。
  static const Color danmakuColor = Color(0xFF9AC4A8);

  /// 点赞数：低饱和柔玫红。
  static const Color likeColor = Color(0xFFD9A8BA);

  /// 两枚胶囊之间的最小安全间距。
  static const double _minGap = 8.0;

  /// 回落字号下限（再小则在封面上不可读）。
  static const double _minFontSize = 9.0;

  /// 字号回落档位（相对标题字号的比例）。
  static const List<double> _shrinkSteps = [
    1.0,
    0.94,
    0.88,
    0.82,
    0.76,
    0.70,
    0.64,
  ];

  @override
  Widget build(BuildContext context) {
    final double nominal =
        DefaultTextStyle.of(context).style.fontSize ?? appBaseFontSize;
    final int? like = (likeCount ?? 0) > 0 ? likeCount : null;
    final bool hasStat =
        showStat && (playCount != null || danmakuCount != null || like != null);
    final String duration = durationText.trim();
    final bool hasDuration = duration.isNotEmpty;
    if (!hasStat && !hasDuration) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final double fontSize = _fitFontSize(
          context,
          constraints.maxWidth,
          nominal,
          hasStat: hasStat,
          hasDuration: hasDuration,
          like: like,
          duration: duration,
        );
        final Widget? stat =
            hasStat ? _statCapsule(context, fontSize, like) : null;
        final Widget? time =
            hasDuration ? _durationCapsule(context, fontSize, duration) : null;
        final Widget row = Row(
          mainAxisAlignment: stat != null && time != null
              ? MainAxisAlignment.spaceBetween
              : time != null
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
          children: [
            ?stat,
            ?time,
          ],
        );
        // 极端窄卡 / 超大字号：字号已回落到下限仍放不下时，整组等比缩小兜底，
        // 保证不会出现 RenderFlex 溢出或两枚胶囊叠压。
        final double required =
            (hasStat ? _statWidth(context, fontSize, like) : 0.0) +
                (hasDuration ? _durationWidth(context, fontSize, duration) : 0.0) +
                (hasStat && hasDuration ? _minGap : 0.0);
        if (required <= constraints.maxWidth) return row;
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: SizedBox(width: required, child: row),
        );
      },
    );
  }

  /// 选择两枚胶囊都能容纳的最大字号；逐级回落，最低 [_minFontSize]。
  double _fitFontSize(
    BuildContext context,
    double maxWidth,
    double nominal, {
    required bool hasStat,
    required bool hasDuration,
    required int? like,
    required String duration,
  }) {
    var fontSize = _minFontSize;
    for (final ratio in _shrinkSteps) {
      final candidate = math.max(nominal * ratio, _minFontSize);
      final required = (hasStat ? _statWidth(context, candidate, like) : 0.0) +
          (hasDuration ? _durationWidth(context, candidate, duration) : 0.0) +
          (hasStat && hasDuration ? _minGap : 0.0);
      if (required <= maxWidth) return candidate;
      fontSize = candidate;
    }
    return fontSize;
  }

  double _statWidth(BuildContext context, double fontSize, int? like) {
    final labels = <String>[
      if (playCount != null) NumUtils.formatNum(playCount),
      if (danmakuCount != null) NumUtils.formatNum(danmakuCount),
      if (like != null) NumUtils.formatNum(like),
    ];
    var width = _horizontalPadding(context, fontSize) * 2;
    for (var i = 0; i < labels.length; i++) {
      if (i > 0) width += _itemGap(context, fontSize);
      width += _iconSize(context, fontSize) +
          _iconGap(context, fontSize) +
          _textWidth(context, labels[i], fontSize) +
          0.5;
    }
    return width;
  }

  double _durationWidth(BuildContext context, double fontSize, String text) =>
      _horizontalPadding(context, fontSize) * 2 +
      _textWidth(context, text, fontSize) +
      0.5;

  Widget _statCapsule(BuildContext context, double fontSize, int? like) {
    final items = <_CoverStatItem>[
      if (playCount != null)
        _CoverStatItem(
          icon: AppIcons.viewCount(),
          text: NumUtils.formatNum(playCount),
          color: playColor,
        ),
      if (danmakuCount != null)
        _CoverStatItem(
          icon: AppIcons.danmakuCount(),
          text: NumUtils.formatNum(danmakuCount),
          color: danmakuColor,
        ),
      if (like != null)
        _CoverStatItem(
          icon: AppIcons.like(),
          text: NumUtils.formatNum(like),
          color: likeColor,
        ),
    ];
    final double iconSize = _iconSize(context, fontSize);
    final double iconGap = _iconGap(context, fontSize);
    final double itemGap = _itemGap(context, fontSize);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _horizontalPadding(context, fontSize),
        vertical: _verticalPadding(context, fontSize),
      ),
      decoration: BoxDecoration(
        color: AppColors.black.withValues(alpha: 0.70),
        borderRadius: const BorderRadius.all(Radius.circular(100)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) SizedBox(width: itemGap),
            AppIcon(items[i].icon, size: iconSize, color: items[i].color),
            SizedBox(width: iconGap),
            Text(
              items[i].text,
              style: TextStyle(
                fontSize: fontSize,
                height: 1.2,
                color: items[i].color,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _durationCapsule(BuildContext context, double fontSize, String text) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _horizontalPadding(context, fontSize),
        vertical: _verticalPadding(context, fontSize),
      ),
      decoration: BoxDecoration(
        color: AppColors.black.withValues(alpha: 0.70),
        borderRadius: const BorderRadius.all(Radius.circular(100)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: fontSize,
          height: 1.2,
          color: AppColors.white,
        ),
      ),
    );
  }

  // 以下尺寸均以**实际渲染字号**为基准：文字由 Text 再乘 textScaler，
  // 图标与内边距需与之同源，UI 缩放时才能保持比例。
  static double _rendered(BuildContext context, double fontSize) =>
      MediaQuery.textScalerOf(context).scale(fontSize);

  static double _horizontalPadding(BuildContext context, double fontSize) =>
      _rendered(context, fontSize) * 0.42;

  static double _verticalPadding(BuildContext context, double fontSize) =>
      _rendered(context, fontSize) * 0.14;

  static double _iconSize(BuildContext context, double fontSize) =>
      _rendered(context, fontSize) * 1.0;

  static double _iconGap(BuildContext context, double fontSize) =>
      _rendered(context, fontSize) * 0.20;

  static double _itemGap(BuildContext context, double fontSize) =>
      _rendered(context, fontSize) * 0.45;

  static double _textWidth(
    BuildContext context,
    String text,
    double fontSize,
  ) {
    final inherited = DefaultTextStyle.of(context).style;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          height: 1.2,
          fontFamily: inherited.fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.width;
  }
}

class _CoverStatItem {
  const _CoverStatItem({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;
}
