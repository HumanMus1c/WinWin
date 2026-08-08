import 'package:flutter/material.dart';
import 'app_chrome.dart';
import 'app_shapes.dart';
import 'app_typography.dart';
import 'colors.dart';
import 'ui_style.dart';

/// App theme — 按 [UiStyle] 解析三套 ThemeData。
///
/// 参照 BiliPai 的 `PureBiliBiliTheme`：
/// - **iOS**：沿用现有 iosBlue 配色，连续曲率圆角，扩散阴影。
/// - **Material 3**：标准 M3 ColorScheme（品牌粉种子色衍生），
///   `surfaceContainerHighest` 强调 tonal elevation，圆角 ×0.9 缩放。
/// - **Miuix**：扁平低 elevation 配色，`surfaceContainer` 偏中性灰，
///   圆角 ×1.15 缩放。
///
/// 在 `main.dart` 通过 `ValueListenableBuilder<UiStyle>` 消费
/// [UiStyleNotifier]，切换 `theme`/`darkTheme` 即可实现整树热切换。
class AppTheme {
  /// 浅色主题（按 [style] 解析）。
  static ThemeData lightFor(UiStyle style) => switch (style) {
        UiStyle.ios => _iosLight,
        UiStyle.material3 => _md3Light,
        UiStyle.miuix => _miuixLight,
      };

  /// 深色主题（按 [style] 解析）。
  static ThemeData darkFor(UiStyle style) => switch (style) {
        UiStyle.ios => _iosDark,
        UiStyle.material3 => _md3Dark,
        UiStyle.miuix => _miuixDark,
      };

  /// 向后兼容：默认 iOS 浅色主题。
  static ThemeData get light => lightFor(UiStyle.ios);

  /// 向后兼容：默认 iOS 深色主题。
  static ThemeData get dark => darkFor(UiStyle.ios);

  /// 按 [UiStyle] 组装三套设计 Token（[AppShapes] / [AppTypography] /
  /// [AppChrome]），挂载到 [ThemeData.extensions]，组件通过
  /// `Theme.of(context).extension<AppShapes>()` 等读取。
  static Iterable<ThemeExtension<dynamic>> _extensionsFor(UiStyle style) => [
        AppShapes.forStyle(style),
        AppTypography.forStyle(style),
        AppChrome.forStyle(style),
      ];

  // ─────────────────────────── iOS ───────────────────────────

  static const _iosRadiusSmall = Radius.circular(10);
  static const _iosRadiusMedium = Radius.circular(12);
  static const _iosRadiusLarge = Radius.circular(14);
  static const _iosRadiusXLarge = Radius.circular(20);
  static const _iosRadiusFloating = Radius.circular(28);

