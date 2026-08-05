import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'ui/app.dart';

void main() {
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
