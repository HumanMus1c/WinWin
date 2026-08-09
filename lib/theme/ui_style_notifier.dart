import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

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
/// 初始值固定为 [UiStyle.ios]（默认风格）；`ensureBootstrap()` 完成后由
/// `main.dart` 调用 [refresh] 从持久化存储读取实际值。
class UiStyleNotifier extends ValueNotifier<UiStyle> {
  UiStyleNotifier._() : super(UiStyle.ios);

  static final UiStyleNotifier instance = UiStyleNotifier._();

  /// 从持久化存储读取实际 UI 风格并通知重建。
  /// 在 `ensureBootstrap()` 完成后调用。
  void refresh() {
    final raw = GStorage.setting.get(
      SettingBoxKey.uiStyle,
      defaultValue: UiStyle.ios.legacyInt,
    ) as int;
    value = UiStyle.fromLegacyInt(raw);
  }

  /// 切换 UI 风格并持久化。
  ///
  /// 使用 [addPostFrameCallback] 将 value 赋值推迟到当前帧渲染完成后，
  /// 确保完全脱离触发的 widget（如 SegmentedButton/CupertinoSegmentedControl）
  /// 的 onSelectionChanged/onValueChanged 回调同步栈，避免在 semantics/layout
  /// 处理中途触发整树重建导致 parentDataDirty 断言失败、渲染帧中断。
  Future<void> setStyle(UiStyle style) async {
    await GStorage.setting.put(SettingBoxKey.uiStyle, style.legacyInt);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      value = style;
    });
  }
}
