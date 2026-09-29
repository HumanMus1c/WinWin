import 'package:flutter/material.dart';

/// 应用级 ScaffoldMessenger 句柄（挂载于 `MaterialApp.scaffoldMessengerKey`）。
///
/// 供没有 BuildContext 的异步/深层调用点弹提示使用（例如网络错误 toast）。
/// 取代此前与纯 MaterialApp 架构不兼容、会抛异步异常的 GetX Snackbar。
final GlobalKey<ScaffoldMessengerState> appScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// 显示一条应用级 SnackBar（最新优先，先收起上一条）。
///
/// 启动早期 ScaffoldMessenger 尚未挂载时静默忽略。
void showAppSnackBar(String message) {
  final messenger = appScaffoldMessengerKey.currentState;
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
