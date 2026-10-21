import 'package:flutter/services.dart';

/// 纯原生 Windows 系统托盘的 Dart 桥。
///
/// 与 `windows/runner/tray_icon.cc` 通过 MethodChannel `winwin/tray` 通信：
/// - Dart → 原生：`setTrayVisible`(bool) 显示/隐藏托盘图标；`isTrayVisible` 查询。
/// - 原生 → Dart：`onTrayEvent`("show" | "exit") 托盘交互事件。
///
/// 非 Windows 平台或原生通道不可用（未重新构建 runner）时静默降级，
/// 不影响应用其余功能。
class NativeTray {
  NativeTray._();
  static final NativeTray instance = NativeTray._();

  static const MethodChannel _channel = MethodChannel('winwin/tray');

  /// 托盘事件回调：`show` = 请求显示主窗口；`exit` = 请求真正退出。
  void Function(String event)? onEvent;

  bool _handlerAttached = false;

  void _ensureHandler() {
    if (_handlerAttached) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onTrayEvent') {
        final event = call.arguments as String? ?? 'show';
        onEvent?.call(event);
      }
      return null;
    });
    _handlerAttached = true;
  }

  /// 显示/隐藏原生托盘图标。
  Future<void> setVisible(bool visible) async {
    _ensureHandler();
    try {
      await _channel.invokeMethod<void>('setTrayVisible', visible);
    } catch (_) {
      // 原生通道不可用时忽略（如非 Windows 或 runner 未重建）。
    }
  }

  Future<bool> isVisible() async {
    try {
      final v = await _channel.invokeMethod<bool>('isTrayVisible');
      return v ?? false;
    } catch (_) {
      return false;
    }
  }
}