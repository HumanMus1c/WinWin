import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/core/storage/storage_key.dart';

/// 桌面伪 PiP 管理器（Phase 4.6）。
///
/// 参照 PiliPlus `enterDesktopPip` / `exitDesktopPip`：通过 windowManager
/// 调整窗口大小、位置、置顶来实现「画中画」效果。
///
/// 进入 PiP：保存当前窗口尺寸/位置 → 缩小到 [pipWidth]x[pipHeight] →
/// 置顶 → 移到屏幕右下角（[setAlignment]）。
/// 退出 PiP：恢复原窗口尺寸/位置 → 取消置顶。
///
/// 自动 PiP（[autoPipEnabled]）：窗口失焦时自动进入，重新聚焦时自动退出。
class DesktopPipController with WindowListener {
  DesktopPipController._();
  static final DesktopPipController instance = DesktopPipController._();

  /// PiP 窗口宽度（16:9 基准）。
  static const double pipWidth = 480;
  /// PiP 窗口高度。
  static const double pipHeight = 270;

  bool _inPip = false;
  /// 当前是否处于 PiP 模式。
  bool get isInPipMode => _inPip;

  /// 进入 PiP 前保存的窗口尺寸（用于退出时恢复）。
  Size? _savedSize;
  /// 进入 PiP 前保存的窗口位置。
  Offset? _savedPosition;

  bool _initialized = false;

  /// 初始化 windowManager 监听（在 main.dart 中调用一次）。
  Future<void> ensureInitialized() async {
    if (_initialized) return;
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    _initialized = true;
  }

  /// 进入桌面 PiP 模式。
  ///
  /// 保存当前窗口状态，缩小窗口并置顶到屏幕右下角。
  /// 已在 PiP 模式时为空操作。
  Future<void> enterPip() async {
    if (!_initialized || _inPip) return;
    // 保存当前窗口尺寸和位置。
    _savedSize = await windowManager.getSize();
    _savedPosition = await windowManager.getPosition();

    // 设置 PiP 窗口尺寸。
    await windowManager.setSize(const Size(pipWidth, pipHeight));
    // 置顶。
    await windowManager.setAlwaysOnTop(true);
    // 移到屏幕右下角。
    await windowManager.setAlignment(Alignment.bottomRight);
    _inPip = true;
    debugPrint('DesktopPip: entered PiP mode');
  }

  /// 退出桌面 PiP 模式，恢复原窗口尺寸和位置。
  Future<void> exitPip() async {
    if (!_initialized || !_inPip) return;
    // 取消置顶。
    await windowManager.setAlwaysOnTop(false);
    // 恢复原窗口尺寸。
    final size = _savedSize;
    if (size != null) {
      await windowManager.setSize(size);
    }
    // 恢复原窗口位置。
    final pos = _savedPosition;
    if (pos != null) {
      await windowManager.setPosition(pos);
    }
    _savedSize = null;
    _savedPosition = null;
    _inPip = false;
    debugPrint('DesktopPip: exited PiP mode');
  }

  /// 切换 PiP 模式。
  Future<void> togglePip() async {
    if (_inPip) {
      await exitPip();
    } else {
      await enterPip();
    }
  }

  // ── WindowListener ──

  @override
  void onWindowFocus() {
    // 窗口重新聚焦时，如果处于 autoPiP 进入的 PiP 模式，自动退出。
    if (_inPip) {
      unawaited(exitPip());
    }
  }
}

/// 判断是否启用了自动 PiP（窗口失焦时自动进入画中画）。
bool get autoPipEnabled => GStorage.setting.get(
      SettingBoxKey.autoPiP,
      defaultValue: false,
    ) as bool;
