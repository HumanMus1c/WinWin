import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/theme/app_colors.dart';
import 'package:winwin/theme/miuix_theme_bridge.dart' show kMiuixSurfaceAlpha;

/// Miuix 毛玻璃表面：与 `lib/common/widgets/miuix_overlay_panel.dart` 同材质
/// 的可复用底（半透明底 × [kMiuixSurfaceAlpha] + backdrop 模糊 16 + 1px 描边 +
/// 圆角 12 + 4px 下投影）。
///
/// 供**浮于滚动内容之上**的横条类控件复用（分类标签条、按钮行等），使滚动
/// 内容从其后经过时呈模糊；与 `MiuixOverlayPanel` 的差别是不含标题行与内边距，
/// 只承担材质，内容由 [child] 决定。
///
/// 两种档位：
/// - 面板档（默认 `borderRadius = 12`）：四边 1px 描边 + 下投影，用于悬浮条；
/// - 全宽档（`borderRadius = 0`）：不画圆角与投影，仅底部 1px 描边，用于通栏
///   行（如页面顶部的按钮行），避免屏幕边缘出现多余圆角。
class MiuixFrostedSurface extends StatelessWidget {
  const MiuixFrostedSurface({
    super.key,
    required this.child,
    this.borderRadius = 12,
    this.blurSigma = 16,
  });

  /// 表面内容（须自带尺寸：面板档由外部定宽高，全宽档建议 `SizedBox.expand`）。
  final Widget child;

  /// 圆角半径；传 0 取全宽档（无圆角/无投影，仅底部描边）。
  final double borderRadius;

  /// backdrop 模糊半径（默认 16，对齐 `MiuixOverlayPanel`）。
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final isDark = tokens.isDark;
    final baseColor = isDark ? const Color(0xFF262626) : const Color(0xFFEAEAEA);
    final outlineColor = isDark
        ? AppColors.white.withValues(alpha: 0.12)
        : AppColors.black.withValues(alpha: 0.08);
    final isFullBleed = borderRadius <= 0;
    final radius = BorderRadius.circular(isFullBleed ? 0 : borderRadius);

    return Container(
      decoration: BoxDecoration(
        borderRadius: isFullBleed ? null : radius,
        boxShadow: isFullBleed
            ? null
            : [
                BoxShadow(
                  color: AppColors.black.withValues(alpha: isDark ? 0.35 : 0.15),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: baseColor.withValues(alpha: kMiuixSurfaceAlpha),
              borderRadius: isFullBleed ? null : radius,
              border: isFullBleed
                  ? Border(bottom: BorderSide(color: outlineColor))
                  : Border.all(color: outlineColor),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
