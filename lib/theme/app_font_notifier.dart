import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/core/storage/storage_key.dart';

/// 应用字体全局通知器（单例 [ValueNotifier]）。
///
/// 移植自 BiliPai 的 `AppFontFileStore` + `withFontFamily` 机制。
///
/// **value** 为当前字体族名：
/// - 空字符串 `''` = 系统默认（Windows 上由 Flutter 决定，通常 Segoe UI）
/// - `'Segoe UI'` = Windows 系统默认 UI 字体（显式指定）
/// - `'Microsoft YaHei UI'` / `'SimSun'` 等 = Windows 预装字体
/// - [customFontFamily] = 通过 [FontLoader] 动态注册的自定义字体
///
/// **持久化**：fontFamily + 自定义字体文件名存入 Hive `setting` box。
///
/// **自定义字体导入流程**（参照 BiliPai `importAppFontFromUri`）：
/// 1. 用户通过 `file_picker` 选择 `.ttf` / `.otf` 文件
/// 2. 复制到 `{applicationSupportDirectory}/app_fonts/custom_font.{ext}`
/// 3. 通过 [FontLoader] 注册为 [customFontFamily]
/// 4. 更新 value 触发 MaterialApp 重建
class AppFontNotifier extends ValueNotifier<String> {
  AppFontNotifier._() : super(windowsDefault);

  static final AppFontNotifier instance = AppFontNotifier._();

  /// 自定义字体在 FontLoader 中注册的族名。
  static const String customFontFamily = 'winwin_custom_font';

  /// Windows 系统默认 UI 字体。
  static const String windowsDefault = 'Segoe UI';

  /// 系统默认占位值（空串 = 让 Flutter 自行决定）。
  static const String systemDefault = '';

  /// 允许导入的字体文件扩展名。
  static const Set<String> allowedExtensions = {'.ttf', '.otf'};

  /// 自定义字体文件是否已加载到 FontLoader。
  bool _customFontLoaded = false;

  /// 当前是否使用自定义字体。
  bool get isCustomFont => value == customFontFamily;

  /// 从持久化存储读取字体设置并加载自定义字体（如有）。
  /// 在 `ensureBootstrap()` 完成后调用。
  Future<void> refresh() async {
    final family = GStorage.setting.get(
      SettingBoxKey.appFontFamily,
      defaultValue: windowsDefault,
    ) as String;
    if (family == customFontFamily) {
      final fileName = GStorage.setting.get(
        SettingBoxKey.appFontFileName,
        defaultValue: '',
      ) as String;
      if (fileName.isNotEmpty) {
        final loaded = await _loadCustomFont(fileName);
        if (loaded) {
          value = customFontFamily;
          return;
        }
        // 自定义字体加载失败，回退到系统默认。
        await clearCustomFont();
        value = windowsDefault;
        return;
      }
      value = windowsDefault;
      return;
    }
    value = family.isEmpty ? windowsDefault : family;
  }

  /// 切换到预设字体族并持久化。
  Future<void> setFontFamily(String family) async {
    await GStorage.setting.put(SettingBoxKey.appFontFamily, family);
    value = family;
  }

  /// 导入自定义字体文件。
  ///
  /// 参照 BiliPai `importAppFontFromUri`：
  /// - 复制文件到 `{appSupportDir}/app_fonts/custom_font.{ext}`
  /// - 通过 FontLoader 注册为 [customFontFamily]
  /// - 持久化族名 + 文件名
  ///
  /// 返回 null 表示成功，非 null 为错误信息。
  Future<String?> importCustomFont(String sourcePath) async {
    final ext = p.extension(sourcePath).toLowerCase();
    if (!allowedExtensions.contains(ext)) {
      return '仅支持 .ttf / .otf 字体文件';
    }

    try {
      final appDir = await getApplicationSupportDirectory();
      final fontDir = Directory(p.join(appDir.path, 'app_fonts'));
      if (!await fontDir.exists()) {
        await fontDir.create(recursive: true);
      }
      final targetPath = p.join(fontDir.path, 'custom_font$ext');
      await File(sourcePath).copy(targetPath);

      // 预校验：尝试加载一次，避免保存损坏文件后影响启动。
      final loaded = await _loadCustomFont('custom_font$ext');
      if (!loaded) {
        return '字体文件无效或已损坏';
      }

      await GStorage.setting.put(SettingBoxKey.appFontFamily, customFontFamily);
      await GStorage.setting
          .put(SettingBoxKey.appFontFileName, 'custom_font$ext');
      value = customFontFamily;
      return null;
    } catch (e) {
      return '字体导入失败：$e';
    }
  }

  /// 恢复系统默认字体，并删除已导入的自定义字体文件。
  Future<void> clearCustomFont() async {
    final fileName = GStorage.setting.get(
      SettingBoxKey.appFontFileName,
      defaultValue: '',
    ) as String;
    if (fileName.isNotEmpty) {
      try {
        final appDir = await getApplicationSupportDirectory();
        final fontPath = p.join(appDir.path, 'app_fonts', fileName);
        final file = File(fontPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // 删除失败不阻塞流程。
      }
    }
    await GStorage.setting.delete(SettingBoxKey.appFontFileName);
    await GStorage.setting.put(SettingBoxKey.appFontFamily, windowsDefault);
    value = windowsDefault;
  }

  /// 通过 FontLoader 加载自定义字体文件。
  Future<bool> _loadCustomFont(String fileName) async {
    if (_customFontLoaded) return true;
    try {
      final appDir = await getApplicationSupportDirectory();
      final fontPath = p.join(appDir.path, 'app_fonts', fileName);
      final file = File(fontPath);
      if (!await file.exists()) return false;

      final bytes = await file.readAsBytes();
      final loader = FontLoader(customFontFamily);
      loader.addFont(
        Future.value(ByteData.sublistView(bytes)),
      );
      await loader.load();
      _customFontLoaded = true;
      return true;
    } catch (e) {
      debugPrint('AppFontNotifier: 自定义字体加载失败 — $e');
      return false;
    }
  }

  /// 获取当前字体的显示名称（用于设置页 subtitle）。
  String get displayName {
    if (isCustomFont) return '自定义字体';
    if (value == windowsDefault) return 'Segoe UI（Windows 默认）';
    return value.isEmpty ? '系统默认' : value;
  }
}
