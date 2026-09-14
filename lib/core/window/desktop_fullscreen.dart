import 'dart:io' show Platform;
import 'package:flutter/services.dart';

/// 桌面平台原生全屏控制器（对标 PiliPlus `enterDesktopFullScreen` / `exitDesktopFullScreen` 架构）。
///
/// 通过原生 Win32 Runner（`winwin/fullscreen`）直接接管窗口非客户区与尺寸计算，
/// 完美规避 `window_manager` 剥离 `WS_MAXIMIZEBOX` 与工作区钳制导致的无法占满显示器、
/// 任务栏/标题栏遮挡以及恢复按钮置灰等已知缺陷。
class DesktopFullscreen {
  DesktopFullscreen._();

  static const MethodChannel _channel = MethodChannel('winwin/fullscreen');
  static bool _isFullScreen = false;

  /// 当前是否处于显示器原生全屏状态。
  static bool get isFullScreen => _isFullScreen;

  /// 进入显示器原生全屏模式。
  static Future<void> enter() async {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return;
    if (_isFullScreen) return;
    _isFullScreen = true;
    try {
      await _channel.invokeMethod('enterFullScreen');
    } catch (_) {}
  }

  /// 退出显示器原生全屏模式。
  static Future<void> exit() async {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return;
    if (!_isFullScreen) return;
    _isFullScreen = false;
    try {
      await _channel.invokeMethod('exitFullScreen');
    } catch (_) {}
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
