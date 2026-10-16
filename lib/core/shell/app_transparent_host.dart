import 'package:flutter/widgets.dart';

import 'app_theme_host.dart';

/// `Material(type: MaterialType.transparency)` 的零 material 等价替身。B7-c7 第二批。
///
/// 复刻依据：`material_ui` 1.5.0 `lib/src/material.dart` `_MaterialState.build`（L445-560）。
/// 对子树，透明 `Material` 只做三件事，逐项等价如下：
///
/// 1. `AnimatedDefaultTextStyle(style: widget.textStyle ?? Theme.of(context).textTheme.bodyMedium!)`
///    → **改写子树默认文本样式**。本替身以 [AppTextStyles.bodyMedium] 复刻（B2-t1 零漂移派生：
///      仅 `color` + `decoration`，字号由调用点 / 外层 `DefaultTextStyle` 提供）。
///      原实现为动画版，本替身用固定 `DefaultTextStyle`——主题切换时的样式插值是过渡期产物，
///      退役后不再保留（稳态视觉一致）。
/// 2. ink 层（`NotificationListener<LayoutChangedNotification>` + `_InkFeatures`）
///    → 项目内已无消费者（`InkWell` / `ListTile` / `InkResponse` 等自 B6 起全部 Miuix 化），
///      不再迁移（去掉了无意义的 ink 层开销）。
/// 3. `ClipPath(ShapeBorderClipper(RoundedRectangleBorder()), clipBehavior)`
///    → transparency 的 shape 为**矩形且不描边**（`_ShapeBorderPaint` 不绘制任何内容），
///      默认 `Clip.none` 即零视觉；原调用点若显式传 `Clip.hardEdge`，
///      本替身以 [hardClip] 开关补 `ClipRect`（其默认 `clipBehavior` 即 `Clip.hardEdge`），
///      与 Material 的矩形硬裁剪口径一致。
///
/// 因而本替身 = `DefaultTextStyle(bodyMedium)`（+ 可选 `ClipRect`）：视觉与
/// "Material 祖先 + 默认文本样式" 语义等价，但不再拖入 material_ui，也无 ink 层。
/// 层级与 Material 一致：`DefaultTextStyle` 在外、裁剪在内。
class AppTransparentHost extends StatelessWidget {
  const AppTransparentHost({
    super.key,
    this.hardClip = false,
    required this.child,
  });

  /// true 时按视口矩形硬裁剪（等价 Material `clipBehavior: Clip.hardEdge`）。
  ///
  /// 仅 2026-10-09 收口-3 遗留的 `image_gallery_viewer` 一处为 true
  /// （当时为约束 ListTile 水波范围；水波已退役，保留裁剪以维持零视觉变化）。
  final bool hardClip;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    return DefaultTextStyle(
      style: tokens.text.bodyMedium ?? const TextStyle(),
      child: hardClip ? const ClipRect() : child,
    );
  }
}