import 'package:flutter/material.dart';

/// 单选对话框：用于画质/音质/主题模式等枚举值选择。
///
/// 移植自 PiliPlus 的 `SelectDialog`，去除 GetX 依赖。
/// 选中后通过 `Navigator.pop` 返回所选值。
class SelectDialog<T> extends StatelessWidget {
  final T? value;
  final String title;
  final List<(T, String)> values;
  final Widget Function(BuildContext, int)? subtitleBuilder;
  final bool toggleable;

  const SelectDialog({
    super.key,
    this.value,
    required this.values,
    required this.title,
    this.subtitleBuilder,
    this.toggleable = false,
  });

  @override
  Widget build(BuildContext context) {
    final titleMedium = Theme.of(context).textTheme.titleMedium;
    return AlertDialog(
      clipBehavior: Clip.hardEdge,
      title: Text(title),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      content: Material(
        type: MaterialType.transparency,
        child: SingleChildScrollView(
          child: RadioGroup<T>(
            onChanged: (v) => Navigator.of(context).pop(v ?? value),
            groupValue: value,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                values.length,
                (index) {
                  final item = values[index];
                  return RadioListTile<T>(
                    toggleable: toggleable,
                    dense: true,
                    value: item.$1,
                    title: Text(item.$2, style: titleMedium),
                    subtitle: subtitleBuilder?.call(context, index),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
