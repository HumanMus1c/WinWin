import 'package:flutter/material.dart';

/// 普通设置项：标题 + 副标题 + leading + trailing + onTap。
///
/// 移植自 PiliPlus 的 `NormalItem`，去除 GetX 依赖。
/// [onTap] 回调接收 `setState` 用于刷新副标题。
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
    super.key,
  }) : assert(title != null || getTitle != null);

  @override
  State<NormalItem> createState() => _NormalItemState();
}

class _NormalItemState extends State<NormalItem> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget? subtitle;
    final text = widget.subtitle ?? widget.getSubtitle?.call();
    if (text != null) {
      subtitle = Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.outline,
        ),
      );
    }
    // trailing 限宽防溢出（对标 BiliPai 数值 maxWidth 200dp）。
    final trailing = widget.getTrailing?.call(theme);
    return ListTile(
      contentPadding: widget.contentPadding,
      onTap: widget.onTap == null ? null : () => widget.onTap!(context, refresh),
      title: Text(
        widget.title ?? widget.getTitle!(),
        style: widget.titleStyle ?? theme.textTheme.titleMedium,
      ),
      subtitle: subtitle,
      leading: widget.leading,
      trailing: trailing == null
          ? null
          : ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: trailing,
            ),
    );
  }

  void refresh() {
    if (mounted) {
      setState(() {});
    }
  }
}
