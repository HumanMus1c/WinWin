import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'package:winwin/core/storage/storage_pref.dart';

/// 桌面平台原生全屏控制器（对标 PiliPlus `enterDesktopFullScreen` / `exitDesktopFullScreen` 架构）。
///
/// 通过原生 Win32 Runner（`winwin/fullscreen`）直接接管窗口非客户区与尺寸计算，
/// 完美规避 `window_manager` 剥离 `WS_MAXIMIZEBOX` 与工作区钳制导致的无法占满显示器、
/// 任务栏/标题栏遮挡以及恢复按钮置灰等已知缺陷。
///
/// 沉浸式标题栏联动（对标 PiliPlus 全屏切换 TitleBarStyle）：
/// 全屏期间切回 `normal` 样式，规避 window_manager 隐藏标题栏分支给客户区
/// 增加 8px 内缩（否则全屏四周出现边缘带）；退出全屏恢复 `hidden`。
class DesktopFullscreen {
  DesktopFullscreen._();

  static const MethodChannel _channel = MethodChannel('winwin/fullscreen');
  static bool _isFullScreen = false;

  /// 当前是否处于显示器原生全屏状态。
  static bool get isFullScreen => _isFullScreen;

  /// 全屏状态通知（供 UI 层控制沉浸标题条显隐）。
  static final ValueNotifier<bool> fullScreenNotifier =
      ValueNotifier<bool>(false);

  /// 进入显示器原生全屏模式。
  static Future<void> enter() async {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return;
    if (_isFullScreen) return;
    _isFullScreen = true;
    fullScreenNotifier.value = true;
    try {
      await _channel.invokeMethod('enterFullScreen');
      if (Pref.immersiveTitleBar) {
        await windowManager.setTitleBarStyle(TitleBarStyle.normal);
      }
    } catch (_) {}
  }

  /// 退出显示器原生全屏模式。
  static Future<void> exit() async {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return;
    if (!_isFullScreen) return;
    _isFullScreen = false;
    try {
      if (Pref.immersiveTitleBar) {
        await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      }
      await _channel.invokeMethod('exitFullScreen');
    } catch (_) {}
    fullScreenNotifier.value = false;
  }

  /// 切换显示器原生全屏状态。
  static Future<void> toggle() async {
    if (_isFullScreen) {
      await exit();
    } else {
      await enter();
    }
  }
}
