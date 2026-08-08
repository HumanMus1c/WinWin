import 'package:flutter/material.dart';

import 'package:winwin/theme/app_shapes.dart';
import 'package:winwin/theme/inherited_ui_style.dart';
import 'package:winwin/theme/ui_style.dart';

/// 自适应角标组件（Phase 7.5.2）。
///
/// 参照 PiliPlus 的 `PBadge` 三种变体 + BiliPai 的风格化渲染：
/// - [PBadgeType.duration]：黑底白字时长角标（视频封面右下角）。
/// - [PBadgeType.badge]：secondaryContainer 实心角标（rcmdReason / 已关注）。
/// - [PBadgeType.progress]：primary 半透明进度条角标（观看进度）。
///
/// 形状按 [UiStyle] 解析的 [AppShapes] 切换；MD3/Miuix 略有圆角差异。
enum PBadgeType { duration, badge, progress }

class PBadge extends StatelessWidget {
  const PBadge({
    super.key,
    required this.text,
    this.type = PBadgeType.badge,
    this.progress,
  });

  /// 文本内容（duration / badge 类型必填，progress 类型可空）。
  final String? text;

  /// 角标类型。
  final PBadgeType type;

  /// 进度（0.0-1.0），仅 [PBadgeType.progress] 使用。
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final shapes = theme.extension<AppShapes>() ?? AppShapes.ios;
    final style = InheritedUiStyle.of(context);

    switch (type) {
      case PBadgeType.duration:
        return _DurationBadge(
          text: text ?? '',
          radius: shapes.tiny,
          cs: cs,
        );
      case PBadgeType.badge:
        return _SolidBadge(
          text: text ?? '',
          radius: shapes.tiny,
          cs: cs,
          style: style,
        );
      case PBadgeType.progress:
        final p = (progress ?? 0).clamp(0.0, 1.0);
        if (p <= 0) return const SizedBox.shrink();
        return _ProgressBadge(
          progress: p,
          radius: shapes.tiny,
          cs: cs,
          style: style,
        );
    }
  }
}

// ── 时长角标：黑底（85% 不透明）白字，iOS/MD3/Miuix 视觉一致 ──
class _DurationBadge extends StatelessWidget {
  const _DurationBadge({
    required this.text,
    required this.radius,
    required this.cs,
  });

  final String text;
  final Radius radius;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.all(radius),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, color: Colors.white),
      ),
    );
  }
}

// ── 实心角标：secondaryContainer 底色，按风格略调圆角 ──
class _SolidBadge extends StatelessWidget {
  const _SolidBadge({
    required this.text,
    required this.radius,
    required this.cs,
    required this.style,
  });

  final String text;
  final Radius radius;
  final ColorScheme cs;
  final UiStyle style;

  @override
  Widget build(BuildContext context) {
    // Miuix 偏好更圆的胶囊感
    final r = style == UiStyle.miuix ? const Radius.circular(100) : radius;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.all(r),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          height: 1.4,
          color: cs.onSecondaryContainer,
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
    // Miuix 用胶囊；iOS/MD3 用细圆角矩形
    final r = style == UiStyle.miuix ? const Radius.circular(100) : radius;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.85),
        borderRadius: BorderRadius.all(r),
      ),
      child: Text(
        '${(progress * 100).round()}%',
        style: const TextStyle(fontSize: 9, color: Colors.white),
      ),
    );
  }
}
