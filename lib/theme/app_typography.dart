import 'package:flutter/widgets.dart';


/// 字体排印 Token — 字重 / 字间距体系（阶段5d-L4-2 单轨化）。
///
/// 参照 BiliPai 的 `BiliDesign.typography`：
/// - **iOS**：Segoe UI 适配版，轻微紧凑字间距（-0.1），semibold 字重。
/// - **Material 3**：标准 M3 Typography，letterSpacing 0.15（规范间距）。
/// - **Miuix**：Medium 字重，letterSpacing 0（扁平舒展）。
///
/// 读取通道：`AppThemeHost.of(context).typography`（MD3 库级退役 B2 起）；
/// **B7-a 起为纯 Token 类**（已剥离 `ThemeExtension` 基类与 ThemeData 注册）。
/// 仅提供与 M3 默认有差异的补充字段；基础字号仍由
/// `ThemeData.textTheme` 提供。
@immutable
class AppTypography {
  const AppTypography({
    required this.titleLetterSpacing,
    required this.labelLetterSpacing,
    required this.bodyLetterSpacing,
    required this.headlineWeight,
    required this.titleWeight,
    required this.bodyWeight,
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

  // ── Miuix（阶段5d-L2 起为唯一取值；扁平舒展，对齐 BiliMiuixTypography 视觉调性）──
  static const miuix = AppTypography(
    titleLetterSpacing: 0.0,
    labelLetterSpacing: 0.0,
    bodyLetterSpacing: 0.0,
    headlineWeight: FontWeight.w500,
    titleWeight: FontWeight.w500,
    bodyWeight: FontWeight.w400,
  );

  /// 兼容旧代码：映射到 [miuix]（对齐 upstream 单向迁移规则）。
  @Deprecated('Use miuix instead. Upstream BiliPai maps iOS to MIUIX.')
  static const ios = miuix;

  /// 将 [base] 文本样式叠加当前风格的字重 / 字间距。
  TextStyle applyTo(TextStyle base) => base.copyWith(
        fontWeight: titleWeight,
        letterSpacing: titleLetterSpacing,
      );
}
