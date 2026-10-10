import 'package:flutter/widgets.dart';


/// 形状 Token — 圆角体系（阶段5d-L4-2 单轨化）。
///
/// 参照 BiliPai 的 `BiliDesign.shapes`：iOS 连续曲率圆角，MD3 标准 M3
/// 圆角 ×0.9 缩放，Miuix 扁平大圆角 ×1.15 缩放。
///
/// 读取通道：`AppThemeHost.of(context).shapes`（MD3 库级退役 B2 起）；
/// **B7-a 起为纯 Token 类**（已剥离 `ThemeExtension` 基类与 ThemeData 注册）。
///
/// 同时提供 [Radius] 与 [BorderRadius] / [RoundedRectangleBorder] 三种形式，
/// 覆盖卡片、按钮、容器、胶囊、输入框等场景。
@immutable
class AppShapes {
  const AppShapes({
    required this.tiny,
    required this.small,
    required this.medium,
    required this.large,
    required this.extraLarge,
    required this.floating,
    required this.pill,
  });

  /// 最小圆角（角标 / tag）。
  final Radius tiny;

  /// 小圆角（小按钮 / badge）。
  final Radius small;

  /// 中圆角（卡片 / 列表项 / 输入框）。
  final Radius medium;

  /// 大圆角（大卡片 / sheet header）。
  final Radius large;

  /// 超大圆角（dialog / bottom sheet）。
  final Radius extraLarge;

  /// 浮动圆角（FAB / 浮动栏）。
  final Radius floating;

  /// 胶囊圆角（pill / 底部导航胶囊）。
  final Radius pill;

  /// 当前风格（供组件做风格特判时使用）。

  // ── Miuix（阶段5d-L2 起为唯一取值；×1.15 缩放，扁平大圆角，
  //   对齐 BiliPai MIUIX_CORNER_RADIUS_SCALE = 1.15f）──
  static const miuix = AppShapes(
    tiny: Radius.circular(6),
    small: Radius.circular(12),
    medium: Radius.circular(14),
    large: Radius.circular(16),
    extraLarge: Radius.circular(23),
    floating: Radius.circular(32),
    pill: Radius.circular(100),
  );

  /// 兼容旧代码：映射到 [miuix]（对齐 upstream 单向迁移规则）。
  @Deprecated('Use miuix instead. Upstream BiliPai maps iOS to MIUIX.')
  static const ios = miuix;

  // ── BorderRadius 便捷访问 ──
  BorderRadius get tinyBorder => BorderRadius.all(tiny);
  BorderRadius get smallBorder => BorderRadius.all(small);
  BorderRadius get mediumBorder => BorderRadius.all(medium);
  BorderRadius get largeBorder => BorderRadius.all(large);
  BorderRadius get extraLargeBorder => BorderRadius.all(extraLarge);
  BorderRadius get floatingBorder => BorderRadius.all(floating);
  BorderRadius get pillBorder => BorderRadius.all(pill);

  // ── ShapeBorder 便捷访问 ──
  RoundedRectangleBorder get cardShape =>
      RoundedRectangleBorder(borderRadius: mediumBorder);
  RoundedRectangleBorder get buttonShape =>
      RoundedRectangleBorder(borderRadius: smallBorder);
  RoundedRectangleBorder get containerShape =>
      RoundedRectangleBorder(borderRadius: largeBorder);
  RoundedRectangleBorder get dialogShape =>
      RoundedRectangleBorder(borderRadius: extraLargeBorder);
  RoundedRectangleBorder get floatingShape =>
      RoundedRectangleBorder(borderRadius: floatingBorder);
  StadiumBorder get pillShape => const StadiumBorder();
}
