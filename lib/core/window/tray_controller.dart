import 'dart:async';

import 'package:window_manager/window_manager.dart';

import 'package:winwin/core/window/app_exit.dart';
import 'package:winwin/core/window/native_tray.dart';

/// 系统托盘控制器。
///
/// 托盘图标**恒显**（不再是可配置项）：进程存活期间保持可见，直至真正退出。
/// - [init] 启动时挂原生事件回调并显示图标；
/// - [refresh] 真正退出过程中请求隐藏，其余情况保持可见；
/// - [isReallyExiting] 供窗口关闭逻辑判断是否放行真正退出
///   （托盘「退出」菜单触发时为真）。
class TrayController {
  TrayController._();
  static final TrayController instance = TrayController._();

  bool _inited = false;
  bool _reallyExiting = false;

  /// 启动初始化（幂等）。需在 windowManager 就绪后调用。
  Future<void> init() async {
    if (_inited) return;
    _inited = true;
    NativeTray.instance.onEvent = _onTrayEvent;
    await refresh();
  }

  /// 同步托盘图标可见性（托盘恒显；仅真正退出过程中隐藏）。
  Future<void> refresh() async {
    await NativeTray.instance.setVisible(!_reallyExiting);
  }

  bool get isReallyExiting => _reallyExiting;

  Future<void> _onTrayEvent(String event) async {
    switch (event) {
      case 'show':
        await windowManager.show();
        await windowManager.focus();
      case 'exit':
        _reallyExiting = true;
        unawaited(AppExit.exit());
    }
  }
}