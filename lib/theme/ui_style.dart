/// 三风格 UI 枚举与渲染分发。
///
/// 参照 BiliPai 的 `UiPreset × AndroidNativeVariant` 二维枚举，简化为
/// 单一 [UiStyle] 枚举（IOS / MATERIAL3 / MIUIX）。每个自适应组件通过
/// [resolvePrimitiveRenderer] 获取 [PrimitiveRenderer]，在三条渲染路径间
/// `when` 分发，使分发逻辑在纯 Dart 中可测试且跨组件一致。
///
/// 设计原则（BiliPai 注释原文）：
/// "Use this enum at the entry point of every preset-aware primitive so the
/// dispatch is testable in plain Kotlin and consistent across primitives."
library;

/// 应用级 UI 风格枚举。
///
/// - [ios]：iOS 风格（Cupertino 控件 + 连续曲率圆角 + 扩散阴影）
/// - [material3]：Material Design 3 风格（M3 控件 + 标准 tonal elevation）
/// - [miuix]：Miuix 风格（扁平 + 0 elevation + 1.15× 圆角缩放）
enum UiStyle {
  ios('iOS', 0),
  material3('Material 3', 1),
  miuix('Miuix', 2),
  ;

  final String label;
  final int legacyInt;

  const UiStyle(this.label, this.legacyInt);

  /// 从持久化的 int 值反序列化。未知值回退到 [ios]（默认风格）。
  static UiStyle fromLegacyInt(int? value) => switch (value) {
        0 => ios,
        1 => material3,
        2 => miuix,
        _ => ios,
      };
}

/// 组件级渲染分发枚举。
///
/// 每个自适应组件在入口处调用 [resolvePrimitiveRenderer] 获取此枚举，
/// 然后 `when` 分发到对应风格的具体实现。保持分发逻辑集中、可测试、
/// 跨组件一致。
enum PrimitiveRenderer {
  /// iOS 渲染路径：Cupertino 控件 + 连续曲率 + 扩散阴影。
  ios,

  /// Material 3 渲染路径：M3 原生控件 + 标准 tonal elevation。
  material3,

  /// Miuix 渲染路径：扁平控件 + 0 elevation + 1.15× 圆角。
  miuix,
}

/// 组件渲染分发纯函数。
///
/// 在每个自适应组件入口处调用：
/// ```dart
/// final renderer = resolvePrimitiveRenderer(UiStyle.of(context));
/// switch (renderer) {
///   case PrimitiveRenderer.ios => IosImplementation(...),
///   case PrimitiveRenderer.material3 => Md3Implementation(...),
///   case PrimitiveRenderer.miuix => MiuixImplementation(...),
/// }
/// ```
///
/// 当前 [UiStyle] 与 [PrimitiveRenderer] 一一对应；保留独立枚举以便
/// 未来引入更细粒度的"桥接"渲染路径（如 BiliPai 的 MIUIX_BRIDGED）。
PrimitiveRenderer resolvePrimitiveRenderer(UiStyle style) =>
    switch (style) {
      UiStyle.ios => PrimitiveRenderer.ios,
      UiStyle.material3 => PrimitiveRenderer.material3,
      UiStyle.miuix => PrimitiveRenderer.miuix,
    };
