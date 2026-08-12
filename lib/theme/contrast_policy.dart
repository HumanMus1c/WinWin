import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 主题对比度策略（ThemeContrastPolicy）。
///
/// 纯 Dart 复刻自 BiliPai design-system `ThemeContrastPolicy.kt`：
/// 半透明容器先与背景做 alpha 合成（[opaqueCompositeOver]），再基于
/// WCAG 相对亮度公式测对比度（[calculateContrastRatio]），为半透明
/// 表面选出可读前景色（[resolveAccessibleContainerColors]）。
///
/// 阈值：文字 4.5:1（[kAccessibleTextMinContrast]），
/// 非文字 UI 元素 3.0:1（[kAccessibleUiMinContrast]）。

const double kAccessibleTextMinContrast = 4.5;
const double kAccessibleUiMinContrast = 3.0;

/// 半透明容器的「不透明视觉等价 + 可读前景色」解析结果。
class AccessibleContainerColors {
  const AccessibleContainerColors({
    required this.containerColor,
    required this.contentColor,
  });

  /// 与背景 alpha 合成后的不透明容器色。
  final Color containerColor;

  /// 达到最小对比度（或候选中对比度最高）的前景色。
  final Color contentColor;
}

/// 把 [foreground] 叠在 [background] 上拍平为不透明色，
/// 使对比度检测基于用户实际看到的颜色（Porter-Duff source-over）。
Color opaqueCompositeOver(Color foreground, Color background) {
  final fa = foreground.a;
  final ba = background.a;
  final outAlpha = fa + ba * (1 - fa);
  if (outAlpha == 0) return Colors.transparent;
  return Color.from(
    alpha: 1,
    red: (foreground.r * fa + background.r * ba * (1 - fa)) / outAlpha,
    green: (foreground.g * fa + background.g * ba * (1 - fa)) / outAlpha,
    blue: (foreground.b * fa + background.b * ba * (1 - fa)) / outAlpha,
  );
}

/// WCAG 对比度比值：(L_lighter + 0.05) / (L_darker + 0.05)。
double calculateContrastRatio(Color foreground, Color background) {
  final fl = foreground.computeLuminance();
  final bl = background.computeLuminance();
  final lighter = math.max(fl, bl);
  final darker = math.min(fl, bl);
  return (lighter + 0.05) / (darker + 0.05);
}

/// 为半透明语义容器解析不透明等价色与可读前景色。
///
/// 候选前景 = [contentColor] + [fallbackContentColors]（去重后按序），
/// 第一个达到 [minimumContrast] 的候选胜出；全部不达标时退回对比度
/// 最高的候选。
AccessibleContainerColors resolveAccessibleContainerColors({
  required Color containerColor,
  required Color contentColor,
  required Color backgroundColor,
  List<Color> fallbackContentColors = const [],
  double minimumContrast = kAccessibleTextMinContrast,
}) {
  final resolvedContainer = opaqueCompositeOver(containerColor, backgroundColor);
  final candidates = <Color>{contentColor, ...fallbackContentColors}.toList();
  final resolved = candidates.firstWhere(
    (c) => calculateContrastRatio(c, resolvedContainer) >= minimumContrast,
    orElse: () => candidates.reduce(
      (a, b) => calculateContrastRatio(a, resolvedContainer) >=
              calculateContrastRatio(b, resolvedContainer)
          ? a
          : b,
    ),
  );
  return AccessibleContainerColors(
    containerColor: resolvedContainer,
    contentColor: resolved.withValues(alpha: 1),
  );
}

/// 候选色不达标时依次尝试 [fallbacks]，仍不达标则保留候选色。
Color resolveReadableThemeTextColor({
  required Color candidate,
  required Color background,
  required List<Color> fallbacks,
  required double minimumContrast,
}) {
  if (calculateContrastRatio(candidate, background) >= minimumContrast) {
    return candidate;
  }
  for (final fallback in fallbacks) {
    if (calculateContrastRatio(fallback, background) >= minimumContrast) {
      return fallback;
    }
  }
  return candidate;
}

/// 对标 BiliPai `enforceDynamicLightTextContrast`：校正 ColorScheme 中
/// 各 on*/容器配对的文字对比度（浅色主题下个别动态色可能不达标）。
///
/// 仅使用未弃用的 surface/container 语义槽位。
ColorScheme enforceDynamicLightTextContrast(ColorScheme scheme) {
  final accentFallbacks = [
    scheme.onSurface,
    scheme.onInverseSurface,
    scheme.scrim,
  ];
  final surfaceFallbacks = [
    scheme.onSurface,
    scheme.onInverseSurface,
    scheme.scrim,
  ];
  final surfaceVariantFallbacks = [
    scheme.onSurface,
    scheme.onInverseSurface,
    scheme.scrim,
  ];

  return scheme.copyWith(
    onSurface: resolveReadableThemeTextColor(
      candidate: scheme.onSurface,
      background: scheme.surface,
      fallbacks: surfaceFallbacks,
      minimumContrast: kAccessibleTextMinContrast,
    ),
    onSurfaceVariant: resolveReadableThemeTextColor(
      candidate: scheme.onSurfaceVariant,
      background: scheme.surfaceContainerHighest,
      fallbacks: surfaceVariantFallbacks,
      minimumContrast: kAccessibleTextMinContrast,
    ),
    onPrimary: resolveReadableThemeTextColor(
      candidate: scheme.onPrimary,
      background: scheme.primary,
      fallbacks: accentFallbacks,
      minimumContrast: kAccessibleTextMinContrast,
    ),
    onPrimaryContainer: resolveReadableThemeTextColor(
      candidate: scheme.onPrimaryContainer,
      background: scheme.primaryContainer,
      fallbacks: accentFallbacks,
      minimumContrast: kAccessibleTextMinContrast,
    ),
    onSecondaryContainer: resolveReadableThemeTextColor(
      candidate: scheme.onSecondaryContainer,
      background: scheme.secondaryContainer,
      fallbacks: accentFallbacks,
      minimumContrast: kAccessibleTextMinContrast,
    ),
    onTertiaryContainer: resolveReadableThemeTextColor(
      candidate: scheme.onTertiaryContainer,
      background: scheme.tertiaryContainer,
      fallbacks: accentFallbacks,
      minimumContrast: kAccessibleTextMinContrast,
    ),
    onError: resolveReadableThemeTextColor(
      candidate: scheme.onError,
      background: scheme.error,
      fallbacks: accentFallbacks,
      minimumContrast: kAccessibleTextMinContrast,
    ),
    onErrorContainer: resolveReadableThemeTextColor(
      candidate: scheme.onErrorContainer,
      background: scheme.errorContainer,
      fallbacks: accentFallbacks,
      minimumContrast: kAccessibleTextMinContrast,
    ),
  );
}
