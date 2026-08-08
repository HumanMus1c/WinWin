import 'package:flutter/material.dart';

import 'ui_style.dart';

/// 字体排印 Token — 按 [UiStyle] 解析的字重 / 字间距体系。
///
/// 参照 BiliPai 的 `BiliDesign.typography`：
/// - **iOS**：SF Pro 风格，titleMedium 17sp / letterSpacing -0.41（紧凑感）。
/// - **Material 3**：标准 M3 Typography，letterSpacing 0.15（规范间距）。
/// - **Miuix**：Medium 字重，letterSpacing 0（扁平舒展）。
///
/// 作为 [ThemeExtension] 挂载，组件通过
/// `Theme.of(context).extension<AppTypography>()` 读取。
/// 仅提供与 M3 默认有差异的补充字段；基础字号仍由
/// `ThemeData.textTheme` 提供。
@immutable
class AppTypography extends ThemeExtension<AppTypography> {
  const AppTypography({
    required this.titleLetterSpacing,
    required this.labelLetterSpacing,
    required this.bodyLetterSpacing,
    required this.headlineWeight,
    required this.titleWeight,
    required this.bodyWeight,
    required this.style,
  });

  /// title 系列字间距（iOS 负值紧凑，MD3 正值规范，Miuix 0）。
  final double titleLetterSpacing;

  /// label 系列字间距。
  final double labelLetterSpacing;

  /// body 系列字间距。
  final double bodyLetterSpacing;

  /// headline 字重（iOS semibold=600，MD3 medium=500，Miuix medium=500）。
  final FontWeight headlineWeight;

  /// title 字重。
  final FontWeight titleWeight;

  /// body 字重。
  final FontWeight bodyWeight;

  /// 当前风格。
  final UiStyle style;

  // ── iOS（SF Pro 紧凑）──
  static const ios = AppTypography(
    titleLetterSpacing: -0.41,
    labelLetterSpacing: -0.08,
    bodyLetterSpacing: -0.24,
    headlineWeight: FontWeight.w600,
    titleWeight: FontWeight.w600,
    bodyWeight: FontWeight.w400,
    style: UiStyle.ios,
  );

  // ── Material 3（规范间距）──
  static const material3 = AppTypography(
    titleLetterSpacing: 0.15,
    labelLetterSpacing: 0.1,
    bodyLetterSpacing: 0.25,
    headlineWeight: FontWeight.w500,
    titleWeight: FontWeight.w500,
    bodyWeight: FontWeight.w400,
    style: UiStyle.material3,
  );

  // ── Miuix（扁平舒展）──
  static const miuix = AppTypography(
    titleLetterSpacing: 0.0,
    labelLetterSpacing: 0.0,
    bodyLetterSpacing: 0.0,
    headlineWeight: FontWeight.w500,
    titleWeight: FontWeight.w500,
    bodyWeight: FontWeight.w400,
    style: UiStyle.miuix,
  );

  /// 按 [UiStyle] 解析对应 Token。
  static AppTypography forStyle(UiStyle style) => switch (style) {
        UiStyle.ios => ios,
        UiStyle.material3 => material3,
        UiStyle.miuix => miuix,
      };

  /// 将 [base] 文本样式叠加当前风格的字重 / 字间距。
  TextStyle applyTo(TextStyle base) => base.copyWith(
        fontWeight: titleWeight,
        letterSpacing: titleLetterSpacing,
      );

  @override
  AppTypography copyWith({
    double? titleLetterSpacing,
    double? labelLetterSpacing,
    double? bodyLetterSpacing,
    FontWeight? headlineWeight,
    FontWeight? titleWeight,
    FontWeight? bodyWeight,
    UiStyle? style,
  }) =>
      AppTypography(
        titleLetterSpacing: titleLetterSpacing ?? this.titleLetterSpacing,
        labelLetterSpacing: labelLetterSpacing ?? this.labelLetterSpacing,
        bodyLetterSpacing: bodyLetterSpacing ?? this.bodyLetterSpacing,
        headlineWeight: headlineWeight ?? this.headlineWeight,
        titleWeight: titleWeight ?? this.titleWeight,
        bodyWeight: bodyWeight ?? this.bodyWeight,
        style: style ?? this.style,
      );

  @override
  AppTypography lerp(AppTypography? other, double t) {
    if (other is! AppTypography) return this;
    return AppTypography(
      titleLetterSpacing:
          _lerpDouble(titleLetterSpacing, other.titleLetterSpacing, t),
      labelLetterSpacing:
          _lerpDouble(labelLetterSpacing, other.labelLetterSpacing, t),
      bodyLetterSpacing:
          _lerpDouble(bodyLetterSpacing, other.bodyLetterSpacing, t),
      headlineWeight: FontWeight.lerp(headlineWeight, other.headlineWeight, t) ??
          headlineWeight,
      titleWeight:
          FontWeight.lerp(titleWeight, other.titleWeight, t) ?? titleWeight,
      bodyWeight: FontWeight.lerp(bodyWeight, other.bodyWeight, t) ?? bodyWeight,
      style: t < 0.5 ? style : other.style,
    );
  }
}

double _lerpDouble(double a, double b, double t) => a + (b - a) * t;
