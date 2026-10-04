import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:winwin/pages/setting/theme_notifier.dart';

/// Windows 平台标题栏沉浸模式控制器（对标 PiliPlus）。
///
/// 通过原生 MethodChannel (`winwin/window_title_bar`) 动态调用 Windows 11 DWM API
/// (`DWMWA_USE_IMMERSIVE_DARK_MODE`)，并联动 `windowManager.setBrightness`，
/// 让原生窗口标题栏与应用深浅色模式严格保持一致，
/// 规避设置 `DWMWA_CAPTION_COLOR` 导致的 DWM 最大化白色硬直角边框与缩放僵硬问题，
/// 完美保留原生窗口标题栏的完整手势、Snap Layouts、Mica 材质以及流畅硬件动效。
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

    // 仅在明确检测到暗色环境时主动下发，避免在配置尚未载入时将原生默认暗色误置为浅色
    if (_isCurrentDark()) {
      update(customDark: true);
    }
  }

  /// 移除监听与清理资源。
  void dispose() {
    if (!_initialized) return;
    _initialized = false;
    WidgetsBinding.instance.removeObserver(this);
    ThemeNotifier.instance.removeListener(_onThemeChanged);
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

  /// 与 Flutter 渲染树的主题亮度进行直接对齐（如在 didChangeDependencies 中调用）。
  Future<void> syncWithTheme(Brightness brightness) {
    return update(customDark: brightness == Brightness.dark);
  }

  /// 更新标题栏为当前主题对应的深色或浅色原生沉浸模式（对标 PiliPlus）。
  ///
  /// 仅通过 `DWMWA_USE_IMMERSIVE_DARK_MODE` 切换深浅色，杜绝注入 `DWMWA_CAPTION_COLOR`，
  /// 以免破坏 Windows 11 原生 DWM 硬件合成管线并在最大化过渡时产生白色硬直角边框。
  Future<void> update({
    Color? customColor,
    Color? customTextColor,
    bool? customDark,
  }) async {
    if (!Platform.isWindows) return;

    final isDark = customDark ?? _isCurrentDark();

    try {
      await Future.wait([
        _channel.invokeMethod('setTitleBarColor', {
          'dark': isDark,
        }),
        windowManager.setBrightness(isDark ? Brightness.dark : Brightness.light),
      ]);
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
