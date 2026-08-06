import 'package:flutter/material.dart';

import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/core/storage/storage_key.dart';
import 'package:winwin/core/storage/storage_pref.dart';

/// 主题模式全局通知器。
///
/// 单例 [ValueNotifier<ThemeMode>]，在 `main.dart` 的 `MaterialApp` 中
/// 通过 `ValueListenableBuilder` 消费，设置页切换主题时调用
/// `ThemeNotifier.instance.value = newMode` 即可实时重建整棵树。
///
/// 存储沿用 PiliPlus 体系：`SettingBoxKey.themeMode` 存 int
/// （0=light, 1=dark, 2=system）。
class ThemeNotifier extends ValueNotifier<ThemeMode> {
  ThemeNotifier._() : super(Pref.themeMode);

  static final ThemeNotifier instance = ThemeNotifier._();

  /// 当前存储的 int 值（0=light, 1=dark, 2=system）。
  int get typeIndex => switch (value) {
        ThemeMode.light => 0,
        ThemeMode.dark => 1,
        _ => 2,
      };

  /// 切换主题模式并持久化。
  Future<void> setMode(ThemeMode mode) async {
    value = mode;
    await GStorage.setting.put(SettingBoxKey.themeMode, typeIndex);
  }
}

/// 主题模式枚举（用于设置项选择对话框）。
enum ThemeModeType {
  light('浅色'),
  dark('深色'),
  system('跟随系统'),
  ;

  final String label;
  const ThemeModeType(this.label);

  ThemeMode toThemeMode() => switch (this) {
        ThemeModeType.light => ThemeMode.light,
        ThemeModeType.dark => ThemeMode.dark,
        ThemeModeType.system => ThemeMode.system,
      };

  static ThemeModeType fromMode(ThemeMode mode) => switch (mode) {
        ThemeMode.light => ThemeModeType.light,
        ThemeMode.dark => ThemeModeType.dark,
        ThemeMode.system => ThemeModeType.system,
      };
}
