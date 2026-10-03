import 'package:flutter_miuix/miuix.dart';
import 'package:material_ui/material_ui.dart';

import 'package:winwin/theme/inherited_ui_style.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/theme/ui_style.dart';

/// 三处对话框共用外壳（SelectDialog / 弹幕设置 / 字幕设置）。
///
/// - MD3：`surfaceContainerHigh` + 24 圆角（对齐原各文件内联实现）；
/// - Miuix：[MiuixSurface] squircle 16 圆角 + surface α0.96 + outlineVariant
///   0.5px 描边 + 柔和阴影（阶段3a 起替换原 `Dialog` 直角近似外壳）。
///
/// 语义保持：仍是 `Dialog` 路由（遮罩、`barrierDismissible` 与全局
/// AppEscapeScope 的 Esc 弹层路由检测均不变）。
class MiuixDialogShell extends StatelessWidget {
  const MiuixDialogShell({
    super.key,
    required this.constraints,
    required this.child,
  });

  /// 卡片尺寸约束（各调用点自带，如 SelectDialog 的 minWidth 320）。
  final BoxConstraints constraints;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isMiuix = InheritedUiStyle.of(context) == UiStyle.miuix;

    final content = ConstrainedBox(constraints: constraints, child: child);

    return Dialog(
      backgroundColor: isMiuix ? Colors.transparent : cs.surfaceContainerHigh,
      elevation: isMiuix ? 0 : null,
      shape: isMiuix
          ? const RoundedRectangleBorder()
          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(
        horizontal: Style.lg,
        vertical: Style.xl,
      ),
      child: isMiuix
          ? MiuixSurface(
              cornerRadius: 16,
              color: cs.surface.withValues(alpha: 0.96),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.25),
                width: 0.5,
              ),
              shadowElevation: 8,
              child: content,
            )
          : Material(type: MaterialType.transparency, child: content),
    );
  }
}
