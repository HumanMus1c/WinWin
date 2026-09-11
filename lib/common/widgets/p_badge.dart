import 'package:flutter/material.dart';

import 'package:winwin/theme/app_shapes.dart';
import 'package:winwin/theme/inherited_ui_style.dart';
import 'package:winwin/theme/ui_style.dart';

/// 自适应角标组件（对齐 PiliPlus 与哔哩哔哩官方美术规范）。
///
/// 支持多种语义化标签：
/// - [PBadgeType.duration]：黑底半透明白字时长角标（视频封面右下角）。
/// - [PBadgeType.highlight]：哔哩哔哩官方活力暖橙底白字（高播放量 / 高点赞 / 热门推荐）。
/// - [PBadgeType.status]：低饱和弱化中性灰底（已关注等辅助状态）。
/// - [PBadgeType.primary]：官方品牌粉红底白字（置顶 / 精选 / 重要通知）。
/// - [PBadgeType.vip]：官方大会员粉红底白字（大会员 / 年度大会员）。
/// - [PBadgeType.linePrimary]：透明底，品牌粉红细边框与文字（番剧独家 / 完结）。
/// - [PBadgeType.lineSecondary]：透明底，中性灰细边框与文字。
/// - [PBadgeType.error]：官方警示红底白字。
/// - [PBadgeType.progress]：主色半透明进度条角标（观看进度）。
/// - [PBadgeType.badge]：通用兼容实心角标（若包含赞/播放/热等推荐词自动高光，否则使用弱底）。
enum PBadgeType {
  duration,
  highlight,
  status,
  primary,
  vip,
  linePrimary,
  lineSecondary,
  error,
  progress,
  badge,
}

class PBadge extends StatelessWidget {
  const PBadge({
    super.key,
    required this.text,
    this.type = PBadgeType.badge,
    this.progress,
    this.fontSize,
    this.padding,
    this.backgroundColor,
    this.textColor,
    this.borderColor,
  });

  /// 文本内容（duration / highlight / status 等类型必填，progress 类型可空）。
  final String? text;

  /// 角标类型。
  final PBadgeType type;

  /// 进度（0.0-1.0），仅 [PBadgeType.progress] 使用。
  final double? progress;

  /// 自定义字号（默认 9.0）。
  final double? fontSize;

  /// 自定义内边距。
  final EdgeInsetsGeometry? padding;

  /// 自定义背景色（覆盖类型默认色）。
  final Color? backgroundColor;

  /// 自定义文字色（覆盖类型默认色）。
  final Color? textColor;

  /// 自定义边框颜色。
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final shapes = theme.extension<AppShapes>() ?? AppShapes.material3;
    final style = InheritedUiStyle.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (type == PBadgeType.progress) {
      final p = (progress ?? 0).clamp(0.0, 1.0);
      if (p <= 0) return const SizedBox.shrink();
      return _ProgressBadge(
        progress: p,
        radius: shapes.tiny,
        cs: cs,
        style: style,
      );
    }

    final rawText = text ?? '';
    if (rawText.isEmpty) return const SizedBox.shrink();

    if (type == PBadgeType.duration) {
      return _DurationBadge(
        text: rawText,
        radius: shapes.tiny,
        fontSize: fontSize ?? 10.0,
        padding: padding,
      );
    }

    // 智能识别兼容：当为 badge 时，如果文案是“已关注”转为 status，如果含“播放/赞/热/万”等转为 highlight
    final resolvedType = switch (type) {
      PBadgeType.badge => _inferBadgeType(rawText),
      _ => type,
    };

    return _ThemedBadge(
      text: rawText,
      type: resolvedType,
      radius: shapes.tiny,
      cs: cs,
      style: style,
      isDark: isDark,
      fontSize: fontSize ?? 9.0,
      padding: padding,
      customBg: backgroundColor,
      customFg: textColor,
      customBorder: borderColor,
    );
  }

  static PBadgeType _inferBadgeType(String text) {
    if (text == '已关注' || text == '新关注') {
      return PBadgeType.status;
    }
    if (text.contains('会员') || text.contains('大会员') || text.contains('专享')) {
      return PBadgeType.vip;
    }
    if (text.contains('限免')) {
      return PBadgeType.highlight;
    }
    if (text.contains('独家') || text.contains('出品')) {
      return PBadgeType.primary;
    }
    if (text.contains('播放') ||
        text.contains('赞') ||
        text.contains('热') ||
        text.contains('推荐') ||
        text.contains('万') ||
        text.contains('看')) {
      return PBadgeType.highlight;
    }
    return PBadgeType.status;
  }
}

