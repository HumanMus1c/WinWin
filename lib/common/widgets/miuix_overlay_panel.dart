import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';

import 'package:winwin/theme/miuix_theme_bridge.dart';

/// 共用毛玻璃浮层面板（弹幕样式 / 表情面板等二级浮层共用，样式单一来源）。
///
/// 统一要素（复测反馈"统一面板设计"）：
/// - 12 圆角 + blur 16 毛玻璃 + 1px 描边 + 4px 下投影；
/// - 半透明底：浅色 #EAEAEA / 暗色 #262626 × [kMiuixSurfaceAlpha]
///   （与 Toast、弹层壳同源，集中调整）；
/// - 标题行（图标 + 标题 + 分隔线）与内容内边距 16。
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final baseColor = isDark ? const Color(0xFF262626) : const Color(0xFFEAEAEA);
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.08);

    return Material(
      type: MaterialType.transparency,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.15),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              decoration: BoxDecoration(
                color: baseColor.withValues(alpha: kMiuixSurfaceAlpha),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.08),
                  width: 1,
                ),
              ),
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
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(height: 1, color: dividerColor),
                  const SizedBox(height: 10),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
