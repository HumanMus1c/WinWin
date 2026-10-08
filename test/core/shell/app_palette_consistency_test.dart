import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/theme/colors.dart';

/// AppPalette 一致性回归（MD3 库级退役 B2 起）。
///
/// 防漂移点：AppPalette 是 `colorScheme` 的取代面，取值必须与项目调色板常量
/// （theme/colors.dart 的 `miuixLight*/miuixDark*`，即过渡期 ThemeData 所用来源）
/// 完全一致——否则逐处迁移会引入不可见的配色漂移。
void main() {
  test('AppPalette 浅色取值与项目调色板常量一致', () {
    const p = AppPalette.light;
    expect(p.primary, miuixLightPrimary);
    expect(p.onPrimary, miuixLightOnPrimary);
    expect(p.primaryContainer, miuixLightPrimaryContainer);
    expect(p.secondary, miuixLightSecondary);
    expect(p.secondaryContainer, miuixLightSecondaryContainer);
    expect(p.tertiary, miuixLightTertiary);
    expect(p.tertiaryContainer, miuixLightTertiaryContainer);
    expect(p.surface, miuixLightSurface);
    expect(p.surfaceContainer, miuixLightSurfaceContainer);
    expect(p.surfaceContainerHighest, miuixLightSurfaceContainerHighest);
    expect(p.onSurface, miuixLightOnSurface);
    expect(p.onSurfaceVariant, miuixLightOnSurfaceVariant);
    expect(p.outline, miuixLightOutline);
    expect(p.outlineVariant, miuixLightOutlineVariant);
    expect(p.background, miuixLightBackground);
    expect(p.onBackground, miuixLightOnSurface);
    expect(p.error, miuixLightError);
  });

  test('AppPalette 深色取值与项目调色板常量一致', () {
    const p = AppPalette.dark;
    expect(p.primary, miuixDarkPrimary);
    expect(p.onPrimary, miuixDarkOnPrimary);
    expect(p.primaryContainer, miuixDarkPrimaryContainer);
    expect(p.secondary, miuixDarkSecondary);
    expect(p.secondaryContainer, miuixDarkSecondaryContainer);
    expect(p.tertiary, miuixDarkTertiary);
    expect(p.tertiaryContainer, miuixDarkTertiaryContainer);
    expect(p.surface, miuixDarkSurface);
    expect(p.surfaceContainer, miuixDarkSurfaceContainer);
    expect(p.surfaceContainerHighest, miuixDarkSurfaceContainerHighest);
    expect(p.onSurface, miuixDarkOnSurface);
    expect(p.onSurfaceVariant, miuixDarkOnSurfaceVariant);
    expect(p.outline, miuixDarkOutline);
    expect(p.outlineVariant, miuixDarkOutlineVariant);
    expect(p.background, miuixDarkBackground);
    expect(p.onBackground, miuixDarkOnSurface);
    expect(p.error, miuixDarkError);
  });

  test('AppThemeHost 按明暗装配对应单例（Token 通道口径）', () {
    final light = AppThemeHost.tokensFor(Brightness.light);
    expect(light.isDark, isFalse);
    expect(identical(light.colors, AppPalette.light), isTrue);
    expect(light.shapes, isNotNull);

    final dark = AppThemeHost.tokensFor(Brightness.dark);
    expect(dark.isDark, isTrue);
    expect(identical(dark.colors, AppPalette.dark), isTrue);
  });
}
