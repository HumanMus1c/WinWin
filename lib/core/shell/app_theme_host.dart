import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart' show MiuixColors;

import 'package:winwin/theme/app_chrome.dart';
import 'package:winwin/theme/app_shapes.dart';
import 'package:winwin/theme/app_typography.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/miuix_theme_bridge.dart';

/// 应用文本样式面（取代 Material `textTheme` 读取）。
///
/// 只包含项目实际使用的 10 个槽位；取值由过渡期 `ThemeData.textTheme`
/// （M3 Typography + 应用字体族注入）派生 → 与迁移前**逐字段一致**（零漂移）。
/// B7 摘除 material_ui 时改为内联常量（派生入口在 app_theme.dart，随其退役）。
@immutable
class AppTextStyles {
  const AppTextStyles({
    this.titleLarge,
    this.titleMedium,
    this.titleSmall,
    this.bodyLarge,
    this.bodyMedium,
    this.bodySmall,
    this.labelLarge,
    this.labelMedium,
    this.labelSmall,
    this.headlineSmall,
  });

  final TextStyle? titleLarge;
  final TextStyle? titleMedium;
  final TextStyle? titleSmall;
  final TextStyle? bodyLarge;
  final TextStyle? bodyMedium;
  final TextStyle? bodySmall;
  final TextStyle? labelLarge;
  final TextStyle? labelMedium;
  final TextStyle? labelSmall;
  final TextStyle? headlineSmall;

  /// 未挂宿主/未注入时的兜底（空样式；正常路径由 AppShell 注入真实值）。
  static const AppTextStyles fallback = AppTextStyles();
}

/// 应用调色板（取代 Material `ColorScheme` 的读取面）。
///
/// 字段名与 `ColorScheme` **一一对齐**，便于迁移期做纯机械替换：
/// `Theme.of(context).colorScheme.X` → `AppThemeHost.of(context).colors.X`。
///
/// 取值**全部来自项目调色板常量**（theme/colors.dart 的 `miuixLight*/miuixDark*`，
/// 与过渡期 ThemeData 的 ColorScheme 同源）→ 迁移零视觉漂移。
@immutable
class AppPalette {
  const AppPalette({
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.tertiaryContainer,
    required this.surface,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
    required this.outlineVariant,
    required this.background,
    required this.onBackground,
    required this.error,
    required this.onError,
    required this.inverseSurface,
    required this.onInverseSurface,
    required this.scrim,
  });

  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color secondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;
  final Color tertiary;
  final Color tertiaryContainer;
  final Color surface;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color outline;
  final Color outlineVariant;
  final Color background;
  final Color onBackground;
  final Color error;
  final Color onError;

  /// 反色面（亮色主题用深卡、暗色主题用亮卡；Toast 等反色卡使用）。
  final Color inverseSurface;

  /// 反色面上的内容色。
  final Color onInverseSurface;

  /// 遮罩色（对话框/弹层 barrier）。
  final Color scrim;

  static const AppPalette light = AppPalette(
    primary: miuixLightPrimary,
    onPrimary: miuixLightOnPrimary,
    primaryContainer: miuixLightPrimaryContainer,
    onPrimaryContainer: miuixLightOnPrimaryContainer,
    secondary: miuixLightSecondary,
    secondaryContainer: miuixLightSecondaryContainer,
    // M3 基线值（项目未覆写该字段）
    onSecondaryContainer: Color(0xFF1D192B),
    tertiary: miuixLightTertiary,
    tertiaryContainer: miuixLightTertiaryContainer,
    surface: miuixLightSurface,
    // M3 基线值（迁移前 ColorScheme.light() 的默认，项目未覆写该字段）
    surfaceContainerLow: Color(0xFFF7F2FA),
    surfaceContainer: miuixLightSurfaceContainer,
    // M3 基线值（项目未覆写该字段）
    surfaceContainerHigh: Color(0xFFECE6F0),
    surfaceContainerHighest: miuixLightSurfaceContainerHighest,
    onSurface: miuixLightOnSurface,
    onSurfaceVariant: miuixLightOnSurfaceVariant,
    outline: miuixLightOutline,
    outlineVariant: miuixLightOutlineVariant,
    background: miuixLightBackground,
    onBackground: miuixLightOnSurface,
    error: miuixLightError,
    onError: miuixLightOnPrimary,
    // M3 基线值（项目未覆写这两个反色字段；Toast 反色卡取此处）
    inverseSurface: Color(0xFF313033),
    onInverseSurface: Color(0xFFF4EFF4),
    scrim: Color(0xFF000000),
  );

