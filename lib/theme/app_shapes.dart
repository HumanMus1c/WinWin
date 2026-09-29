import 'package:material_ui/material_ui.dart';

import 'ui_style.dart';

/// 形状 Token — 按 [UiStyle] 解析的圆角体系。
///
/// 参照 BiliPai 的 `BiliDesign.shapes`：iOS 连续曲率圆角，MD3 标准 M3
/// 圆角 ×0.9 缩放，Miuix 扁平大圆角 ×1.15 缩放。作为 [ThemeExtension]
/// 挂载到 [ThemeData]，组件通过 `Theme.of(context).extension<AppShapes>()`
/// 读取，无需手动传递 [UiStyle]。
///
/// 同时提供 [Radius] 与 [BorderRadius] / [RoundedRectangleBorder] 三种形式，
/// 覆盖卡片、按钮、容器、胶囊、输入框等场景。
@immutable
class AppShapes extends ThemeExtension<AppShapes> {
  const AppShapes({
    required this.tiny,
    required this.small,
    required this.medium,
    required this.large,
    required this.extraLarge,
    required this.floating,
    required this.pill,
    required this.style,
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
  final UiStyle style;

  // ── Material 3（×0.9 缩放，对齐 BiliPai MD3_CORNER_RADIUS_SCALE = 0.9f）──
  static const material3 = AppShapes(
    tiny: Radius.circular(4),
    small: Radius.circular(9),
    medium: Radius.circular(11),
    large: Radius.circular(13),
    extraLarge: Radius.circular(18),
    floating: Radius.circular(25),
    pill: Radius.circular(100),
    style: UiStyle.material3,
  );

  // ── Miuix（×1.15 缩放，扁平大圆角，对齐 BiliPai MIUIX_CORNER_RADIUS_SCALE = 1.15f）──
  static const miuix = AppShapes(
    tiny: Radius.circular(6),
    small: Radius.circular(12),
    medium: Radius.circular(14),
    large: Radius.circular(16),
    extraLarge: Radius.circular(23),
    floating: Radius.circular(32),
    pill: Radius.circular(100),
    style: UiStyle.miuix,
  );

  /// 兼容旧代码：映射到 [miuix]（对齐 upstream 单向迁移规则）。
  @Deprecated('Use miuix or material3 instead. Upstream BiliPai maps iOS to MIUIX.')
  static const ios = miuix;

  /// 按 [UiStyle] 解析对应 Token。
  static AppShapes forStyle(UiStyle style) => switch (style) {
        UiStyle.material3 => material3,
        UiStyle.miuix => miuix,
      };

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

  @override
  AppShapes copyWith({
    Radius? tiny,
    Radius? small,
    Radius? medium,
    Radius? large,
    Radius? extraLarge,
    Radius? floating,
    Radius? pill,
    UiStyle? style,
  }) =>
      AppShapes(
        tiny: tiny ?? this.tiny,
        small: small ?? this.small,
        medium: medium ?? this.medium,
        large: large ?? this.large,
        extraLarge: extraLarge ?? this.extraLarge,
        floating: floating ?? this.floating,
        pill: pill ?? this.pill,
        style: style ?? this.style,
      );

  @override
  AppShapes lerp(AppShapes? other, double t) {
    if (other is! AppShapes) return this;
    return AppShapes(
      tiny: Radius.lerp(tiny, other.tiny, t) ?? tiny,
      small: Radius.lerp(small, other.small, t) ?? small,
      medium: Radius.lerp(medium, other.medium, t) ?? medium,
      large: Radius.lerp(large, other.large, t) ?? large,
      extraLarge: Radius.lerp(extraLarge, other.extraLarge, t) ?? extraLarge,
      floating: Radius.lerp(floating, other.floating, t) ?? floating,
      pill: Radius.lerp(pill, other.pill, t) ?? pill,
      style: t < 0.5 ? style : other.style,
    );
  }
}
