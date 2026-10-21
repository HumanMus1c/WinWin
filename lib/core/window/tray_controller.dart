import 'package:window_manager/window_manager.dart';

import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/core/window/native_tray.dart';

/// 系统托盘控制器。
///
/// 把「显示托盘图标 / 退出时最小化到托盘」两个设置项接到纯原生托盘实现上：
/// - [init] 启动时挂原生事件回调并按设置同步图标可见性；
/// - [refresh] 设置热变更时同步图标可见性；
/// - [isReallyExiting] 供窗口关闭逻辑判断是否放行真正退出
///   （托盘「退出」菜单或未开启「最小化到托盘」时为真）。
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

  /// 同步托盘图标可见性（设置热生效入口）。
  Future<void> refresh() async {
    await NativeTray.instance.setVisible(Pref.showTrayIcon && !_reallyExiting);
  }

  bool get isReallyExiting => _reallyExiting;

  void allowRealExit() => _reallyExiting = true;

  Future<void> _onTrayEvent(String event) async {
    switch (event) {
      case 'show':
        await windowManager.show();
        await windowManager.focus();
      case 'exit':
        _reallyExiting = true;
        await windowManager.destroy();
    }
  }
}