  static ThemeData get _iosLight => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          primary: iosBlue,
          onPrimary: Colors.white,
          secondary: iosSystemGray,
          background: lightBackground,
          surface: lightSurface,
          surfaceContainer: iosSystemGray5,
          surfaceContainerHighest: iosSystemGray4,
          onSurface: Color(0xFF1C1C1E),
          onSurfaceVariant: iosSystemGray,
          error: iosRed,
        ),
        scaffoldBackgroundColor: lightBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        cardTheme: CardThemeData(
          color: lightSurface,
          elevation: 0,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(_iosRadiusMedium),
          ),
        ),
        extensions: _extensionsFor(UiStyle.ios),
      );

  static ThemeData get _iosDark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: iosBlue,
          onPrimary: Colors.white,
          secondary: iosSystemGray2,
          background: darkBackground,
          surface: darkSurface,
          surfaceContainer: darkSurfaceVariant,
          surfaceContainerHighest: Color(0xFF363636),
          onSurface: Color(0xFFE8E8E8),
          onSurfaceVariant: Color(0xFFB0B0B0),
          error: iosRed,
        ),
        scaffoldBackgroundColor: darkBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        cardTheme: CardThemeData(
          color: darkSurface,
          elevation: 0,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(_iosRadiusMedium),
          ),
        ),
        extensions: _extensionsFor(UiStyle.ios),
      );

  // ─────────────────────────── Material 3 ───────────────────────────

  /// M3 圆角缩放系数（BiliPai: MD3_CORNER_RADIUS_SCALE = 0.9f）。
  static const _md3Scale = 0.9;
  static final _md3RadiusSmall = Radius.circular((10 * _md3Scale).roundToDouble());
  static final _md3RadiusMedium = Radius.circular((12 * _md3Scale).roundToDouble());
  static final _md3RadiusLarge = Radius.circular((14 * _md3Scale).roundToDouble());
  static final _md3RadiusXLarge = Radius.circular((20 * _md3Scale).roundToDouble());
  static final _md3RadiusFloating = Radius.circular((28 * _md3Scale).roundToDouble());

  static ThemeData get _md3Light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          primary: md3LightPrimary,
          onPrimary: md3LightOnPrimary,
          primaryContainer: md3LightPrimaryContainer,
          onPrimaryContainer: md3LightOnPrimaryContainer,
          secondary: md3LightSecondary,
          onSecondary: md3LightOnSecondary,
          secondaryContainer: md3LightSecondaryContainer,
          onSecondaryContainer: md3LightOnSecondaryContainer,
          tertiary: md3LightTertiary,
          onTertiary: md3LightOnTertiary,
          tertiaryContainer: md3LightTertiaryContainer,
          onTertiaryContainer: md3LightOnTertiaryContainer,
          background: md3LightBackground,
          surface: md3LightSurface,
          surfaceContainerLowest: md3LightSurfaceContainerLowest,
          surfaceContainerLow: md3LightSurfaceContainerLow,
          surfaceContainer: md3LightSurfaceContainer,
          surfaceContainerHigh: md3LightSurfaceContainerHigh,
          surfaceContainerHighest: md3LightSurfaceContainerHighest,
          onSurface: md3LightOnSurface,
          onSurfaceVariant: md3LightOnSurfaceVariant,
          outline: md3LightOutline,
          outlineVariant: md3LightOutlineVariant,
          error: md3LightError,
          onError: md3LightOnError,
          errorContainer: md3LightErrorContainer,
          onErrorContainer: md3LightOnErrorContainer,
        ),
        scaffoldBackgroundColor: md3LightBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 3,
        ),
        cardTheme: CardThemeData(
          color: md3LightSurface,
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(_md3RadiusMedium),
          ),
        ),
        extensions: _extensionsFor(UiStyle.material3),
      );

  static ThemeData get _md3Dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: md3DarkPrimary,
          onPrimary: md3DarkOnPrimary,
          primaryContainer: md3DarkPrimaryContainer,
          onPrimaryContainer: md3DarkOnPrimaryContainer,
          secondary: md3DarkSecondary,
          onSecondary: md3DarkOnSecondary,
          secondaryContainer: md3DarkSecondaryContainer,
          onSecondaryContainer: md3DarkOnSecondaryContainer,
          tertiary: md3DarkTertiary,
          onTertiary: md3DarkOnTertiary,
          tertiaryContainer: md3DarkTertiaryContainer,
          onTertiaryContainer: md3DarkOnTertiaryContainer,
          background: md3DarkBackground,
          surface: md3DarkSurface,
          surfaceContainerLowest: md3DarkSurfaceContainerLowest,
          surfaceContainerLow: md3DarkSurfaceContainerLow,
          surfaceContainer: md3DarkSurfaceContainer,
          surfaceContainerHigh: md3DarkSurfaceContainerHigh,
          surfaceContainerHighest: md3DarkSurfaceContainerHighest,
          onSurface: md3DarkOnSurface,
          onSurfaceVariant: md3DarkOnSurfaceVariant,
          outline: md3DarkOutline,
          outlineVariant: md3DarkOutlineVariant,
          error: md3DarkError,
          onError: md3DarkOnError,
          errorContainer: md3DarkErrorContainer,
          onErrorContainer: md3DarkOnErrorContainer,
        ),
        scaffoldBackgroundColor: md3DarkBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 3,
        ),
        cardTheme: CardThemeData(
          color: md3DarkSurface,
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(_md3RadiusMedium),
          ),
        ),
        extensions: _extensionsFor(UiStyle.material3),
      );

  // ─────────────────────────── Miuix ───────────────────────────

  /// Miuix 圆角缩放系数（BiliPai: MIUIX_CORNER_RADIUS_SCALE = 1.15f）。
  static const _miuixScale = 1.15;
  static final _miuixRadiusSmall = Radius.circular((10 * _miuixScale).roundToDouble());
  static final _miuixRadiusMedium = Radius.circular((12 * _miuixScale).roundToDouble());
  static final _miuixRadiusLarge = Radius.circular((14 * _miuixScale).roundToDouble());
  static final _miuixRadiusXLarge = Radius.circular((20 * _miuixScale).roundToDouble());
  static final _miuixRadiusFloating = Radius.circular((28 * _miuixScale).roundToDouble());

  static ThemeData get _miuixLight => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          primary: miuixLightPrimary,
          onPrimary: miuixLightOnPrimary,
          primaryContainer: miuixLightPrimaryContainer,
          onPrimaryContainer: miuixLightOnPrimaryContainer,
          secondary: miuixLightSecondary,
          secondaryContainer: miuixLightSecondaryContainer,
          tertiary: miuixLightTertiary,
          tertiaryContainer: miuixLightTertiaryContainer,
          background: miuixLightBackground,
          surface: miuixLightSurface,
          surfaceContainer: miuixLightSurfaceContainer,
          surfaceContainerHighest: miuixLightSurfaceContainerHighest,
          onSurface: miuixLightOnSurface,
          onSurfaceVariant: miuixLightOnSurfaceVariant,
          outline: miuixLightOutline,
          outlineVariant: miuixLightOutlineVariant,
          error: miuixLightError,
        ),
        scaffoldBackgroundColor: miuixLightBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        cardTheme: CardThemeData(
          color: miuixLightSurfaceContainer,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(_miuixRadiusMedium),
          ),
        ),
        extensions: _extensionsFor(UiStyle.miuix),
      );

  static ThemeData get _miuixDark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: miuixDarkPrimary,
          onPrimary: miuixDarkOnPrimary,
          primaryContainer: miuixDarkPrimaryContainer,
          onPrimaryContainer: miuixDarkOnPrimaryContainer,
          secondary: miuixDarkSecondary,
          secondaryContainer: miuixDarkSecondaryContainer,
          tertiary: miuixDarkTertiary,
          tertiaryContainer: miuixDarkTertiaryContainer,
          background: miuixDarkBackground,
          surface: miuixDarkSurface,
          surfaceContainer: miuixDarkSurfaceContainer,
          surfaceContainerHighest: miuixDarkSurfaceContainerHighest,
          onSurface: miuixDarkOnSurface,
          onSurfaceVariant: miuixDarkOnSurfaceVariant,
          outline: miuixDarkOutline,
          outlineVariant: miuixDarkOutlineVariant,
          error: miuixDarkError,
        ),
        scaffoldBackgroundColor: miuixDarkBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        cardTheme: CardThemeData(
          color: miuixDarkSurfaceContainer,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(_miuixRadiusMedium),
          ),
        ),
        extensions: _extensionsFor(UiStyle.miuix),
      );

  /// 通用：按风格返回圆角半径（供组件层使用）。
  static Radius radiusSmall(UiStyle style) => switch (style) {
        UiStyle.ios => _iosRadiusSmall,
        UiStyle.material3 => _md3RadiusSmall,
        UiStyle.miuix => _miuixRadiusSmall,
      };

  static Radius radiusMedium(UiStyle style) => switch (style) {
        UiStyle.ios => _iosRadiusMedium,
        UiStyle.material3 => _md3RadiusMedium,
        UiStyle.miuix => _miuixRadiusMedium,
      };

  static Radius radiusLarge(UiStyle style) => switch (style) {
        UiStyle.ios => _iosRadiusLarge,
        UiStyle.material3 => _md3RadiusLarge,
        UiStyle.miuix => _miuixRadiusLarge,
      };

  static Radius radiusXLarge(UiStyle style) => switch (style) {
        UiStyle.ios => _iosRadiusXLarge,
        UiStyle.material3 => _md3RadiusXLarge,
        UiStyle.miuix => _miuixRadiusXLarge,
      };

  static Radius radiusFloating(UiStyle style) => switch (style) {
        UiStyle.ios => _iosRadiusFloating,
        UiStyle.material3 => _md3RadiusFloating,
        UiStyle.miuix => _miuixRadiusFloating,
      };
}
