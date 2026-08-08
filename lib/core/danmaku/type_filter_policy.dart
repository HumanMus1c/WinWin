// Ported from BiliPai (Kotlin) -> WinWin (Dart)
// Original: com/android/purebilibili/feature/video/danmaku/DanmakuTypeFilterPolicy.kt
//
// 弹幕类型 / 颜色过滤策略。
//
// 与 [DanmakuOptions] 的区别：
// - [DanmakuOptions] 面向渲染引擎（canvas_danmaku），将屏蔽类型转成
//   DanmakuOption.hideScroll/hideTop/hideBottom/hideSpecial。
// - 本策略面向数据层（入桶前 / 渲染前判断），提供细粒度的「单条弹幕是否
//   应显示」决策，支持标准弹幕与高级弹幕分支，并可被 keyword_filter 联动。
//
// 字段语义与 B 站 mode 对齐：
//   mode 1/2/3 = 滚动, 4 = 底部, 5 = 顶部, 7 = 高级（special）

/// 白色弹幕 RGB（0xFFFFFF），用于判断是否为彩色弹幕。
const int _kDanmakuWhiteRgb = 0x00FFFFFF;

/// 弹幕类型过滤设置（与 [DanmakuOptions] 的 blockTypesList 联动）。
class DanmakuTypeFilterSettings {
  /// 允许滚动弹幕（mode 1/2/3）。
  final bool allowScroll;
  /// 允许顶部弹幕（mode 5）。
  final bool allowTop;
  /// 允许底部弹幕（mode 4）。
  final bool allowBottom;
  /// 允许彩色弹幕（非白色）。
  final bool allowColorful;
  /// 允许高级弹幕（mode 7）。
  final bool allowSpecial;

  const DanmakuTypeFilterSettings({
    this.allowScroll = true,
    this.allowTop = true,
    this.allowBottom = true,
    this.allowColorful = true,
    this.allowSpecial = true,
  });

  /// 从屏蔽类型集合构造（value 与 [DanmakuElem.mode] 语义对齐）。
  ///
  /// blockTypes 约定（与 [DanmakuOptions] 一致）：
  /// | value | 含义 | 对应字段 |
  /// |---|---|---|
  /// | 2 | 滚动 | allowScroll=false |
  /// | 5 | 顶部 | allowTop=false |
  /// | 4 | 底部 | allowBottom=false |
  /// | 7 | 高级 | allowSpecial=false |
  /// | 6 | 彩色 | allowColorful=false |
  factory DanmakuTypeFilterSettings.fromBlockTypes(Set<int> blockTypes) {
    return DanmakuTypeFilterSettings(
      allowScroll: !blockTypes.contains(2),
      allowTop: !blockTypes.contains(5),
      allowBottom: !blockTypes.contains(4),
      allowSpecial: !blockTypes.contains(7),
      allowColorful: !blockTypes.contains(6),
    );
  }

  /// 全部允许（无过滤）。
  static const DanmakuTypeFilterSettings allowAll = DanmakuTypeFilterSettings();

  @override
  String toString() =>
      'DanmakuTypeFilterSettings(scroll=$allowScroll, top=$allowTop, '
      'bottom=$allowBottom, colorful=$allowColorful, special=$allowSpecial)';
}

/// 弹幕类型过滤策略（纯函数，无状态）。
abstract final class DanmakuTypeFilterPolicy {
  /// 判断标准弹幕（mode 1-5）是否应显示。
  ///
  /// - [danmakuMode]：弹幕 mode（1/2/3=滚动, 4=底部, 5=顶部）。
  /// - [color]：弹幕颜色（十进制 RGB）。
  /// - [settings]：过滤设置。
  /// - [isVipGradualColor]：是否为大会员渐变彩弹幕（colorful==60001）。
  static bool shouldDisplayStandard({
    required int danmakuMode,
    required int color,
    required DanmakuTypeFilterSettings settings,
    bool isVipGradualColor = false,
  }) {
    final typeAllowed = switch (danmakuMode) {
      4 => settings.allowBottom,
      5 => settings.allowTop,
      _ => settings.allowScroll,
    };
    if (!typeAllowed) return false;
    if (!settings.allowColorful &&
        isColorfulDanmaku(color, isVipGradualColor)) {
      return false;
    }
    return true;
  }

  /// 判断高级弹幕（mode 7）是否应显示。
  static bool shouldDisplayAdvanced({
    required int color,
    required DanmakuTypeFilterSettings settings,
  }) {
    if (!settings.allowSpecial) return false;
    if (!settings.allowColorful && isColorfulDanmaku(color)) return false;
    return true;
  }

  /// 判断是否为彩色弹幕（非白色，或大会员渐变彩）。
  static bool isColorfulDanmaku(int color, [bool isVipGradualColor = false]) {
    if (isVipGradualColor) return true;
    final rgb = color & _kDanmakuWhiteRgb;
    return rgb != _kDanmakuWhiteRgb;
  }
}
