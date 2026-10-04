import 'package:flutter_miuix/miuix.dart';
import 'package:material_ui/material_ui.dart';

import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/ui/components/app_components.dart';

/// 开关设置项：自动从 [GStorage.setting] 读取初始值，切换时写回。
///
/// 移植自 PiliPlus 的 `SetSwitchItem`，去除 GetX/SmartDialog 依赖。
/// [isSplit] 为 true 时左侧点击进入子设置（[onTap]），右侧独立开关。
/// Miuix 非 split 分支使用 flutter_miuix 的 [MiuixSwitchPreference]（阶段2）。
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
    final theme = Theme.of(context);
    final subTitleStyle = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.outline,
    );

    final miuixSwitchBtn = AppSwitch(
      value: val,
      onChanged: switchChange,
    );

    // 阶段5d-L1：M3 分支已移除；miuix 分支恒用。
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

        final Color? customTitleColor = widget.titleStyle?.color;
        return MiuixSwitchPreference(
          value: val,
          onChanged: switchChange,
          title: widget.title,
          summary: widget.subtitle,
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
          insideMargin: widget.contentPadding ??
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        );
  }
}

