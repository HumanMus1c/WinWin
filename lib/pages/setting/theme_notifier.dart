import 'dart:ui' show Brightness;

import 'package:flutter/foundation.dart' show ValueNotifier;

import 'package:winwin/core/log/app_logger.dart';
import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/core/storage/storage_key.dart';
import 'package:winwin/core/storage/storage_pref.dart';

/// 主题模式全局通知器。
///
/// 单例 [ValueNotifier<ThemeModeType>]，由 `main.dart` 经
/// `ValueListenableBuilder` 消费（解析出最终明暗后传给应用壳与标题栏）：
/// 设置页切换主题时调用 `ThemeNotifier.instance.setMode(...)` 即可实时重建整棵树。
///
/// 存储沿用 PiliPlus 体系：`SettingBoxKey.themeMode` 存 int
/// （0=light, 1=dark, 2=system）。
///
/// **不再依赖 Material 的 `ThemeMode`**（MD3 库级退役 B1：改项目枚举，
/// 移除 material 依赖）。
///
/// **初始化时机**：构造时不访问 [Pref]（因此时 Hive 可能尚未初始化），
/// 初始值固定为 [ThemeModeType.system]；`ensureBootstrap()` 完成后由
/// `main.dart` 调用 [refresh] 从持久化存储读取实际值。
class ThemeNotifier extends ValueNotifier<ThemeModeType> {
  ThemeNotifier._() : super(ThemeModeType.system);

  static final ThemeNotifier instance = ThemeNotifier._();

  /// 从持久化存储读取实际主题模式并通知重建。
  /// 在 `ensureBootstrap()` 完成后调用。
  void refresh() {
    value = ThemeModeType.fromTypeIndex(Pref.themeType);
  }

  /// 当前存储的 int 值（0=light, 1=dark, 2=system）。
  int get typeIndex => value.typeIndex;

  /// 切换主题模式并持久化。
  Future<void> setMode(ThemeModeType mode) async {
    final previous = value;
    value = mode;
    await GStorage.setting.put(SettingBoxKey.themeMode, typeIndex);
    AppLogger.w('Coverage', 'themeMode ${previous.name} → ${mode.name}');
  }
}

/// 主题模式枚举（项目自有；用于设置项选择对话框与主题解析）。
enum ThemeModeType {
  light('浅色', 0),
  dark('深色', 1),
  system('跟随系统', 2),
  ;

  final String label;

  /// 持久化 int 值（0=light, 1=dark, 2=system）。
  final int typeIndex;

  const ThemeModeType(this.label, this.typeIndex);

  /// 由持久化 int 值解析（未知值回退 system）。
  static ThemeModeType fromTypeIndex(int index) => switch (index) {
        0 => ThemeModeType.light,
        1 => ThemeModeType.dark,
        _ => ThemeModeType.system,
      };

  /// 解析最终是否深色（[platformBrightness] 为系统亮度，用于 system 档）。
  bool resolveIsDark(Brightness platformBrightness) => switch (this) {
        ThemeModeType.light => false,
        ThemeModeType.dark => true,
        ThemeModeType.system => platformBrightness == Brightness.dark,
      };
}
