import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'core/bootstrap.dart';
import 'pages/setting/theme_notifier.dart';
import 'pages/video/desktop_pip.dart';
import 'theme/app_theme.dart';
import 'ui/app.dart';

/// 全局路由观察器，供 VideoDetailPage 监听 push/pop 事件，
/// 在页面被覆盖时暂停播放器、返回时恢复播放。
final RouteObserver<PageRoute<dynamic>> routeObserver =
    RouteObserver<PageRoute<dynamic>>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Phase 4.6：初始化桌面伪 PiP 窗口管理器。
  unawaited(DesktopPipController.instance.ensureInitialized());
  // The video player kernel (fvp/mdk) needs no manual init here: the fvp
  // plugin's dartPluginClass auto-registers on startup (mdk key + globals).
  // The Windows runner shows the window only after the first frame renders,
  // so bootstrap (Hive → accounts → Dio) must not block runApp(). Controllers
  // await ensureBootstrap() themselves before touching the network.
  unawaited(
    ensureBootstrap().then((_) => ThemeNotifier.instance.refresh()),
  );
  runApp(const WinWinApp());
}

class WinWinApp extends StatelessWidget {
  const WinWinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeNotifier.instance,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: 'WinWin — BiliPai Desktop Port',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeMode,
          navigatorObservers: [routeObserver],
          home: const AppRoot(),
        );
      },
    );
  }
}
