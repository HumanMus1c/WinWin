import 'package:flutter_miuix/miuix.dart';
import 'package:material_ui/material_ui.dart';

import 'package:winwin/common/widgets/miuix_dialog_shell.dart';
import 'package:winwin/core/log/app_logger.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/core/shell/app_dialogs.dart';

/// 单选对话框：用于画质/音质/主题模式等枚举值选择。
///
/// 移植自 PiliPlus 的 `SelectDialog`，去除 GetX 依赖。
/// 选中后通过 `Navigator.pop` 返回所选值（点选即提交，无确定按钮）。
///
/// 外壳统一走 [MiuixDialogShell]（M3 surfaceContainerHigh+24 / Miuix squircle
/// 16）；选项行在 Miuix 风格下改用 flutter_miuix 的 [MiuixRadioButton] +
/// [MiuixBasicComponent] 组合行（阶段3a 起替换原 RadioListTile 近似）。
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
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final titleMedium = TextTheme.of(context).titleMedium;
    final subtitleStyle = tokens.text.labelSmall?.copyWith(
      color: cs.outline,
    );

    return MiuixDialogShell(
      // 带副标题（如界面风格说明）时抬高下限，避免说明文案被硬换行。
      constraints: BoxConstraints(
        minWidth: subtitleBuilder != null ? 320 : 0,
        maxWidth: 420,
        maxHeight: 640,
      ),
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
                MiuixIconButton(
                  minWidth: 24,
                  minHeight: 24,
                  child: Tooltip(
                    message: '关闭',
                    child: AppIcon(AppIcons.clear()),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const SizedBox(height: Style.sm),
          const MiuixHorizontalDivider(),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: Style.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  values.length,
                  (index) => _buildMiuixOption(
                    context,
                    index,
                    titleMedium,
                    subtitleStyle,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Miuix 选项行：单选按钮 + 标题/副标题内容 + 整行点选即提交。
  Widget _buildMiuixOption(
    BuildContext context,
    int index,
    TextStyle? titleStyle,
    TextStyle? subtitleStyle,
  ) {
    final item = values[index];
    final subtitle = subtitleBuilder?.call(context, index);
    void commit() => Navigator.of(context).pop(item.$1);

    return MiuixBasicComponent(
      startAction: MiuixRadioButton(
        selected: item.$1 == value,
        onChanged: (_) => commit(),
      ),
      content: [
        Text(item.$2, style: titleStyle),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          DefaultTextStyle.merge(style: subtitleStyle, child: subtitle),
        ],
      ],
      onClick: commit,
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
  final result = await showAppDialog<T>(
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
