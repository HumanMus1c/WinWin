import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'core/bootstrap.dart';
import 'theme/app_theme.dart';
import 'ui/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The video player kernel (fvp/mdk) needs no manual init here: the fvp
  // plugin's dartPluginClass auto-registers on startup (mdk key + globals).
  // The Windows runner shows the window only after the first frame renders,
  // so bootstrap (Hive → accounts → Dio) must not block runApp(). Controllers
  // await ensureBootstrap() themselves before touching the network.
  unawaited(ensureBootstrap());
  runApp(const WinWinApp());
}

class WinWinApp extends StatelessWidget {
  const WinWinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WinWin — BiliPai Desktop Port',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const AppRoot(),
    );
  }
}
