import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:winwin/pages/setting/theme_notifier.dart';
import 'package:winwin/theme/app_theme.dart';
import 'package:winwin/theme/ui_style_notifier.dart';

/// Windows 平台标题栏沉浸色彩控制器。
///
/// 通过原生 MethodChannel (`winwin/window_title_bar`) 动态调用 Windows 11 DWM API
/// (`DWMWA_CAPTION_COLOR`, `DWMWA_TEXT_COLOR`, `DWMWA_USE_IMMERSIVE_DARK_MODE`)，
/// 使系统原生窗口标题栏背景与应用主窗口的 Scaffold 背景色以及深浅色模式严格保持一致，
/// 达到无缝沉浸视觉效果，同时保留原生窗口标题栏的完整手势、Snap Layouts 以及窗口控制按钮功能。
class TitleBarController with WidgetsBindingObserver {
  TitleBarController._();
  static final TitleBarController instance = TitleBarController._();

  static const MethodChannel _channel =
      MethodChannel('winwin/window_title_bar');

  bool _initialized = false;

  /// 初始化并挂载主题与样式监听。
  void init() {
    if (!Platform.isWindows) return;
    if (_initialized) return;
    _initialized = true;

    WidgetsBinding.instance.addObserver(this);
    ThemeNotifier.instance.addListener(_onThemeChanged);
    UiStyleNotifier.instance.addListener(_onThemeChanged);

    // 初始应用当前主题色彩
    update();
  }

  /// 移除监听与清理资源。
  void dispose() {
    if (!_initialized) return;
    _initialized = false;
    WidgetsBinding.instance.removeObserver(this);
    ThemeNotifier.instance.removeListener(_onThemeChanged);
    UiStyleNotifier.instance.removeListener(_onThemeChanged);
  }

  @override
  void didChangePlatformBrightness() {
    if (ThemeNotifier.instance.value == ThemeMode.system) {
      update();
    }
  }

  void _onThemeChanged() {
    update();
  }

  /// 更新标题栏颜色为指定颜色或当前主题对应的 Scaffold 背景色。
  Future<void> update({
    Color? customColor,
    Color? customTextColor,
    bool? customDark,
  }) async {
    if (!Platform.isWindows) return;

    final isDark = customDark ?? _isCurrentDark();
    final uiStyle = UiStyleNotifier.instance.value;
    final theme =
        isDark ? AppTheme.darkFor(uiStyle) : AppTheme.lightFor(uiStyle);

    final bgColor = customColor ?? theme.scaffoldBackgroundColor;
    final textColor = customTextColor ??
        (isDark ? const Color(0xFFE8E8E8) : const Color(0xFF18191C));

    try {
      await _channel.invokeMethod('setTitleBarColor', {
        'color': bgColor.toARGB32() & 0xFFFFFF,
        'textColor': textColor.toARGB32() & 0xFFFFFF,
        'dark': isDark,
      });
    } catch (_) {
      // 忽略不支持平台版本或通道未就绪异常
    }
  }

  bool _isCurrentDark() {
    final mode = ThemeNotifier.instance.value;
    if (mode == ThemeMode.dark) return true;
    if (mode == ThemeMode.light) return false;
    return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
  }
}
