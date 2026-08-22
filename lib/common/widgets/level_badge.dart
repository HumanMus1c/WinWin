import 'package:flutter/material.dart';

import 'package:winwin/theme/style.dart';
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
class LevelBadge extends StatelessWidget {
  const LevelBadge({
    super.key,
    required this.level,
    this.isSenior = false,
    this.height = 16.0,
    this.fontSize = 10.0,
  });

  final int level;
  final bool isSenior;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final color = LevelColors.forLevel(level, isSenior: isSenior);

    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(Style.radiusXs - 1),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
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
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
            ),
            style: TextStyle(
              fontSize: fontSize,
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
    final levelColor = LevelColors.forLevel(level, isSenior: isSenior);

    final isMax = level >= 6 || (nextExp == null && (currentExp ?? 0) > 0);
    double progress = 1.0;
    if (!isMax && currentExp != null && nextExp != null && nextExp! > 0) {
      final min = currentMin ?? 0;
      final range = (nextExp! - min).clamp(1, 99999999);
      final currentInRange = (currentExp! - min).clamp(0, range);
      progress = (currentInRange / range).clamp(0.0, 1.0);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(Style.radiusSm),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.25),
          width: 0.5,
        ),
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
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                width: 140,
                height: 4,
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: cs.outlineVariant.withValues(alpha: 0.3),
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
