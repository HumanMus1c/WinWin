import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/core/storage/storage_key.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/core/window/desktop_fullscreen.dart';
import 'package:winwin/core/window/tray_controller.dart';
import 'package:winwin/pages/video/desktop_pip.dart';

/// 窗口位置/大小记忆控制器。
///
/// 启动时从持久化存储恢复上次的窗口尺寸、位置与最大化状态；
/// 运行中监听窗口事件，防抖写回（Resize/Move 结束 500ms 后保存）。
///
/// 注意：
/// - PiP 模式下不保存（避免把 480x270 的小窗状态当作用户偏好）；
/// - 最大化状态下只记录标志位，不覆盖常规尺寸/位置。
class WindowStateController with WindowListener {
  WindowStateController._();
  static final WindowStateController instance = WindowStateController._();

  static const Size _minSize = Size(640, 400);

  bool _listening = false;
  Timer? _saveTimer;

  Size get savedWindowSize {
    final raw = GStorage.setting.get(SettingBoxKey.windowSize);
    return _readSize(raw) ?? const Size(1280, 720);
  }

  bool get isMaximized =>
      GStorage.setting.get(SettingBoxKey.isWindowMaximized, defaultValue: false) == true;

  /// 挂载窗口事件监听（在窗口初始化并显示后调用，避免初始化干扰）。
  void startListening() {
    if (!_listening) {
      windowManager.addListener(this);
      // 拦截关闭：交由 onWindowClose 决定「最小化到托盘」还是真正退出。
      windowManager.setPreventClose(true);
      _listening = true;
    }
  }

  /// 恢复窗口状态并开始监听（需 [GStorage.init] 完成后调用）。
  Future<void> restoreAndListen() async {
    // 保证 windowManager 已初始化（内部幂等）。
    await DesktopPipController.instance.ensureInitialized();
    startListening();

    final box = GStorage.setting;
    final maximized = box.get(SettingBoxKey.isWindowMaximized, defaultValue: false) == true;
    final size = _readSize(box.get(SettingBoxKey.windowSize));
    final position = _readOffset(box.get(SettingBoxKey.windowPosition));
    if (maximized) {
      await windowManager.maximize();
      if (!await windowManager.isVisible()) {
        await windowManager.show();
        await windowManager.focus();
      }
      return;
    }
    if (size != null) {
      await windowManager.setSize(size);
    }
    if (position != null) {
      // 位置越出屏幕（如拔掉外接显示器）时不恢复，使用默认位置。
      final screen = _screenLogicalSize();
      if (screen == null || _onScreen(position, size ?? const Size(1280, 800), screen)) {
        await windowManager.setPosition(position);
      }
    }
    if (!await windowManager.isVisible()) {
      await windowManager.show();
      await windowManager.focus();
    }
  }

  Size? _readSize(dynamic raw) {
    if (raw is List && raw.length >= 2) {
      final w = (raw[0] as num?)?.toDouble() ?? 0;
      final h = (raw[1] as num?)?.toDouble() ?? 0;
      if (w >= _minSize.width && h >= _minSize.height) return Size(w, h);
    }
    return null;
  }

  Offset? _readOffset(dynamic raw) {
    if (raw is List && raw.length >= 2) {
      return Offset(
        (raw[0] as num?)?.toDouble() ?? 0,
        (raw[1] as num?)?.toDouble() ?? 0,
      );
    }
    return null;
  }

  Size? _screenLogicalSize() {
    final views = PlatformDispatcher.instance.views;
    if (views.isEmpty) return null;
    final view = views.first;
    return view.physicalSize / view.devicePixelRatio;
  }

  /// 窗口左上角仍留有可见区域即认为在屏幕内。
  bool _onScreen(Offset pos, Size size, Size screen) {
    return pos.dx > -size.width + 100 &&
        pos.dy > -size.height + 100 &&
        pos.dx < screen.width - 100 &&
        pos.dy < screen.height - 100;
  }

  /// 防抖保存常规尺寸/位置（全屏/最大化/PiP 状态下跳过）。
  void _scheduleSave() {
    if (DesktopFullscreen.isFullScreen) return;
    if (DesktopPipController.instance.isInPipMode) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _saveNormalState);
  }

  Future<void> _saveNormalState() async {
    try {
      if (DesktopFullscreen.isFullScreen) return;
      if (await windowManager.isMaximized()) return;
      if (DesktopPipController.instance.isInPipMode) return;
      final size = await windowManager.getSize();
      final position = await windowManager.getPosition();
      await GStorage.setting.put(SettingBoxKey.windowSize, [size.width, size.height]);
      await GStorage.setting.put(
          SettingBoxKey.windowPosition, [position.dx, position.dy]);
    } catch (_) {
      // 保存失败不影响使用，下次调整窗口时重试。
    }
  }

  @override
  void onWindowResized() => _scheduleSave();

  @override
  void onWindowMoved() => _scheduleSave();

  @override
  void onWindowMaximize() {
    _saveTimer?.cancel();
    GStorage.setting.put(SettingBoxKey.isWindowMaximized, true);
  }

  @override
  void onWindowUnmaximize() {
    GStorage.setting.put(SettingBoxKey.isWindowMaximized, false);
    _scheduleSave();
  }

  @override
  void onWindowClose() {
    // 关闭前立即落盘一次（取消未触发的防抖）。
    _saveTimer?.cancel();
    unawaited(_saveNormalState());

    // 「退出时最小化到托盘」：托盘可用且非托盘菜单触发的真正退出时，
    // 隐藏窗口（进程保活到托盘）；否则放行真正退出。
    if (Pref.minimizeOnExit &&
        Pref.showTrayIcon &&
        !TrayController.instance.isReallyExiting) {
      unawaited(windowManager.hide());
      return;
    }
    unawaited(windowManager.destroy());
  }
}
