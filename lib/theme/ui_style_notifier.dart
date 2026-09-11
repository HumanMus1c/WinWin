import 'package:flutter/foundation.dart';

import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/core/storage/storage_key.dart';
import 'package:winwin/theme/ui_style.dart';

/// UI 风格全局通知器（单例 [ValueNotifier]）。
///
/// 参照 BiliPai 的 `SettingsManager.setUiStyle` + `LocalUiPreset` 广播。
/// 在 `main.dart` 的 `MaterialApp` 外层通过 `ValueListenableBuilder<UiStyle>`
/// 消费，设置页切换风格时调用 `UiStyleNotifier.instance.value = newStyle`
/// 即可实时重建整棵树。
///
/// **存储**：沿用 Hive `setting` box，key = [SettingBoxKey.uiStyle]，
/// 存 int（0=ios, 1=material3, 2=miuix）。
///
/// **初始化时机**：构造时不访问 [GStorage]（此时 Hive 可能尚未初始化），
/// 初始值固定为 [UiStyle.material3]（默认风格）；`ensureBootstrap()` 完成后由
/// `main.dart` 调用 [refresh] 从持久化存储读取实际值。
class UiStyleNotifier extends ValueNotifier<UiStyle> {
  UiStyleNotifier._() : super(UiStyle.material3);

  static final UiStyleNotifier instance = UiStyleNotifier._();

  /// 从持久化存储读取实际 UI 风格并通知重建。
  /// 在 `ensureBootstrap()` 完成后调用。
  void refresh() {
    final raw = GStorage.setting.get(
      SettingBoxKey.uiStyle,
      defaultValue: UiStyle.material3.legacyInt,
    ) as int;
    value = UiStyle.fromLegacyInt(raw);
  }

  /// 切换 UI 风格并持久化。
  ///
  /// 先持久化再设置 [value]：使 value 赋值在微任务中执行，
  /// 脱离调用方可能的同步回调栈，避免在 semantics/layout 处理中途
  /// 触发整树重建导致 parentDataDirty 断言失败。
  Future<void> setStyle(UiStyle style) async {
    await GStorage.setting.put(SettingBoxKey.uiStyle, style.legacyInt);
    value = style;
  }
}
