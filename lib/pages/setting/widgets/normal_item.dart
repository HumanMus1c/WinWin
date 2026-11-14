import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter/widgets.dart';

import 'package:winwin/theme/app_icons.dart';

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
  final Widget Function(AppTokens tokens)? getTrailing;
  final void Function(BuildContext context, VoidCallback setState)? onTap;
  final EdgeInsetsGeometry? contentPadding;
  final TextStyle? titleStyle;
  final BorderRadius? borderRadius;

  /// 是否可用；false 时整行置灰且不可点击（功能尚未实现）。
  final bool enabled;

  /// 标题行尾随部件（如「尚未实现」角标）。
  final Widget? titleTrailing;

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
    this.enabled = true,
    this.titleTrailing,
    super.key,
  }) : assert(title != null || getTitle != null);

  @override
  State<NormalItem> createState() => _NormalItemState();
}

class _NormalItemState extends State<NormalItem> {
  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final text = widget.subtitle ?? widget.getSubtitle?.call();
    // trailing 限宽防溢出（对标 BiliPai 数值 maxWidth 200dp）。
    final trailing = widget.getTrailing?.call(tokens);

    // 阶段5d-L1：M3 分支已移除；MiuixBasicComponent 恒用。
    final Color? customTitleColor = widget.titleStyle?.color;
    final titleColors = customTitleColor == null
        ? MiuixBasicComponentDefaults.titleColor(context)
        : MiuixBasicComponentColors(
            color: customTitleColor,
            disabledColor: tokens.colors.outline,
          );

    return MiuixBasicComponent(
      // 标题后需挂角标时改用 content 自绘（MiuixBasicComponent 的 title 仅支持字符串）。
      title: widget.titleTrailing == null
          ? (widget.title ?? widget.getTitle!())
          : null,
      summary: widget.titleTrailing == null ? text : null,
      content: widget.titleTrailing == null
          ? null
          : _buildContent(context, text, titleColors),
      titleColor: widget.titleTrailing == null ? titleColors : null,
      startAction: widget.leading == null
          ? null
          : IconTheme(
              data: IconThemeData(
                color: widget.enabled
                    ? tokens.colors.primary
                    : tokens.colors.outline,
                // 与行标题同口径：MiuixBasicComponent 标题字号（headline1）。
                size: appRowIconSize(context),
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
      enabled: widget.enabled,
      onClick: !widget.enabled || widget.onTap == null
          ? null
          : () => widget.onTap!(context, refresh),
    );
  }

  /// 标题 + 尾随角标（如「尚未实现」）+ 副标题。
  ///
  /// 字号/字重/颜色解析口径与 [MiuixBasicComponent] 内置 title/summary 一致。
  List<Widget> _buildContent(
    BuildContext context,
    String? text,
    MiuixBasicComponentColors titleColors,
  ) {
    final textStyles = MiuixTheme.of(context).textStyles;
    return [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: MiuixText(
              widget.title ?? widget.getTitle!(),
              fontSize: textStyles.headline1.fontSize,
              fontWeight: FontWeight.w500,
              color: titleColors.resolve(widget.enabled),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          widget.titleTrailing!,
        ],
      ),
      if (text != null)
        MiuixText(
          text,
          fontSize: textStyles.body2.fontSize,
          color: MiuixBasicComponentDefaults.summaryColor(context)
              .resolve(widget.enabled),
        ),
    ];
  }

  void refresh() {
    if (mounted) {
      setState(() {});
    }
  }
}

