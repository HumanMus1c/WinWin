import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

import 'package:winwin/common/widgets/app_dialog_shell.dart';
import 'package:winwin/theme/app_colors.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/core/shell/app_theme_host.dart';

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
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;

    final content = ConstrainedBox(constraints: constraints, child: child);

    // 阶段5d-L1：M3 分支已移除，Miuix 材质为唯一实现。
    // B7-c6-1：路由外壳由 Material `Dialog` 换为零-material 的 `AppDialogShell`
    // （仅承担"居中 + 内边距 + 约束"布局职责；表面仍由下方 `MiuixSurface` 自绘，
    // 故外壳底色透明、圆角归零 ⇒ 视觉零变化）。
    return AppDialogShell(
      backgroundColor: AppColors.transparent,
      borderRadius: Radius.zero,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: Style.lg,
        vertical: Style.xl,
      ),
      child: MiuixSurface(
        cornerRadius: 16,
        color: cs.surface.withValues(alpha: 0.96),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.25),
          width: 0.5,
        ),
        shadowElevation: 8,
        child: content,
      ),
    );
  }
}
