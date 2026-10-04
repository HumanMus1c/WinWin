import 'package:material_ui/material_ui.dart';


/// Chrome Token — 容器外观（圆角 / 阴影 / 边框策略；阶段5d-L4-2 单轨化）。
///
/// 参照 BiliPai 的 `BiliDesign.chrome`：描述「外壳」级视觉特征——
/// 容器圆角、胶囊指示器圆角、阴影 elevation、是否启用 tonal elevation、
/// 是否显示分割线。与 [AppShapes]（组件级圆角）互补：[AppShapes] 描述
/// 单个控件的形状，[AppChrome] 描述承载多个控件的「外壳」。
///
/// 作为 [ThemeExtension] 挂载，组件通过
/// `Theme.of(context).extension<AppChrome>()` 读取。
@immutable
class AppChrome extends ThemeExtension<AppChrome> {
  const AppChrome({
    required this.containerRadius,
    required this.pillRadius,
    required this.elevation,
    required this.tonalElevation,
    required this.showDividers,
    required this.scrolledUnderElevation,
  });

  /// 外壳容器圆角（底部导航 / 顶栏背景 / sheet 头部）。
  final double containerRadius;

  /// 胶囊指示器圆角（底部导航选中态 pill / 分段控件指示器）。
  final double pillRadius;

  /// 标准 elevation（卡片 / 浮动元素）。
  final double elevation;

  /// tonal elevation（Miuix=0 表示纯扁平，MD3 用 tonal 表达层级）。
  final double tonalElevation;

  /// 是否显示分割线（iOS 偏好细分割线，Miuix 偏好无边框）。
  final bool showDividers;

  /// 滚动时的 under elevation（顶栏滚动着色深度）。
  final double scrolledUnderElevation;

  /// 当前风格。

  // ── Miuix（阶段5d-L2 起为唯一取值；扁平 0 elevation + 无分割线，
  //   对齐 BiliPai tonalSurfaceElevationDp = 0）──
  static const miuix = AppChrome(
    containerRadius: 20,
    pillRadius: 22,
    elevation: 0,
    tonalElevation: 0,
    showDividers: false,
    scrolledUnderElevation: 0,
  );

  /// 兼容旧代码：映射到 [miuix]（对齐 upstream 单向迁移规则）。
  @Deprecated('Use miuix instead. Upstream BiliPai maps iOS to MIUIX.')
  static const ios = miuix;

  /// 容器圆角的 BorderRadius 便捷访问。
  BorderRadius get containerBorder => BorderRadius.circular(containerRadius);

  /// 胶囊圆角的 BorderRadius 便捷访问。
  BorderRadius get pillBorder => BorderRadius.circular(pillRadius);

  @override
  AppChrome copyWith({
    double? containerRadius,
    double? pillRadius,
    double? elevation,
    double? tonalElevation,
    bool? showDividers,
    double? scrolledUnderElevation,
  }) =>
      AppChrome(
        containerRadius: containerRadius ?? this.containerRadius,
        pillRadius: pillRadius ?? this.pillRadius,
        elevation: elevation ?? this.elevation,
        tonalElevation: tonalElevation ?? this.tonalElevation,
        showDividers: showDividers ?? this.showDividers,
        scrolledUnderElevation:
            scrolledUnderElevation ?? this.scrolledUnderElevation,
      );

  @override
  AppChrome lerp(AppChrome? other, double t) {
    if (other is! AppChrome) return this;
    return AppChrome(
      containerRadius:
          _lerpDouble(containerRadius, other.containerRadius, t),
      pillRadius: _lerpDouble(pillRadius, other.pillRadius, t),
      elevation: _lerpDouble(elevation, other.elevation, t),
      tonalElevation: _lerpDouble(tonalElevation, other.tonalElevation, t),
      showDividers: t < 0.5 ? showDividers : other.showDividers,
      scrolledUnderElevation:
          _lerpDouble(scrolledUnderElevation, other.scrolledUnderElevation, t),
    );
  }
}

double _lerpDouble(double a, double b, double t) => a + (b - a) * t;
