import 'package:flutter/material.dart';

import 'package:winwin/theme/app_shapes.dart';
import 'package:winwin/theme/contrast_policy.dart';

/// 解析大会员角标展示文案。
///
/// 移植自 BiliPai `UserVipBadge.kt`：
/// 优先使用服务端返回的 [label]；若为空，则依据 [vipType] 进行兜底：
/// - 2 -> "年度大会员"
/// - 1 或其他 -> "大会员"
String resolveUserVipBadgeLabel(String? label, [int vipType = 0]) {
  final trimmed = label?.trim() ?? '';
  if (trimmed.isNotEmpty) return trimmed;
  return switch (vipType) {
    2 => '年度大会员',
    1 => '大会员',
    _ => '大会员',
  };
}

/// 大会员角标的前景与背景色计算结果。
class AccessibleVipBadgeColors {
  const AccessibleVipBadgeColors({
    required this.containerColor,
    required this.contentColor,
  });

  final Color containerColor;
  final Color contentColor;
}

/// 计算符合 WCAG 4.5:1 对比度的大会员角标颜色。
///
/// 移植自 BiliPai `UserVipBadge.kt` 中的 `resolveVipBadgeColors`：
/// 在暗色模式或半透明背景下，通过 alpha 拍平后按序在备选前景色中选取
/// 最具可读性的前景色，避免暗色背景上文字泛白或发灰。
AccessibleVipBadgeColors resolveVipBadgeColors({
  required Color containerColor,
  required Color preferredContentColor,
  required Color surfaceColor,
  required Color onSurface,
  required Color onBackground,
  required Color inverseOnSurface,
}) {
  final resolved = resolveAccessibleContainerColors(
    containerColor: containerColor,
    contentColor: preferredContentColor,
    backgroundColor: surfaceColor,
    fallbackContentColors: [
      onSurface,
      onBackground,
      inverseOnSurface,
      Colors.white,
      Colors.black,
    ],
    minimumContrast: kAccessibleTextMinContrast,
  );
  return AccessibleVipBadgeColors(
    containerColor: resolved.containerColor,
    contentColor: resolved.contentColor,
  );
}

/// 自适应大会员微章胶囊（个人空间 / 详情页 / 评论区通用）。
///
/// 移植自 BiliPai `UserVipBadge.kt`：
/// - 软质填充胶囊，默认取主题 secondaryContainer / onSecondaryContainer 配对，
///   深色模式下自动压平透光容器，并确保 WCAG 4.5:1 无障碍高对比度；
/// - 支持常规（内边距 10×5）与紧凑（内边距 8×3）两种形态；
/// - 默认字号 11.0，字重 SemiBold (w600)。
class UserVipBadge extends StatelessWidget {
  const UserVipBadge({
    super.key,
    this.label,
    this.vipType = 0,
    this.fontSize = 11.0,
    this.compact = false,
    this.containerColor,
    this.contentColor,
  });

  final String? label;
  final int vipType;
  final double fontSize;
  final bool compact;
  final Color? containerColor;
  final Color? contentColor;

  @override
  Widget build(BuildContext context) {
    final text = resolveUserVipBadgeLabel(label, vipType);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final shapes = theme.extension<AppShapes>() ?? AppShapes.ios;

    final baseContainer = containerColor ?? cs.secondaryContainer;
    final baseContent = contentColor ?? cs.onSecondaryContainer;

    final accessible = resolveVipBadgeColors(
      containerColor: baseContainer,
      preferredContentColor: baseContent,
      surfaceColor: cs.surface,
      onSurface: cs.onSurface,
      onBackground: cs.onSurface,
      inverseOnSurface: cs.inverseSurface,
    );

    return Container(
      decoration: ShapeDecoration(
        color: accessible.containerColor,
        shape: shapes.pillShape,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8.0 : 10.0,
        vertical: compact ? 3.0 : 5.0,
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: fontSize,
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: accessible.contentColor,
        ),
      ),
    );
  }
}
