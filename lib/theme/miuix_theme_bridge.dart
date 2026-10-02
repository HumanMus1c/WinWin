/// Miuix 主题桥接（flutter_miuix 分阶段替换 · 阶段1）。
///
/// `uiStyle == UiStyle.miuix` 时由 main.dart 在整树之上提供 [MiuixTheme]：
/// - 配色：以 flutter_miuix 默认 `MiuixColors` 为底，逐字段覆盖 colors.dart
///   中已有的 miuixLight*/miuixDark* 调色板，保持替换前后的视觉连续性；
/// - 字体：`defaultTextStyles()` 全 14 字段注入 AppFontNotifier 的字体族；
/// - 覆盖日志：进入 miuix 风格 / 明暗或字体切换时落 `Coverage` 标签日志，
///   供实机取证（Release 可查，grep `miuixAdopt`）。
///
/// 未映射字段（secondary/onSecondary 与 disabled* 族等）保留 flutter_miuix
/// 默认值：WinWin 调色板没有与之等效的 Miuix 语义 token，且 HyperOS 关闭态
/// 开关轨道本就依赖默认浅灰/深灰；实机对照后可按需增补。
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

import 'package:winwin/core/log/app_logger.dart';
import 'package:winwin/theme/colors.dart';

/// 浅色桥接配色（字段映射说明见文件头注释）。
MiuixColors miuixBridgeLightColors() => lightColorScheme().copy(
      primary: miuixLightPrimary,
      onPrimary: miuixLightOnPrimary,
      primaryContainer: miuixLightPrimaryContainer,
      onPrimaryContainer: miuixLightOnPrimaryContainer,
      tertiaryContainer: miuixLightTertiaryContainer,
      background: miuixLightBackground,
      onBackground: miuixLightOnSurface, // 近似：WinWin 无独立 onBackground token
      surface: miuixLightSurface,
      onSurface: miuixLightOnSurface,
      surfaceContainer: miuixLightSurfaceContainer,
      surfaceContainerHighest: miuixLightSurfaceContainerHighest,
      outline: miuixLightOutline,
      dividerLine: miuixLightOutlineVariant, // 近似：分隔线取 outlineVariant
      error: miuixLightError,
    );

/// 深色桥接配色。
MiuixColors miuixBridgeDarkColors() => darkColorScheme().copy(
      primary: miuixDarkPrimary,
      onPrimary: miuixDarkOnPrimary,
      primaryContainer: miuixDarkPrimaryContainer,
      onPrimaryContainer: miuixDarkOnPrimaryContainer,
      tertiaryContainer: miuixDarkTertiaryContainer,
      background: miuixDarkBackground,
      onBackground: miuixDarkOnSurface, // 近似：同上
      surface: miuixDarkSurface,
      onSurface: miuixDarkOnSurface,
      surfaceContainer: miuixDarkSurfaceContainer,
      surfaceContainerHighest: miuixDarkSurfaceContainerHighest,
      outline: miuixDarkOutline,
      dividerLine: miuixDarkOutlineVariant, // 近似：同上
      error: miuixDarkError,
    );

/// 桥接文本样式：`fontFamily` 非空时注入全部 14 个字段。
MiuixTextStyles miuixBridgeTextStyles(String? fontFamily) {
  final base = defaultTextStyles();
  if (fontFamily == null) return base;
  TextStyle withFont(TextStyle style) => style.copyWith(fontFamily: fontFamily);
  return base.copy(
    main: withFont(base.main),
    paragraph: withFont(base.paragraph),
    body1: withFont(base.body1),
    body2: withFont(base.body2),
    button: withFont(base.button),
    footnote1: withFont(base.footnote1),
    footnote2: withFont(base.footnote2),
    headline1: withFont(base.headline1),
    headline2: withFont(base.headline2),
    subtitle: withFont(base.subtitle),
    title1: withFont(base.title1),
    title2: withFont(base.title2),
    title3: withFont(base.title3),
    title4: withFont(base.title4),
  );
}

/// 在 miuix 风格下向整树提供桥接后的 [MiuixTheme]。
///
/// 由 main.dart 的 `MaterialApp.builder` 在 `uiStyle == UiStyle.miuix` 时
/// 包裹（位于 Navigator 之上，覆盖全部路由）；明暗由调用方解析
/// （含 ThemeMode 强制态）后传入。
class MiuixThemeScope extends StatefulWidget {
  const MiuixThemeScope({
    super.key,
    required this.isDark,
    this.fontFamily,
    required this.child,
  });

  /// 当前是否深色（由 ThemeMode + 平台亮度解析后传入）。
  final bool isDark;

  /// 应用字体族（AppFontNotifier）；null 表示系统默认。
  final String? fontFamily;

  final Widget child;

  @override
  State<MiuixThemeScope> createState() => _MiuixThemeScopeState();
}

class _MiuixThemeScopeState extends State<MiuixThemeScope> {
  @override
  void initState() {
    super.initState();
    _logCoverage('active');
  }

  @override
  void didUpdateWidget(MiuixThemeScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isDark != widget.isDark ||
        oldWidget.fontFamily != widget.fontFamily) {
      _logCoverage('changed');
    }
  }

  void _logCoverage(String phase) {
    AppLogger.w(
      'Coverage',
      'miuixAdopt: scope $phase isDark=${widget.isDark} '
      'font=${widget.fontFamily ?? 'system'}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final textStyles = miuixBridgeTextStyles(widget.fontFamily);
    final data = widget.isDark
        ? MiuixThemeData.dark(
            colors: miuixBridgeDarkColors(),
            textStyles: textStyles,
          )
        : MiuixThemeData.light(
            colors: miuixBridgeLightColors(),
            textStyles: textStyles,
          );
    return MiuixTheme(data: data, child: widget.child);
  }
}
