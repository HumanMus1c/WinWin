import 'package:flutter/material.dart';

import 'package:winwin/theme/app_shapes.dart';
import 'package:winwin/theme/inherited_ui_style.dart';
import 'package:winwin/theme/ui_style.dart';
import 'package:winwin/utils/num_utils.dart';

/// B 站等级对应颜色。
abstract final class LevelColors {
  static const Color lv0 = Color(0xFFBFBFBF);
  static const Color lv1 = Color(0xFFBFBFBF);
  static const Color lv2 = Color(0xFF95DDB2);
  static const Color lv3 = Color(0xFF92D1E5);
  static const Color lv4 = Color(0xFFFFB37C);
  static const Color lv5 = Color(0xFFFF6C00);
  static const Color lv6 = Color(0xFFFF0000);
  static const Color senior = Color(0xFFFF7A00);

  static Color forLevel(int level, {bool isSenior = false}) {
    if (isSenior) return senior;
    return switch (level) {
      0 => lv0,
      1 => lv1,
      2 => lv2,
      3 => lv3,
      4 => lv4,
      5 => lv5,
      6 => lv6,
      _ => lv6,
    };
  }
}

/// 用户等级徽章组件（Lv.0 ~ Lv.6 + 硬核会员）。
///
/// 遵循 [UiStyle] 自适应规范：
/// - **Material 3**：微圆角矩形（[AppShapes.tiny]），0 扩散阴影，紧凑色块几何；
/// - **Miuix**：扁平圆润大胶囊（全圆角），0 阴影纯扁平。
class LevelBadge extends StatelessWidget {
  const LevelBadge({
    super.key,
    required this.level,
    this.isSenior = false,
    this.height,
    this.fontSize,
  });

  final int level;
  final bool isSenior;
  final double? height;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shapes = theme.extension<AppShapes>() ?? AppShapes.material3;
    final style = InheritedUiStyle.of(context);
    final renderer = resolvePrimitiveRenderer(style);
    final color = LevelColors.forLevel(level, isSenior: isSenior);

    final effectiveHeight = height ?? (renderer == PrimitiveRenderer.miuix ? 15.0 : 16.0);
    final effectiveFontSize = fontSize ?? (renderer == PrimitiveRenderer.miuix ? 9.5 : 10.0);
    final radius = switch (renderer) {
      PrimitiveRenderer.material3 => shapes.tinyBorder,
      PrimitiveRenderer.miuix => shapes.pillBorder,
    };

    return Container(
      height: effectiveHeight,
      padding: EdgeInsets.symmetric(
        horizontal: renderer == PrimitiveRenderer.miuix ? 6.0 : 5.0,
        vertical: 1.0,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: radius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (isSenior) ...[
            const Icon(Icons.bolt, size: 11, color: Colors.white),
            const SizedBox(width: 1),
          ],
          Text(
            'Lv$level',
            strutStyle: StrutStyle(
              height: 1,
              leading: 0,
              fontSize: effectiveFontSize,
              fontWeight: FontWeight.bold,
            ),
            style: TextStyle(
              fontSize: effectiveFontSize,
              height: 1,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

/// 用户经验进度条组件（当前经验 / 升级经验）。
///
/// 遵循 [UiStyle] 自适应规范：
/// - **Material 3**：4dp 标准 M3 进度指示器，带细边框与 M3 surfaceContainerHighest 背景；
/// - **Miuix**：3dp 纯扁平全圆角进度条，无分割描边，紧凑布局。
class LevelExpBar extends StatelessWidget {
  const LevelExpBar({
    super.key,
    required this.level,
    this.currentExp,
    this.nextExp,
    this.currentMin,
    this.isSenior = false,
  });

  final int level;
  final int? currentExp;
  final int? nextExp;
  final int? currentMin;
  final bool isSenior;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final shapes = theme.extension<AppShapes>() ?? AppShapes.material3;
    final style = InheritedUiStyle.of(context);
    final renderer = resolvePrimitiveRenderer(style);
    final levelColor = LevelColors.forLevel(level, isSenior: isSenior);

    final isMax = level >= 6 || (nextExp == null && (currentExp ?? 0) > 0);
    double progress = 1.0;
    if (!isMax && currentExp != null && nextExp != null && nextExp! > 0) {
      final min = currentMin ?? 0;
      final range = (nextExp! - min).clamp(1, 99999999);
      final currentInRange = (currentExp! - min).clamp(0, range);
      progress = (currentInRange / range).clamp(0.0, 1.0);
    }

    final (barHeight, barRadius, containerBorder) = switch (renderer) {
      PrimitiveRenderer.material3 => (
          4.0,
          shapes.tinyBorder,
          Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.35),
            width: 0.5,
          ),
        ),
      PrimitiveRenderer.miuix => (
          3.0,
          shapes.pillBorder,
          null,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(
          alpha: renderer == PrimitiveRenderer.miuix ? 0.35 : 0.5,
        ),
        borderRadius: shapes.smallBorder,
        border: containerBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              LevelBadge(level: level, isSenior: isSenior, height: 14, fontSize: 9),
              const SizedBox(width: 6),
              Text(
                isMax
                    ? '已达到最高等级 (EXP ${NumUtils.formatNum(currentExp)})'
                    : 'EXP ${currentExp ?? 0} / ${nextExp ?? 0}',
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          if (!isMax) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: barRadius,
              child: SizedBox(
                width: 140,
                height: barHeight,
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: cs.outlineVariant.withValues(alpha: 0.25),
                  valueColor: AlwaysStoppedAnimation<Color>(levelColor),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

