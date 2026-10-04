import 'package:flutter/foundation.dart';

import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/core/storage/storage_key.dart';
import 'package:winwin/theme/ui_style.dart';

/// UI 风格全局通知器（单例 [ValueNotifier]）。
///
/// **阶段5d-L4-1（风格入口退役）**：设置页「界面风格」切换入口已移除，
/// 运行时风格恒定 [UiStyle.miuix]；本通知器保留为**纯广播通道**（窗口标题栏
/// 深色调监听、`main.dart` 主题重建依赖它），[refresh] 恒解析为 miuix。
///
/// **存储**：沿用 Hive `setting` box，key = [SettingBoxKey.uiStyle]；
/// 历史值（0=ios / 1=material3 / 2=miuix）统一单向迁移为 miuix
/// （见 [UiStyle.fromLegacyInt]）。
class UiStyleNotifier extends ValueNotifier<UiStyle> {
  UiStyleNotifier._() : super(UiStyle.miuix);

  static final UiStyleNotifier instance = UiStyleNotifier._();

  /// 从持久化存储读取 UI 风格并通知重建。
  /// 在 `ensureBootstrap()` 完成后调用。
  void refresh() {
    final raw = GStorage.setting.get(
      SettingBoxKey.uiStyle,
      defaultValue: UiStyle.miuix.legacyInt,
    ) as int;
    value = UiStyle.fromLegacyInt(raw);
  }
}
