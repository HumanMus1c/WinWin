import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart' show MiuixColors;

import 'package:winwin/theme/app_chrome.dart';
import 'package:winwin/theme/app_shapes.dart';
import 'package:winwin/theme/app_typography.dart';
import 'package:winwin/theme/miuix_theme_bridge.dart';

/// 应用主题取用通道（MD3 库级退役的"主题宿主"替身）。
///
/// 取代 `Theme.of(context).colorScheme` / `Theme.of(context).extension<X>()`
/// 这两条 Material 通道：明暗、配色（flutter_miuix `MiuixColors`）、
/// 设计 Token（AppShapes/AppTypography/AppChrome）统一由 [AppThemeHost]
/// 供给，读取方一律走 `AppTokens.of(context)`。
///
/// L0 阶段（双轨并存）：本文件**零 Material 依赖**，可先于摘除流程独立落地；
/// 组件在 B2 批次分批从 `Theme.of` 切到 [AppTokens.of] 即可。
@immutable
class AppTokens {
  const AppTokens({
    required this.brightness,
    required this.colors,
    required this.shapes,
    required this.typography,
    required this.chrome,
  });

  /// 当前明暗（来源：ThemeNotifier 解析后的最终态）。
  final Brightness brightness;

  /// 桥接后的 Miuix 配色（唯一配色源，见 miuix_theme_bridge）。
  final MiuixColors colors;

  /// 形状 Token。
  final AppShapes shapes;

  /// 字体/文本 Token。
  final AppTypography typography;

  /// 外壳/层级 Token。
  final AppChrome chrome;

  /// 是否深色。
  bool get isDark => brightness == Brightness.dark;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppTokens &&
          other.brightness == brightness &&
          other.colors == colors &&
          other.shapes == shapes &&
          other.typography == typography &&
          other.chrome == chrome;

  @override
  int get hashCode =>
      Object.hash(brightness, colors, shapes, typography, chrome);
}

/// 主题宿主：把 [AppTokens] 注入整树（挂载于 Navigator 之上，覆盖全部路由）。
class AppThemeHost extends InheritedWidget {
  const AppThemeHost({super.key, required this.tokens, required super.child});

  final AppTokens tokens;

  /// 按明暗构造一套 Token（配色走既有桥接调色板，Token 数据零改动）。
  static AppTokens tokensFor(Brightness brightness) => AppTokens(
        brightness: brightness,
        colors: brightness == Brightness.dark
            ? miuixBridgeDarkColors()
            : miuixBridgeLightColors(),
        shapes: AppShapes.miuix,
        typography: AppTypography.miuix,
        chrome: AppChrome.miuix,
      );

  /// 取当前 Token；未挂宿主时按平台亮度回退（防测试/未包裹子树崩溃）。
  static AppTokens of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppThemeHost>()?.tokens ??
      tokensFor(MediaQuery.platformBrightnessOf(context));

  @override
  bool updateShouldNotify(AppThemeHost oldWidget) =>
      oldWidget.tokens != tokens;
}
