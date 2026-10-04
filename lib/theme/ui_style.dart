/// 双风格 UI 枚举与渲染分发（对齐 BiliPai 主题精简架构 §5.2）。
///
/// 运行时收敛为二值模型：[material3] 与 [miuix]。
/// 历史 iOS 风格已单向迁移为 [miuix]，不再作为运行时可选主题。
library;

/// 应用级 UI 风格枚举。
///
/// - [material3]：Material Design 3 风格（M3 原生控件 + 标准 tonal elevation + 0.9× 圆角）
/// - [miuix]：Miuix 风格（扁平控件 + 0 elevation + 1.15× 圆角缩放 + 平滑曲率与下沉微动效）
enum UiStyle {
  material3('Material 3', 1),
  miuix('Miuix', 2),
  ;

  final String label;
  final int legacyInt;

  const UiStyle(this.label, this.legacyInt);

  /// 从持久化的 int 值反序列化（阶段5d-L4-1 单轨迁移）：
  /// 历史值 0（旧 iOS）/ 1（material3）/ 2（miuix）与空值**统一单向迁移为
  /// [miuix]**——风格切换入口已退役，运行时不再存在 material3 取值来源。
  static UiStyle fromLegacyInt(int? value) => miuix;
}

/// 组件级渲染分发枚举。
///
/// 每个自适应组件在入口处调用 [resolvePrimitiveRenderer] 获取此枚举，
/// 然后分发到对应风格的具体实现。保持分发逻辑集中、可测试、跨组件一致。
enum PrimitiveRenderer {
  /// Material 3 渲染路径：M3 原生控件 + 标准 tonal elevation。
  material3,

  /// Miuix 渲染路径：扁平控件 + 0 elevation + 1.15× 圆角 + 紧凑密度。
  miuix,
}

/// 组件渲染分发纯函数。
PrimitiveRenderer resolvePrimitiveRenderer(UiStyle style) =>
    switch (style) {
      UiStyle.material3 => PrimitiveRenderer.material3,
      UiStyle.miuix => PrimitiveRenderer.miuix,
    };

