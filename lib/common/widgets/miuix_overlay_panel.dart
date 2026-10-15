import 'package:material_ui/material_ui.dart';

import 'package:winwin/common/widgets/miuix_frosted_surface.dart';
import 'package:winwin/theme/app_colors.dart';
import 'package:winwin/core/shell/app_theme_host.dart';

/// 共用毛玻璃浮层面板（弹幕样式 / 表情面板等二级浮层共用，样式单一来源）。
///
/// 统一要素（复测反馈"统一面板设计"）：
/// - 12 圆角 + blur 16 毛玻璃 + 1px 描边 + 4px 下投影；
/// - 半透明底：浅色 #EAEAEA / 暗色 #262626 × `kMiuixSurfaceAlpha`
///   （与 Toast、弹层壳同源，集中调整）；
/// - 标题行（图标 + 标题 + 分隔线）与内容内边距 16。
///
/// **材质（圆角 / 毛玻璃 / 描边 / 投影 / 边缘无渐变）由 [MiuixFrostedSurface]
/// 单点承担**，本组件只在其上补标题行与内边距，避免材质口径分散在多处。
///
/// 展开动画不在本组件内：调用方按"贴触发器对角锚点"自行包
/// Fade + Scale（对齐表情面板的对角线展开），本组件仅负责材质与排版。
class MiuixOverlayPanel extends StatelessWidget {
  const MiuixOverlayPanel({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final String title;

  /// 标题前图标（尺寸/颜色由调用方决定，惯例 16）。
  final Widget icon;

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final isDark = tokens.isDark;
    final dividerColor = isDark
        ? AppColors.white.withValues(alpha: 0.10)
        : AppColors.black.withValues(alpha: 0.08);

    return Material(
      type: MaterialType.transparency,
      child: MiuixFrostedSurface(
        borderRadius: 12,
        child: Padding(
          padding: padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  icon,
                  const SizedBox(width: 6),
                  Text(
                    title,
                    style: tokens.text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(height: 1, color: dividerColor),
              const SizedBox(height: 10),
              // 内容区弹性收缩：外层高度受限（窗口过矮 / 视窗内布局）时，
              // 面板整体收窄到可用高度，由调用方的滚动区承担滚动，不越界。
              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }
}