import 'package:flutter/material.dart';

import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/theme/inherited_ui_style.dart';
import 'package:winwin/theme/ui_style.dart';
import 'package:winwin/ui/components/app_components.dart';

/// 开关设置项：自动从 [GStorage.setting] 读取初始值，切换时写回。
///
/// 移植自 PiliPlus 的 `SetSwitchItem`，去除 GetX/SmartDialog 依赖。
/// [isSplit] 为 true 时左侧点击进入子设置（[onTap]），右侧独立开关。
class SetSwitchItem extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String setKey;
  final bool defaultVal;
  final ValueChanged<bool>? onChanged;
  final bool needReboot;
  final Widget? leading;
  final void Function(BuildContext context)? onTap;
  final EdgeInsetsGeometry? contentPadding;
  final TextStyle? titleStyle;
  final bool isSplit;

  const SetSwitchItem({
    super.key,
    required this.title,
    this.subtitle,
    required this.setKey,
    this.defaultVal = false,
    this.onChanged,
    this.needReboot = false,
    this.leading,
    this.onTap,
    this.contentPadding,
    this.titleStyle,
    this.isSplit = false,
  });

  @override
  State<SetSwitchItem> createState() => _SetSwitchItemState();
}

class _SetSwitchItemState extends State<SetSwitchItem> {
  late bool val;

  void setVal() {
    val = GStorage.setting.get(
      widget.setKey,
      defaultValue: widget.defaultVal,
    );
  }

  @override
  void didUpdateWidget(SetSwitchItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.setKey != widget.setKey) {
      setVal();
    }
  }

  @override
  void initState() {
    super.initState();
    setVal();
  }

  Future<void> switchChange([bool? value]) async {
    val = value ?? !val;
    await GStorage.setting.put(widget.setKey, val);
    widget.onChanged?.call(val);
    if (widget.needReboot && mounted) {
      showToast(context, '重启生效', duration: const Duration(seconds: 2));
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = InheritedUiStyle.of(context);
    final renderer = resolvePrimitiveRenderer(style);
    final theme = Theme.of(context);
    final titleStyle = widget.titleStyle ??
        theme.textTheme.titleMedium?.copyWith(
          color: widget.onTap != null && !val
              ? theme.colorScheme.outline
              : null,
        );
    final subTitleStyle = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.outline,
    );

    final switchBtn = Transform.scale(
      scale: 0.8,
      alignment: Alignment.centerRight,
      child: Switch(
        value: val,
        onChanged: switchChange,
      ),
    );

    final miuixSwitchBtn = AppSwitch(
      value: val,
      onChanged: switchChange,
    );

    switch (renderer) {
      case PrimitiveRenderer.material3:
        Widget child(Widget? trailing) => ListTile(
              contentPadding: widget.contentPadding,
              enabled: widget.onTap == null ? true : val,
              onTap: widget.onTap == null
                  ? switchChange
                  : () => widget.onTap!(context),
              title: Text(widget.title, style: titleStyle),
              subtitle: widget.subtitle != null
                  ? Text(
                      widget.subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: subTitleStyle,
                    )
                  : null,
              leading: widget.leading,
              trailing: trailing,
            );

        if (widget.isSplit) {
          return Row(
            children: [
              Expanded(child: child(null)),
              SizedBox(
                height: 25,
                child: VerticalDivider(
                  width: 1,
                  color: theme.colorScheme.outline.withValues(alpha: 0.3),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 24),
                child: switchBtn,
              ),
            ],
          );
        }

        return child(switchBtn);

      case PrimitiveRenderer.miuix:
        Widget miuixContent() => Row(
              children: [
                if (widget.leading != null) ...[
                  IconTheme(
                    data: IconThemeData(
                      color: theme.colorScheme.primary,
                      size: 22,
                    ),
                    child: widget.leading!,
                  ),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: widget.titleStyle ??
                            theme.textTheme.bodyLarge?.copyWith(
                              color: widget.onTap != null && !val
                                  ? theme.colorScheme.outline
                                  : null,
                            ),
                      ),
                      if (widget.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: subTitleStyle,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );

        if (widget.isSplit) {
          return Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: widget.contentPadding ??
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: !val
                        ? null
                        : (widget.onTap == null
                            ? switchChange
                            : () => widget.onTap!(context)),
                    child: miuixContent(),
                  ),
                ),
                SizedBox(
                  height: 25,
                  child: VerticalDivider(
                    width: 1,
                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: miuixSwitchBtn,
                ),
              ],
            ),
          );
        }

        return InkWell(
          onTap: switchChange,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: widget.contentPadding ??
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(child: miuixContent()),
                const SizedBox(width: 8),
                miuixSwitchBtn,
              ],
            ),
          ),
        );
    }
  }
}

