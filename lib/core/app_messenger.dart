import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 应用级 ScaffoldMessenger 句柄（挂载于 `MaterialApp.scaffoldMessengerKey`）。
///
/// 供没有 BuildContext 的异步/深层调用点弹提示使用（例如网络错误 toast）。
/// 取代此前与纯 MaterialApp 架构不兼容、会抛异步异常的 GetX Snackbar。
final GlobalKey<ScaffoldMessengerState> appScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// 浮层提示卡的最大宽度（含内边距）。
///
/// SnackBar 未显式指定 `width` 时会占满整屏（仅留 margin），因此必须按内容
/// 测量宽度并显式传入 `SnackBar.width`，才能得到"短内容紧凑、长内容限宽换行"
/// 的自适应卡片。
const double _toastMaxWidth = 400;

/// 提示卡内容区水平内边距（单侧）。
const double _toastHorizontalPadding = 20;

/// 提示卡距屏幕两侧的最小总留白（`SnackBar.width` 模式无水平 margin）。
const double _toastScreenInset = 32;

/// 显示一条浮层提示（floating · 深色反色卡）。
///
/// - 宽度自适应内容：短消息为紧凑小卡，长消息在 [_toastMaxWidth] 内换行；
/// - 点击卡片任意处立即关闭；
/// - 同屏仅一条：最新优先（先平滑收起上一条）；
/// - [duration] 缺省 4s；配色 / 圆角 / 浮起位置由各主题 `snackBarTheme` 提供。
void showToast(BuildContext context, String message, {Duration? duration}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  _presentToast(context, messenger, message, duration: duration);
}

/// 显示一条应用级浮层提示（[showToast] 的无 BuildContext 版本）。
///
/// 启动早期 ScaffoldMessenger 尚未挂载时静默忽略。
void showAppSnackBar(String message, {Duration? duration}) {
  final messenger = appScaffoldMessengerKey.currentState;
  if (messenger == null) return;
  _presentToast(messenger.context, messenger, message, duration: duration);
}

void _presentToast(
  BuildContext context,
  ScaffoldMessengerState messenger,
  String message, {
  Duration? duration,
}) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      _buildToast(context, message, () => messenger.hideCurrentSnackBar(), duration: duration),
    );
}

/// 构建统一提示卡：内边距归零让点击区域（[GestureDetector]）铺满整卡，
/// 并按文本测量结果显式指定卡片宽度（自适应内容）。
SnackBar _buildToast(
  BuildContext context,
  String message,
  VoidCallback onDismiss, {
  Duration? duration,
}) {
  final displayText = _breakLongSegments(message);
  return SnackBar(
    width: _measureCardWidth(context, displayText),
    padding: EdgeInsets.zero,
    duration: duration ?? const Duration(seconds: 4),
    content: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onDismiss,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _toastHorizontalPadding,
          vertical: 15,
        ),
        child: Text(displayText),
      ),
    ),
  );
}

/// 按内容测量卡片宽度：取各硬换行段落的最长单行宽，封顶 [_toastMaxWidth]，
/// 并保证不超出屏幕（两侧共留 [_toastScreenInset]）。
double _measureCardWidth(BuildContext context, String text) {
  final theme = Theme.of(context);
  final style = theme.snackBarTheme.contentTextStyle ??
      theme.textTheme.bodyMedium ??
      const TextStyle(fontSize: 14);
  final scaler = MediaQuery.textScalerOf(context);

  var naturalWidth = 0.0;
  for (final line in text.split('\n')) {
    final painter = TextPainter(
      text: TextSpan(text: line, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    naturalWidth = math.max(naturalWidth, painter.size.width);
    painter.dispose();
  }

  final contentWidth = math.min(
    naturalWidth,
    _toastMaxWidth - _toastHorizontalPadding * 2,
  );
  final screenLimit = MediaQuery.sizeOf(context).width - _toastScreenInset;
  return math.min(contentWidth + _toastHorizontalPadding * 2, screenLimit);
}

/// 为超长不可断片段（如 URL）插入零宽空格断点：让换行优先落在
/// `/ ? # & = . _ - :` 等分隔符之后，避免 URL 被字符级硬断或整段撑宽。
String _breakLongSegments(String text) {
  final longToken = RegExp(r'\S{24,}');
  final separators = RegExp(r'([/?#&=._\-:]+)');
  return text.replaceAllMapped(
    longToken,
    (token) => token[0]!.replaceAllMapped(separators, (m) => '${m[1]}\u200B'),
  );
}
