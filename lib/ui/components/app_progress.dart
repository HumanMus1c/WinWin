import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

/// 加载环（Miuix 替身：`CircularProgressIndicator` → `MiuixCircularProgressIndicator`）。
///
/// 对齐 Material 常用参数面（B7-b 批量替换通道）：
/// - [value]：0~1 进度；null = 无限旋转（默认）；
/// - [strokeWidth]：环宽（默认取 Miuix 4）；
/// - [size]：直径（默认取 Miuix 30；置于更小约束内时随约束收缩）；
/// - [color]：前景色（默认取 Miuix 语义 `primary`）；轨道保持 Miuix
///   `secondaryContainer`（观感变化点，实机对照清单）。
class AppProgressIndicator extends StatelessWidget {
  const AppProgressIndicator({
    super.key,
    this.value,
    this.strokeWidth,
    this.size,
    this.color,
  });

  final double? value;
  final double? strokeWidth;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final base = MiuixProgressIndicatorDefaults.defaultColors(context);
    final foreground = color ?? base.foregroundColor;
    return MiuixCircularProgressIndicator(
      progress: value,
      strokeWidth: strokeWidth ??
          MiuixProgressIndicatorDefaults.defaultCircularStrokeWidth,
      size: size ?? MiuixProgressIndicatorDefaults.defaultCircularSize,
      colors: MiuixProgressIndicatorColors(
        foregroundColor: foreground,
        disabledForegroundColor: foreground,
        backgroundColor: base.backgroundColor,
      ),
    );
  }
}

/// 线性进度条（Miuix 替身：`LinearProgressIndicator` → `MiuixLinearProgressIndicator`）。
///
/// 对齐 Material 常用参数面：`value`/`minHeight`/`backgroundColor`/`valueColor`。
/// `valueColor: AlwaysStoppedAnimation(c)` 由调用点收敛为 [color]（B7-b 逐点改）。
class AppLinearProgressIndicator extends StatelessWidget {
  const AppLinearProgressIndicator({
    super.key,
    this.value,
    this.minHeight,
    this.color,
    this.backgroundColor,
  });

  final double? value;
  final double? minHeight;
  final Color? color;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final base = MiuixProgressIndicatorDefaults.defaultColors(context);
    final foreground = color ?? base.foregroundColor;
    return MiuixLinearProgressIndicator(
      progress: value,
      height: minHeight ?? MiuixProgressIndicatorDefaults.defaultLinearHeight,
      colors: MiuixProgressIndicatorColors(
        foregroundColor: foreground,
        disabledForegroundColor: foreground,
        backgroundColor: backgroundColor ?? base.backgroundColor,
      ),
    );
  }
}
