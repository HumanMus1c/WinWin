import 'package:flutter/foundation.dart' show ValueNotifier;

import 'package:winwin/core/storage/storage_pref.dart';

/// 外观类设置的全局通知器集合。
///
/// 承接三个需要「热生效」的外观设置项（由 `main.dart` 的 [ListenableBuilder]
/// 消费后重建应用壳）：
/// - [isPureBlack]：纯黑主题（深色背景压到纯黑）；
/// - [textScale]：字体大小（全局 `textScaler`，仅文字）；
/// - [uiScale]：界面缩放（整树缩放，方案 A）。
///
/// 与 [ThemeNotifier] 同模式：构造时不访问 [Pref]（此时 Hive 可能尚未初始化），
/// 初值取默认；`ensureBootstrap()` 完成后由调用方 [refresh] 从持久化存储恢复。
abstract final class AppearanceNotifier {
  /// 纯黑主题开关（默认关）。
  static final ValueNotifier<bool> isPureBlack = ValueNotifier<bool>(false);

  /// 字体大小缩放（默认 1.0）。
  static final ValueNotifier<double> textScale = ValueNotifier<double>(1.0);

  /// 界面整体缩放（默认 1.0）。
  static final ValueNotifier<double> uiScale = ValueNotifier<double>(1.0);

  /// 从持久化存储恢复三项设置（bootstrap 完成后调用）。
  static void refresh() {
    isPureBlack.value = Pref.isPureBlackTheme;
    textScale.value = Pref.defaultTextScale;
    uiScale.value = Pref.uiScale;
  }

  /// 设置项写入后同步（供设置页 onChanged / onTap 调用，实现热生效）。
  static void setPureBlack(bool value) => isPureBlack.value = value;

  static void setTextScale(double value) => textScale.value = value;

  static void setUiScale(double value) => uiScale.value = value;
}