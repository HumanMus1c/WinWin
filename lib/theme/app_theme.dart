import 'package:material_ui/material_ui.dart';
import '../core/shell/app_theme_host.dart';
import 'app_chrome.dart';
import 'app_icons.dart';
import 'app_shapes.dart';
import 'app_typography.dart';
import 'colors.dart';
import 'system_font_scanner.dart';

/// App theme — 阶段5d-L4-2 单轨化后恒解析 Miuix ThemeData。
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
  /// 浅色主题（阶段5d-L2 固化：Token 与主题恒为 Miuix 取值；[style] 参数
  /// 保留以兼容调用签名，不再分支）。
  static ThemeData lightFor({String? fontFamily}) =>
      _applyFont(_miuixLight, fontFamily);

  /// 深色主题（阶段5d-L2 固化，同上）。
  static ThemeData darkFor({String? fontFamily}) =>
      _applyFont(_miuixDark, fontFamily);

  /// 派生 [AppTextStyles]（MD3 库级退役 B2-t：取代 `ThemeData.textTheme` 读取面）。
  ///
  /// 取值直接来自过渡期 ThemeData 的 textTheme（M3 Typography + 字体族注入），
  /// 与迁移前**逐字段一致**；B7 摘除 material_ui 时改为内联常量。
  static AppTextStyles textStylesFor(Brightness brightness) {
    final textTheme =
        (brightness == Brightness.dark ? _miuixDark : _miuixLight).textTheme;
    return AppTextStyles(
      titleLarge: textTheme.titleLarge,
      titleMedium: textTheme.titleMedium,
      titleSmall: textTheme.titleSmall,
      bodyLarge: textTheme.bodyLarge,
      bodyMedium: textTheme.bodyMedium,
      bodySmall: textTheme.bodySmall,
      labelLarge: textTheme.labelLarge,
      labelMedium: textTheme.labelMedium,
      labelSmall: textTheme.labelSmall,
      headlineSmall: textTheme.headlineSmall,
    );
  }

  /// 将 [fontFamily]（或字体标识键）注入 [ThemeData] 的 textTheme / primaryTextTheme。
  ///
  /// 自动解析底层 DirectWrite 基础族名。
  static ThemeData _applyFont(ThemeData base, String? fontFamily) {
    if (fontFamily == null || fontFamily.isEmpty) return base;
    final info = SystemFontScanner.getByFamily(fontFamily);
    final family = info?.actualFamily ?? fontFamily;
    return base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: family),
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: family),
    );
  }

  /// 组装设计 Token（阶段5d-L2 固化：恒为 Miuix 取值），挂载到
  /// [ThemeData.extensions]，组件通过 `Theme.of(context).extension<AppShapes>()`
  /// 等读取。
  static Iterable<ThemeExtension<dynamic>> _extensionsFor() => [
        AppShapes.miuix,
        AppTypography.miuix,
        AppChrome.miuix,
      ];

  /// 全局操作图标主题：注入系统 BackButton 与 CloseButton 图标（Miuix 语义）。
  static ActionIconThemeData _actionIconThemeFor() =>
      ActionIconThemeData(
        backButtonIconBuilder: (BuildContext context) =>
            AppIcon(AppIcons.back()),
        closeButtonIconBuilder: (BuildContext context) =>
            AppIcon(AppIcons.clear()),
      );


  // ─────────────────────────── Miuix（阶段5d-L2 起为唯一取值） ───────────────────────────

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
        // 页面转场：Miuix 动效规范（替代 material_ui 平台默认 Zoom 转场——
        // 其缩放会向路由视口外溢出并覆盖沉浸标题条，详见 miuix_page_transitions.dart）；
        // 关掉 kUseMiuixPageTransitions 即回退平台默认值（null = ThemeData 默认）。
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
        dialogTheme: DialogThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(_miuixRadiusLarge),
          ),
        ),
        listTileTheme: ListTileThemeData(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(_miuixRadiusSmall),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          elevation: 6,
          insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(_miuixRadiusMedium),
          ),
          backgroundColor: miuixLightOnSurface,
          contentTextStyle: const TextStyle(
            color: miuixLightSurface,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actionIconTheme: _actionIconThemeFor(),
        extensions: _extensionsFor(),
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
        // 页面转场：同浅色主题（见 _miuixLight 处说明）。
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
        dialogTheme: DialogThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(_miuixRadiusLarge),
          ),
        ),
        listTileTheme: ListTileThemeData(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(_miuixRadiusSmall),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          elevation: 6,
          insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(_miuixRadiusMedium),
          ),
          backgroundColor: miuixDarkOnSurface,
          contentTextStyle: const TextStyle(
            color: miuixDarkSurface,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actionIconTheme: _actionIconThemeFor(),
        extensions: _extensionsFor(),
      );

  /// 通用：按风格返回圆角半径（阶段5d-L2 固化：恒为 Miuix 取值；[style]
  /// 参数保留以兼容调用签名）。
  static Radius radiusSmall() => _miuixRadiusSmall;

  static Radius radiusMedium() => _miuixRadiusMedium;

  static Radius radiusLarge() => _miuixRadiusLarge;

  static Radius radiusXLarge() => _miuixRadiusXLarge;

  static Radius radiusFloating() => _miuixRadiusFloating;
}
