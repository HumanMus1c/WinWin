import 'package:flutter/material.dart';

/// 应用级 ScaffoldMessenger 句柄（挂载于 `MaterialApp.scaffoldMessengerKey`）。
///
/// 供没有 BuildContext 的异步/深层调用点弹提示使用（例如网络错误 toast）。
/// 取代此前与纯 MaterialApp 架构不兼容、会抛异步异常的 GetX Snackbar。
final GlobalKey<ScaffoldMessengerState> appScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// 统一浮层提示卡的最大宽度（桌面宽屏下长文本自动换行，避免整条过宽）。
const double _toastMaxWidth = 520;

/// 显示一条浮层提示（floating · 深色反色卡）。
///
/// - 点击卡片任意处立即关闭；
/// - 同屏仅一条：最新优先（先平滑收起上一条）；
/// - [duration] 缺省 4s；配色 / 圆角 / 浮起位置由各主题 `snackBarTheme` 提供。
void showToast(BuildContext context, String message, {Duration? duration}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  _presentToast(messenger, message, duration: duration);
}

/// 显示一条应用级浮层提示（[showToast] 的无 BuildContext 版本）。
///
/// 启动早期 ScaffoldMessenger 尚未挂载时静默忽略。
void showAppSnackBar(String message, {Duration? duration}) {
  final messenger = appScaffoldMessengerKey.currentState;
  if (messenger == null) return;
  _presentToast(messenger, message, duration: duration);
}

void _presentToast(
  ScaffoldMessengerState messenger,
  String message, {
  Duration? duration,
}) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      _buildToast(message, () => messenger.hideCurrentSnackBar(), duration: duration),
    );
}

/// 构建统一提示卡：SnackBar 内边距归零，让点击区域（[GestureDetector]）
/// 铺满整张卡片，实现"点击任意处关闭"。
SnackBar _buildToast(
  String message,
  VoidCallback onDismiss, {
  Duration? duration,
}) {
  return SnackBar(
    padding: EdgeInsets.zero,
    duration: duration ?? const Duration(seconds: 4),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _toastMaxWidth),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onDismiss,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          child: Text(message),
        ),
      ),
    ),
  );
}
