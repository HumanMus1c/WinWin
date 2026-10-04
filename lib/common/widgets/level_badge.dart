import 'package:flutter_miuix/miuix.dart';
import 'package:material_ui/material_ui.dart';

import 'package:winwin/common/widgets/level_icon.dart';
import 'package:winwin/theme/app_shapes.dart';
import 'package:winwin/theme/ui_style.dart';
import 'package:winwin/utils/num_utils.dart';

export 'package:winwin/common/widgets/level_icon.dart';

/// B 站等级对应颜色。
abstract final class LevelColors {
  static const Color lv0 = Color(0xFFC0C0C0);
  static const Color lv1 = Color(0xFFC0C0C0);
  static const Color lv2 = Color(0xFF8BD29B);
  static const Color lv3 = Color(0xFF7BCDEF);
  static const Color lv4 = Color(0xFFFEBB8B);
  static const Color lv5 = Color(0xFFEE672A);
  static const Color lv6 = Color(0xFFF04C49);
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
/// 采用哔哩哔哩官方 Canvas 矢量绘制设计（对齐 PiliPlus 与官方 App）：
/// - 官方液晶数码字模；
/// - 官方切角背景与阶梯色彩（Lv0/1 银灰、Lv2 浅绿、Lv3 晴蓝、Lv4 暖黄、Lv5 亮橙、Lv6 鲜红）；
/// - 硬核会员闪电标识（⚡）。
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
    final effectiveHeight = height ?? 13.0;
    return UserLevel(
      level,
      height: effectiveHeight,
      flash: isSenior,
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
    final levelColor = LevelColors.forLevel(level, isSenior: isSenior);

    final isMax = level >= 6 || (nextExp == null && (currentExp ?? 0) > 0);
    double progress = 1.0;
    if (!isMax && currentExp != null && nextExp != null && nextExp! > 0) {
      final min = currentMin ?? 0;
      final range = (nextExp! - min).clamp(1, 99999999);
      final currentInRange = (currentExp! - min).clamp(0, range);
      progress = (currentInRange / range).clamp(0.0, 1.0);
    }

    // 阶段5d-L1：M3 分支已移除（3dp 全圆角、无描边）。
    const barHeight = 3.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: shapes.smallBorder,
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
          // 上限后（isMax）亦展示进度条（progress 初始即 1.0 满格）——
          // 原先隐藏导致用户空间页"看不到经验条"（复测反馈）。
          const SizedBox(height: 4),
          // 阶段5d-L1：M3 分支已移除。
          SizedBox(
            width: 140,
            height: barHeight,
            child: MiuixLinearProgressIndicator(
              progress: progress,
              height: barHeight,
              colors: MiuixProgressIndicatorColors(
                foregroundColor: levelColor,
                disabledForegroundColor: levelColor,
                backgroundColor: cs.outlineVariant.withValues(alpha: 0.25),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

