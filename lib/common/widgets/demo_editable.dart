import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/core/demo/demo_overrides.dart';
import 'package:winwin/core/storage/storage_pref.dart';

/// 演示模式下可即时编辑的数字元素。
///
/// • 渲染值 = `DemoOverrides 覆盖值 ?? value`（仅演示模式读取覆盖值）；
/// • 演示模式下可 hover 高亮、点击编辑，编辑结果立即落盘并立即渲染；
/// • 演示关闭时直接返回 [builder] 原样结果，行为与改动前完全一致。
class DemoEditableNumber extends StatefulWidget {
  const DemoEditableNumber({
    super.key,
    required this.overrideKey,
    required this.value,
    required this.builder,
    this.title,
  });

  /// DemoOverrides 存储键（如 `profile.coins`）。
  final String overrideKey;

  /// 真实值（无覆盖时展示）。
  final num? value;

  /// 根据展示值构建子组件。
  final Widget Function(BuildContext context, num? display) builder;

  /// 编辑弹层标题（如「粉丝数」）。
  final String? title;

  @override
  State<DemoEditableNumber> createState() => _DemoEditableNumberState();
}

class _DemoEditableNumberState extends State<DemoEditableNumber> {
  @override
  void initState() {
    super.initState();
    Pref.demoModeNotifier.addListener(_onDemoChanged);
  }

  @override
  void dispose() {
    Pref.demoModeNotifier.removeListener(_onDemoChanged);
    super.dispose();
  }

  void _onDemoChanged() {
    if (mounted) setState(() {});
  }

  num? get _display => DemoOverrides.number(widget.overrideKey) ?? widget.value;

  void _edit() {
    showDialog<void>(
      context: context,
      builder: (ctx) => _DemoNumberDialog(
        title: widget.title ?? '编辑数值',
        initial: _display == null ? '' : '${_display!.round()}',
        canReset: DemoOverrides.number(widget.overrideKey) != null,
        onApply: (value) async {
          await DemoOverrides.set(widget.overrideKey, value);
          if (mounted) setState(() {});
        },
        onReset: () async {
          await DemoOverrides.clear(widget.overrideKey);
          if (mounted) setState(() {});
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!Pref.demoMode) return widget.builder(context, widget.value);
    return _DemoEditShell(
      onEdit: _edit,
      child: widget.builder(context, _display),
    );
  }
}

/// 演示模式下可即时编辑的枚举/类型元素（下拉列出该控件支持的全部类型）。
///
/// 渲染值 = `DemoOverrides 覆盖值 ?? value`；其余同 [DemoEditableNumber]。
class DemoEditableChoice extends StatefulWidget {
  const DemoEditableChoice({
    super.key,
    required this.overrideKey,
    required this.value,
    required this.options,
    required this.builder,
    this.title,
  });

  /// DemoOverrides 存储键（如 `profile.vipType`）。
  final String overrideKey;

  /// 真实值（无覆盖时展示）。
  final int? value;

  /// 该控件支持的全部类型：(值, 显示名)。
  final List<(int, String)> options;

  /// 根据展示值构建子组件。
  final Widget Function(BuildContext context, int? display) builder;

  /// 选择弹层标题（如「VIP 类型」）。
  final String? title;

  @override
  State<DemoEditableChoice> createState() => _DemoEditableChoiceState();
}

class _DemoEditableChoiceState extends State<DemoEditableChoice> {
  @override
  void initState() {
    super.initState();
    Pref.demoModeNotifier.addListener(_onDemoChanged);
  }

  @override
  void dispose() {
    Pref.demoModeNotifier.removeListener(_onDemoChanged);
    super.dispose();
  }

  void _onDemoChanged() {
    if (mounted) setState(() {});
  }

  int? get _display => DemoOverrides.choice(widget.overrideKey) ?? widget.value;

  void _edit() {
    showDialog<void>(
      context: context,
      builder: (ctx) => _DemoChoiceDialog(
        title: widget.title ?? '选择类型',
        current: _display,
        options: widget.options,
        canReset: DemoOverrides.choice(widget.overrideKey) != null,
        onPick: (value) async {
          await DemoOverrides.set(widget.overrideKey, value);
          if (mounted) setState(() {});
        },
        onReset: () async {
          await DemoOverrides.clear(widget.overrideKey);
          if (mounted) setState(() {});
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!Pref.demoMode) return widget.builder(context, widget.value);
    return _DemoEditShell(
      onEdit: _edit,
      child: widget.builder(context, _display),
    );
  }
}

/// 可编辑元素的共用外壳：hover 高亮 + 点击编辑入口。
///
/// [IgnorePointer] 让子控件不参与命中测试，点击统一交给编辑入口
/// （演示模式下元素语义为"可编辑"，不作为正常交互目标）。
class _DemoEditShell extends StatefulWidget {
  const _DemoEditShell({required this.onEdit, required this.child});

  final VoidCallback onEdit;
  final Widget child;

  @override
  State<_DemoEditShell> createState() => _DemoEditShellState();
}

class _DemoEditShellState extends State<_DemoEditShell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: '演示模式：点击编辑',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onEdit,
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: _hovered
                    ? cs.primary.withValues(alpha: 0.10)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// 数字编辑弹层：输入非负整数 + 确定 / 取消 / 恢复默认。
class _DemoNumberDialog extends StatefulWidget {
  const _DemoNumberDialog({
    required this.title,
    required this.initial,
    required this.canReset,
    required this.onApply,
    required this.onReset,
  });

  final String title;
  final String initial;
  final bool canReset;
  final ValueChanged<int> onApply;
  final VoidCallback onReset;

  @override
  State<_DemoNumberDialog> createState() => _DemoNumberDialogState();
}

class _DemoNumberDialogState extends State<_DemoNumberDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = int.tryParse(_controller.text.trim());
    if (value == null || value < 0) {
      showToast(context, '请输入非负整数');
      return;
    }
    widget.onApply(value);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(hintText: '非负整数'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        if (widget.canReset)
          TextButton(
            onPressed: () {
              widget.onReset();
              Navigator.pop(context);
            },
            child: const Text('恢复默认'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('确定'),
        ),
      ],
    );
  }
}

/// 类型选择弹层：列出该控件支持的全部类型 + 恢复默认。
class _DemoChoiceDialog extends StatelessWidget {
  const _DemoChoiceDialog({
    required this.title,
    required this.current,
    required this.options,
    required this.canReset,
    required this.onPick,
    required this.onReset,
  });

  final String title;
  final int? current;
  final List<(int, String)> options;
  final bool canReset;
  final ValueChanged<int> onPick;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SimpleDialog(
      title: Text(title),
      children: [
        for (final (value, label) in options)
          SimpleDialogOption(
            onPressed: () {
              onPick(value);
              Navigator.pop(context);
            },
            child: Row(
              children: [
                Icon(
                  value == current
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: value == current ? cs.primary : cs.outline,
                ),
                const SizedBox(width: 10),
                Text(label),
              ],
            ),
          ),
        if (canReset)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () {
                  onReset();
                  Navigator.pop(context);
                },
                child: const Text('恢复默认'),
              ),
            ),
          ),
      ],
    );
  }
}
