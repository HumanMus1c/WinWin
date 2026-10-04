import 'package:flutter_miuix/miuix.dart';
import 'package:material_ui/material_ui.dart';

/// 普通设置项：标题 + 副标题 + leading + trailing + onTap。
///
/// 移植自 PiliPlus 的 `NormalItem`，去除 GetX 依赖。
/// [onTap] 回调接收 `setState` 用于刷新副标题。
/// Miuix 分支使用 flutter_miuix 的 [MiuixBasicComponent]（阶段2 起替换）。
class NormalItem extends StatefulWidget {
  final String? title;
  final ValueGetter<String>? getTitle;
  final String? subtitle;
  final ValueGetter<String>? getSubtitle;
  final Widget? leading;
  final Widget Function(ThemeData theme)? getTrailing;
  final void Function(BuildContext context, VoidCallback setState)? onTap;
  final EdgeInsetsGeometry? contentPadding;
  final TextStyle? titleStyle;
  final BorderRadius? borderRadius;

  const NormalItem({
    this.title,
    this.getTitle,
    this.subtitle,
    this.getSubtitle,
    this.leading,
    this.getTrailing,
    this.onTap,
    this.contentPadding,
    this.titleStyle,
    this.borderRadius,
    super.key,
  }) : assert(title != null || getTitle != null);

  @override
  State<NormalItem> createState() => _NormalItemState();
}

class _NormalItemState extends State<NormalItem> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = widget.subtitle ?? widget.getSubtitle?.call();
    // trailing 限宽防溢出（对标 BiliPai 数值 maxWidth 200dp）。
    final trailing = widget.getTrailing?.call(theme);

    // 阶段5d-L1：M3 分支已移除；MiuixBasicComponent 恒用。
        final Color? customTitleColor = widget.titleStyle?.color;
        return MiuixBasicComponent(
          title: widget.title ?? widget.getTitle!(),
          summary: text,
          titleColor: customTitleColor == null
              ? null
              : MiuixBasicComponentColors(
                  color: customTitleColor,
                  disabledColor: theme.colorScheme.outline,
                ),
          startAction: widget.leading == null
              ? null
              : IconTheme(
                  data: IconThemeData(
                    color: theme.colorScheme.primary,
                    size: 22,
                  ),
                  child: widget.leading!,
                ),
          endActions: trailing == null
              ? null
              : [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: trailing,
                  ),
                ],
          insideMargin: widget.contentPadding ??
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          onClick: widget.onTap == null
              ? null
              : () => widget.onTap!(context, refresh),
        );
  }

  void refresh() {
    if (mounted) {
      setState(() {});
    }
  }
}

