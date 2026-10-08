import 'package:flutter/material.dart' as legacy;
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_theme_host.dart';

/// SDK 材料桥接容器（自建版，取代 material_ui 的
/// `MaterialUiCompatibilityBridge`）。
///
/// 用途：flutter_miuix 的 `MiuixTextField` 内部用 **SDK `flutter/material`** 的
/// `TextField` 实现，需要三样东西才能工作：
/// 1. SDK `Material` 祖先（debug 断言 "No Material widget found"）；
/// 2. SDK `ThemeData`（文本/光标/选择色默认值）；
/// 3. SDK `MaterialLocalizations`（release 下缺失会空断言崩溃 → 渲染成大灰块）。
///
/// 本类用 [AppTokens] 的配色构造最小 SDK ThemeData，并以 `Localizations.override`
/// 注入 Global* 本地化（与旧桥的 delegates 一致），作用域仅包住需要的子树。
///
/// L0 阶段：本文件仍允许 import SDK material（flutter_miuix 的实现细节），
/// 但**不**依赖 material_ui；调用点在 B2/B7 批次从旧桥切到这里。
class MiuixCompat extends StatelessWidget {
  const MiuixCompat({super.key, required this.child, this.delegates});

  final Widget child;

  /// 本地化委托；null 时用与旧桥一致的 Global* 三件套。
  final List<LocalizationsDelegate<dynamic>>? delegates;

  static const List<LocalizationsDelegate<dynamic>> _defaultDelegates =
      <LocalizationsDelegate<dynamic>>[
    GlobalCupertinoLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final brightness = tokens.brightness;
    final delegates = this.delegates ?? _defaultDelegates;
    // `Localizations.override` 依赖祖先 Localizations 合并 delegates：
    // 存在祖先时用它（保留应用既有本地化），否则退化为独立 Localizations
    // （如单测 / 脱离应用壳的子树，避免断言崩溃）。
    final Locale? locale = Localizations.maybeLocaleOf(context);
    final Widget localized = locale == null
        ? Localizations(
            locale: const Locale('zh', 'CN'),
            delegates: delegates,
            child: child,
          )
        : Localizations.override(
            context: context,
            delegates: delegates,
            child: child,
          );
    return legacy.Theme(
      data: legacy.ThemeData(
        useMaterial3: true,
        brightness: brightness,
        colorScheme: legacy.ColorScheme.fromSeed(
          seedColor: tokens.colors.primary,
          brightness: brightness,
        ),
        scaffoldBackgroundColor: legacy.Colors.transparent,
        textSelectionTheme: legacy.TextSelectionThemeData(
          cursorColor: tokens.colors.primary,
          selectionColor: tokens.colors.primary.withValues(alpha: 0.3),
        ),
      ),
      child: legacy.Material(
        type: legacy.MaterialType.transparency,
        child: localized,
      ),
    );
  }
}
