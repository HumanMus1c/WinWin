import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/core/storage/storage_key.dart';

/// 演示模式下展示的程序名（替换用户昵称与发言昵称）。
const String kDemoDisplayName = 'WinWin';

/// 演示模式自定义覆盖值（仅演示期生效，用于 README 截图微调）。
///
/// 存储于 localCache box 的 [LocalCacheKey.demoOverrides]（JSON Map），修改即落盘；
/// 关闭演示模式后覆盖值不生效也不删除，再次开启演示模式时直接按保存值渲染。
///
/// 覆盖键示例：`profile.coins`、`profile.exp`、`profile.level`、`profile.vipType`、
/// `space.uid` 等（见各展示点的 DemoEditable* 注册处）。
abstract final class DemoOverrides {
  /// 覆盖值变更计数：供需要跨元素联动的界面监听重建
  /// （如经验条随经验值编辑联动、昵称颜色随 VIP 类型联动）。
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Map<String, dynamic> _read() {
    final raw = GStorage.localCache.get(LocalCacheKey.demoOverrides);
    if (raw is! String || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
    return <String, dynamic>{};
  }

  /// 读取数字类覆盖值（无覆盖返回 null）。
  static num? number(String key) => _read()[key] as num?;

  /// 读取枚举/类型类覆盖值（无覆盖返回 null）。
  static int? choice(String key) => (_read()[key] as num?)?.toInt();

  /// 读取文本类覆盖值（无覆盖返回 null）。
  static String? text(String key) {
    final value = _read()[key];
    return value is String ? value : null;
  }

  /// 写入覆盖值；[value] 为 null 时清除该 key。
  static Future<void> set(String key, Object? value) async {
    final map = _read();
    if (value == null) {
      map.remove(key);
    } else {
      map[key] = value;
    }
    if (map.isEmpty) {
      await GStorage.localCache.delete(LocalCacheKey.demoOverrides);
    } else {
      await GStorage.localCache.put(LocalCacheKey.demoOverrides, jsonEncode(map));
    }
    revision.value++;
  }

  /// 清除单个覆盖值（该项恢复真实数据展示）。
  static Future<void> clear(String key) => set(key, null);

  /// 清空全部演示自定义。
  static Future<void> clearAll() async {
    await GStorage.localCache.delete(LocalCacheKey.demoOverrides);
    revision.value++;
  }
}
