import 'package:material_ui/material_ui.dart';

import 'package:winwin/core/log/app_logger.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/inherited_ui_style.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/theme/ui_style.dart';

/// 单选对话框：用于画质/音质/主题模式等枚举值选择。
///
/// 移植自 PiliPlus 的 `SelectDialog`，去除 GetX 依赖。
/// 选中后通过 `Navigator.pop` 返回所选值（点选即提交，无确定按钮）。
///
/// 弹窗外壳对齐项目面板惯例（`subtitle_settings_panel.dart` 的双套渲染写法）：
/// M3 用 `surfaceContainerHigh` + 24 圆角；Miuix 用 `surface` 半透明 + 16 圆角 + 描边。
class SelectDialog<T> extends StatelessWidget {
  final T? value;
  final String title;
  final List<(T, String)> values;
  final Widget Function(BuildContext, int)? subtitleBuilder;

  const SelectDialog({
    super.key,
    this.value,
    required this.values,
    required this.title,
    this.subtitleBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isMiuix = InheritedUiStyle.of(context) == UiStyle.miuix;
    final titleMedium = TextTheme.of(context).titleMedium;
    final subtitleStyle = theme.textTheme.labelSmall?.copyWith(
      color: cs.outline,
    );
    final activeColor = isMiuix ? cs.primary : biliPink;

    return Dialog(
      backgroundColor: isMiuix
          ? cs.surface.withValues(alpha: 0.96)
          : cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isMiuix ? 16 : 24),
        side: isMiuix
            ? BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.25),
              )
            : BorderSide.none,
      ),
      insetPadding: const EdgeInsets.symmetric(
        horizontal: Style.lg,
        vertical: Style.xl,
      ),
      child: ConstrainedBox(
        // 带副标题（如界面风格说明）时抬高下限，避免说明文案被硬换行。
        constraints: BoxConstraints(
          minWidth: subtitleBuilder != null ? 320 : 0,
          maxWidth: 420,
          maxHeight: 640,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Style.lg,
                  Style.md,
                  Style.sm,
                  0,
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(title, style: titleMedium)),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(AppIcons.clear(context)),
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Style.sm),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: Style.md),
                  child: RadioGroup<T>(
                    onChanged: (v) => Navigator.of(context).pop(v ?? value),
                    groupValue: value,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(
                        values.length,
                        (index) {
                          final item = values[index];
                          final subtitle = subtitleBuilder?.call(context, index);
                          return RadioListTile<T>(
                            dense: true,
                            value: item.$1,
                            activeColor: activeColor,
                            title: Text(item.$2, style: titleMedium),
                            subtitle: subtitle == null
                                ? null
                                : DefaultTextStyle.merge(
                                    style: subtitleStyle,
                                    child: subtitle,
                                  ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 打开 [SelectDialog] 并返回所选值；`null` 表示未选择（关闭或点遮罩取消）。
///
/// 统一各处调用点的内联 `showDialog` 样板，不改变"点选即提交"语义。
///
/// 覆盖探针：在此单一汇聚点记录 open / close 两条 `[W]` 级日志
/// （Release 只落盘 w/e，故必须用 `[W]` 才能在复测日志中可见），
/// 一次性覆盖全部 10 处调用点。因控件是"点选即提交"，返回值**就是**用户所选，
/// 故无需在控件内部再加一条选择日志。
Future<T?> showSelectDialog<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> values,
  T? value,
  Widget Function(BuildContext, int)? subtitleBuilder,
}) async {
  AppLogger.w(
    'Coverage',
    'SelectDialog open $title (options=${values.length}, current=$value)',
  );
  final result = await showDialog<T>(
    context: context,
    builder: (context) => SelectDialog<T>(
      title: title,
      values: values,
      value: value,
      subtitleBuilder: subtitleBuilder,
    ),
  );
  AppLogger.w(
    'Coverage',
    'SelectDialog close $title → ${result ?? 'cancelled'}',
  );
  return result;
}