// ── 时长角标：黑底（65%~80% 不透明）白字 ──
class _DurationBadge extends StatelessWidget {
  const _DurationBadge({
    required this.text,
    required this.radius,
    required this.fontSize,
    this.padding,
  });

  final String text;
  final Radius radius;
  final double fontSize;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.70),
        borderRadius: BorderRadius.all(radius),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: fontSize, color: Colors.white, height: 1.2),
      ),
    );
  }
}

// ── 语义化实心/描边角标：依据哔哩哔哩官方美术规范渲染 ──
class _ThemedBadge extends StatelessWidget {
  const _ThemedBadge({
    required this.text,
    required this.type,
    required this.radius,
    required this.cs,
    required this.style,
    required this.isDark,
    required this.fontSize,
    this.padding,
    this.customBg,
    this.customFg,
    this.customBorder,
  });

  final String text;
  final PBadgeType type;
  final Radius radius;
  final ColorScheme cs;
  final UiStyle style;
  final bool isDark;
  final double fontSize;
  final EdgeInsetsGeometry? padding;
  final Color? customBg;
  final Color? customFg;
  final Color? customBorder;

  @override
  Widget build(BuildContext context) {
    final r = style == UiStyle.miuix ? const Radius.circular(100) : radius;

    // 官方规范颜色取值（对标 PiliPlus 与官方 App）：
    // - highlight（高光推荐）：官方亮橙色 #FF7F24（浅色）/ #D66011（深色）
    // - vip / primary（官方粉红）：#FA7298 / #FB7299
    // - status（辅状态已关注）：浅灰透明底 + 弱中性文字
    // - error（警示）：红底白字
    final Color bgColor;
    final Color fgColor;
    Color border = Colors.transparent;

    switch (type) {
      case PBadgeType.highlight:
        bgColor = isDark ? const Color(0xFFD66011) : const Color(0xFFFF7F24);
        fgColor = Colors.white;
        break;
      case PBadgeType.status:
        bgColor = cs.secondaryContainer.withValues(alpha: isDark ? 0.55 : 0.45);
        fgColor = cs.onSecondaryContainer.withValues(alpha: 0.90);
        break;
      case PBadgeType.primary:
        bgColor = cs.primary;
        fgColor = cs.onPrimary;
        break;
      case PBadgeType.vip:
        bgColor = const Color(0xFFFB7299);
        fgColor = Colors.white;
        break;
      case PBadgeType.linePrimary:
        bgColor = Colors.transparent;
        fgColor = cs.primary;
        border = cs.primary;
        break;
      case PBadgeType.lineSecondary:
        bgColor = Colors.transparent;
        fgColor = cs.outline;
        border = cs.outlineVariant;
        break;
      case PBadgeType.error:
        bgColor = cs.error;
        fgColor = cs.onError;
        break;
      case PBadgeType.badge:
      case PBadgeType.duration:
      case PBadgeType.progress:
        bgColor = cs.secondaryContainer;
        fgColor = cs.onSecondaryContainer;
        break;
    }

    final resolvedBg = customBg ?? bgColor;
    final resolvedFg = customFg ?? fgColor;
    final resolvedBorder = customBorder ?? border;

    return Container(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
      decoration: BoxDecoration(
        color: resolvedBg,
        borderRadius: BorderRadius.all(r),
        border: resolvedBorder != Colors.transparent ? Border.all(color: resolvedBorder, width: 0.8) : null,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: fontSize,
          height: 1.35,
          color: resolvedFg,
          fontWeight: (type == PBadgeType.highlight || type == PBadgeType.vip || type == PBadgeType.primary)
              ? FontWeight.bold
              : FontWeight.normal,
        ),
      ),
    );
  }
}

// ── 进度角标：primary 半透明底色 + 白字 ──
class _ProgressBadge extends StatelessWidget {
  const _ProgressBadge({
    required this.progress,
    required this.radius,
    required this.cs,
    required this.style,
  });

  final double progress;
  final Radius radius;
  final ColorScheme cs;
  final UiStyle style;

  @override
  Widget build(BuildContext context) {
    final r = style == UiStyle.miuix ? const Radius.circular(100) : radius;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.85),
        borderRadius: BorderRadius.all(r),
      ),
      child: Text(
        '${(progress * 100).round()}%',
        style: const TextStyle(fontSize: 9, color: Colors.white, height: 1.2),
      ),
    );
  }
}
