import 'package:flutter_miuix/miuix.dart';
import 'package:material_ui/material_ui.dart';

import 'package:winwin/common/widgets/miuix_dialog_shell.dart';
import 'package:winwin/theme/style.dart';

/// 通用滑块设置对话框（字体大小 / 界面缩放 / 缓冲大小 / 缓冲时长共用）。
///
/// - MD3：AlertDialog + Slider（原内联实现行为保留）；
/// - Miuix：[MiuixDialogShell] + [MiuixSlider]（宽松宽度语境显式撑满，
///   修复"CustomPaint 坍缩为 0 宽不可见"）+ [MiuixTextButton] 操作区。
///
/// 返回值为 `null`（取消）或所选值（确定）。[decimals] 为 null 时按原缓冲
/// 对话框的自适应格式（整数不带小数位），否则固定小数位。
class AppSliderDialog extends StatefulWidget {
  const AppSliderDialog({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    this.suffix = '',
    this.decimals,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String suffix;
  final int? decimals;

  @override
  State<AppSliderDialog> createState() => _AppSliderDialogState();
}

class _AppSliderDialogState extends State<AppSliderDialog> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.value;
  }

  String get _valueLabel {
    final decimals =
        widget.decimals ?? (_value == _value.roundToDouble() ? 0 : 1);
    return '${_value.toStringAsFixed(decimals)}${widget.suffix}';
  }

  @override
  Widget build(BuildContext context) {
    // 阶段5d-L1：M3 分支已移除。
    final theme = Theme.of(context);
    return MiuixDialogShell(
        constraints: const BoxConstraints(minWidth: 320, maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Style.lg,
            Style.md,
            Style.lg,
            Style.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: theme.textTheme.titleMedium),
              const SizedBox(height: Style.md),
              Center(
                child: Text(
                  _valueLabel,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: Style.sm),
              SizedBox(
                width: double.infinity,
                child: MiuixSlider(
                  value: _value,
                  min: widget.min,
                  max: widget.max,
                  steps: widget.divisions > 1 ? widget.divisions - 1 : 0,
                  onValueChanged: (v) => setState(() => _value = v),
                ),
              ),
              const SizedBox(height: Style.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  MiuixTextButton(
                    '取消',
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: Style.sm),
                  MiuixTextButton(
                    '确定',
                    colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                    onPressed: () => Navigator.pop(context, _value),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
  }
}