  static const AppPalette dark = AppPalette(
    primary: miuixDarkPrimary,
    onPrimary: miuixDarkOnPrimary,
    primaryContainer: miuixDarkPrimaryContainer,
    onPrimaryContainer: miuixDarkOnPrimaryContainer,
    secondary: miuixDarkSecondary,
    secondaryContainer: miuixDarkSecondaryContainer,
    // M3 基线值（项目未覆写该字段）
    onSecondaryContainer: Color(0xFFE8DEF8),
    tertiary: miuixDarkTertiary,
    tertiaryContainer: miuixDarkTertiaryContainer,
    surface: miuixDarkSurface,
    // M3 基线值（迁移前 ColorScheme.dark() 的默认，项目未覆写该字段）
    surfaceContainerLow: Color(0xFF1D1B20),
    surfaceContainer: miuixDarkSurfaceContainer,
    // M3 基线值（项目未覆写该字段）
    surfaceContainerHigh: Color(0xFF2B2930),
    surfaceContainerHighest: miuixDarkSurfaceContainerHighest,
    onSurface: miuixDarkOnSurface,
    onSurfaceVariant: miuixDarkOnSurfaceVariant,
    outline: miuixDarkOutline,
    outlineVariant: miuixDarkOutlineVariant,
    background: miuixDarkBackground,
    onBackground: miuixDarkOnSurface,
    error: miuixDarkError,
    onError: Color(0xFF000000),
    // M3 基线值（项目未覆写这两个反色字段）
    inverseSurface: Color(0xFFE6E1E5),
    onInverseSurface: Color(0xFF313033),
    scrim: Color(0xFF000000),
  );

  /// 按明暗取调色板（静态单例，供 [AppTokens] 直接引用）。
  static AppPalette forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

/// 应用主题取用通道（MD3 库级退役的"主题宿主"替身）。
///
/// 取代 `Theme.of(context).colorScheme` / `Theme.of(context).extension<X>()`
/// 这两条 Material 通道：明暗、配色（[AppPalette]）、设计 Token
/// （AppShapes/AppTypography/AppChrome）统一由 [AppThemeHost] 供给，
/// 读取方一律走 `AppThemeHost.of(context)`。
///
/// 需要 flutter_miuix 专有配色语义（如 `windowDimming`）时用 [miuix]。
@immutable
class AppTokens {
  const AppTokens({
    required this.brightness,
    required this.colors,
    required this.miuix,
    required this.shapes,
    required this.typography,
    required this.chrome,
    this.text = AppTextStyles.fallback,
  });

  /// 当前明暗（来源：ThemeNotifier 解析后的最终态）。
  final Brightness brightness;

  /// 项目调色板（取代 `colorScheme`）。
  final AppPalette colors;

  /// flutter_miuix 桥接配色（Miuix 专有语义入口）。
  final MiuixColors miuix;

  /// 形状 Token。
  final AppShapes shapes;

  /// 字体/文本 Token。
  final AppTypography typography;

  /// 外壳/层级 Token。
  final AppChrome chrome;

  /// 文本样式面（取代 `textTheme`；由 AppShell 注入过渡期派生值）。
  final AppTextStyles text;

  /// 是否深色。
  bool get isDark => brightness == Brightness.dark;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppTokens &&
          other.brightness == brightness &&
          identical(other.colors, colors) &&
          identical(other.miuix, miuix) &&
          other.shapes == shapes &&
          other.typography == typography &&
          other.chrome == chrome;

  @override
  int get hashCode =>
      Object.hash(brightness, colors, miuix, shapes, typography, chrome);
}

/// 主题宿主：把 [AppTokens] 注入整树（挂载于 Navigator 之上，覆盖全部路由）。
class AppThemeHost extends InheritedWidget {
  const AppThemeHost({super.key, required this.tokens, required super.child});

  final AppTokens tokens;

  /// 按明暗构造一套 Token（调色板取项目常量，Token 数据零改动）。
  ///
  /// [textStyles] 由应用壳注入（过渡期从 ThemeData 派生；未注入时用空兜底）。
  static AppTokens tokensFor(
    Brightness brightness, {
    AppTextStyles textStyles = AppTextStyles.fallback,
  }) =>
      AppTokens(
        brightness: brightness,
        colors: AppPalette.forBrightness(brightness),
        miuix: brightness == Brightness.dark
            ? miuixBridgeDarkColors()
            : miuixBridgeLightColors(),
        shapes: AppShapes.miuix,
        typography: AppTypography.miuix,
        chrome: AppChrome.miuix,
        text: textStyles,
      );

  /// 取当前 Token；未挂宿主时按平台亮度回退（防测试/未包裹子树崩溃）。
  static AppTokens of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppThemeHost>()?.tokens ??
      tokensFor(MediaQuery.platformBrightnessOf(context));

  @override
  bool updateShouldNotify(AppThemeHost oldWidget) =>
      oldWidget.tokens != tokens;
}
