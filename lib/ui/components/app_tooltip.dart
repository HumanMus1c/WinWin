import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

/// 桌面悬停提示（Miuix 替身：`Tooltip(message:, child:)` → `MiuixTooltipBox` +
/// `MiuixPlainTooltip`）。
///
/// 交互：悬停/长按即时显示（Miuix 口径）；对比 Material 版差异——无
/// `waitDuration` 延迟（原 4 处调用点已随批量替换收敛）。
class AppTooltip extends StatelessWidget {
  const AppTooltip({
    super.key,
    required this.message,
    required this.child,
  });

  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MiuixTooltipBox(
      tooltip: (context, scope) =>
          MiuixPlainTooltip(scope: scope, child: Text(message)),
      child: child,
    );
  }
}
