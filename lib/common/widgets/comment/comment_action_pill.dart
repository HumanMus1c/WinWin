import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart'
    show MiuixPressFeedbackType, MiuixPressable;

import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/app_progress.dart';

/// 评论互动操作的 Miuix 胶囊容器（点赞 / 点踩 / 回复 / 展开收起回复共用）。
///
/// - 胶囊几何：全圆角 + 半透明 `surfaceContainerHighest` 底衬，整块可点击；
/// - 按压反馈：走项目统一的 `MiuixPressable` sink 轻缩（0.98），带 hover 遮罩；
/// - 内容尺寸：图标与文本同为 [fontSize]（名义字号，实际随系统文本缩放），
///   满足「图标随相邻文本字号」口径；
/// - 命中区：最小 24×24（项目可点击控件下限）。
class CommentActionPill extends StatelessWidget {
  const CommentActionPill({
    super.key,
    this.icon,
    this.label,
    this.labelWidget,
    this.trailingIcon,
    this.onPressed,
    required this.fontSize,
    required this.color,
    this.fontWeight = FontWeight.normal,
    this.loading = false,
  });

  /// 前置图标（与 [label] 同尺寸）。
  final IconData? icon;

  /// 文本标签（可为空，退化为纯图标胶囊）。
  final String? label;

  /// 自定义标签部件（优先于 [label]，用于演示模式可内联编辑的计数）。
  final Widget? labelWidget;

  /// 文本后的尾随图标（展开/收起箭头）。
  final IconData? trailingIcon;

  /// 点击回调；null 时胶囊仍展示，但不响应点击。
  final VoidCallback? onPressed;

  /// 胶囊内图标/文本的名义字号。
  final double fontSize;

  /// 图标与文本颜色。
  final Color color;

  final FontWeight fontWeight;

  /// 正在加载时以环形进度替代前置图标。
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final cs = AppThemeHost.of(context).colors;
    final radius = BorderRadius.circular(Style.radiusFull);
    final iconSize = appRowIconSize(context, fontSize);
    final hasLabel = label != null && label!.isNotEmpty;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: Style.xs,
      children: [
        if (loading)
          SizedBox(
            width: iconSize,
            height: iconSize,
            child: AppProgressIndicator(strokeWidth: 1.5, size: iconSize),
          )
        else if (icon != null)
          AppIcon(icon!, size: iconSize, color: color),
        if (labelWidget != null)
          labelWidget!
        else if (hasLabel)
          Text(
            label!,
            maxLines: 1,
            style: TextStyle(
              fontSize: fontSize,
              height: 1.1,
              fontWeight: fontWeight,
              color: color,
            ),
          ),
        if (trailingIcon != null)
          AppIcon(trailingIcon!, size: iconSize, color: color),
      ],
    );

    return MiuixPressable(
      onPressed: onPressed,
      feedbackType: MiuixPressFeedbackType.sink,
      sinkAmount: 0.98,
      borderRadius: radius,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: radius,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Style.sm),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}
