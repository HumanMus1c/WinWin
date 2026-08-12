import 'package:flutter/material.dart';

import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/http/danmaku.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/pages/video/player_controller.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';

/// 弹幕发送面板（移植自 PiliPlus `lib/pages/video/send_danmaku/view.dart`）。
///
/// WinWin 精简版：不引入 GetX / chat_bottom_container，改用 ValueNotifier +
/// showModalBottomSheet。保留核心能力：文本输入（≤100 字）、模式切换
/// （滚动/顶部/底部）、颜色预设选择、发送成功后本地回显。
///
/// 弹出方式：[showSendDanmakuPanel]，由播放器控制条「发弹幕」按钮调用
/// （全屏态使用）；内联模式见 [SendDanmakuPanel.inline]，嵌入视频页
/// 播放器正下方。
void showSendDanmakuPanel(
  BuildContext context, {
  required WinWinPlayerController controller,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SendDanmakuPanel(controller: controller),
    ),
  );
}

class SendDanmakuPanel extends StatefulWidget {
  const SendDanmakuPanel({
    super.key,
    required this.controller,
    this.inline = false,
  });

  final WinWinPlayerController controller;

  /// true：内联嵌入视频页播放器正下方（不自动聚焦、发送成功不关闭面板，
  /// 仅清空输入框）；false：底部弹窗模式（「发弹幕」按钮弹出）。
  final bool inline;

  @override
  State<SendDanmakuPanel> createState() => _SendDanmakuPanelState();
}

class _SendDanmakuPanelState extends State<SendDanmakuPanel> {
  late final TextEditingController _textController;
  late final ValueNotifier<int> _mode;
  late final ValueNotifier<Color> _color;
  final ValueNotifier<bool> _sending = ValueNotifier(false);
  final FocusNode _focusNode = FocusNode();

  /// 弹幕颜色预设（与 PiliPlus 一致，共 14 色）。
  static const List<Color> _colorList = [
    Colors.white,
    Color(0xFFFE0302),
    Color(0xFFFF7204),
    Color(0xFFFFAA02),
    Color(0xFFFFD302),
    Color(0xFFFFFF00),
    Color(0xFFA0EE00),
    Color(0xFF00CD00),
    Color(0xFF019899),
    Color(0xFF4266BE),
    Color(0xFF89D5FF),
    Color(0xFFCC0273),
    Color(0xFF222222),
    Color(0xFF9B9B9B),
  ];

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _mode = ValueNotifier(1);
    _color = ValueNotifier(Colors.white);
  }

  @override
  void dispose() {
    _textController.dispose();
    _mode.dispose();
    _color.dispose();
    _sending.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _canSend =>
      _textController.text.trim().isNotEmpty && !_sending.value;

  Future<void> _onSend() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _sending.value) return;

    if (!Accounts.main.isLogin) {
      _toast('请先登录');
      return;
    }
    if (widget.controller.danmaku?.danmakuClosed == true) {
      _toast('UP 主已关闭弹幕');
      return;
    }

    _sending.value = true;
    final mode = _mode.value;
    final color = _color.value.toARGB32() & 0xFFFFFF;
    final res = await DanmakuHttp.shootDanmaku(
      oid: widget.controller.cid,
      bvid: widget.controller.bvid,
      msg: text,
      mode: mode,
      progress: widget.controller.position.value.inMilliseconds,
      color: color,
    );
    if (!mounted) {
      _sending.value = false;
      return;
    }
    switch (res) {
      case Success():
        // 本地回显：立即上屏，无需等待服务端重新拉取。
        widget.controller.danmaku?.addLocal(
          text: text,
          mode: mode,
          color: color,
        );
        _toast('发送成功');
        if (widget.inline) {
          // 内联模式：不关闭面板，仅清空输入框。
          _textController.clear();
          setState(() {});
        } else {
          Navigator.of(context).pop();
        }
      case Error(:final errMsg):
        _toast(errMsg ?? '发送失败');
      case Loading():
        break;
    }
    _sending.value = false;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inline = widget.inline;
    return Container(
      // 内联模式宽度由外层（视频宽度）决定，弹窗模式限制最大宽度。
      constraints: inline ? null : const BoxConstraints(maxWidth: 560),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: inline
            ? null
            : const BorderRadius.vertical(
                top: Radius.circular(Style.radiusMd),
              ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildInputRow(theme),
          const Divider(height: 1),
          _buildOptions(theme),
          SizedBox(
            height: inline
                ? Style.sm
                : MediaQuery.of(context).padding.bottom + Style.sm,
          ),
        ],
      ),
    );
  }

  /// 顶部输入行：文本框 + 清空 + 发送。
  Widget _buildInputRow(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Style.md,
        vertical: Style.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              focusNode: _focusNode,
              // 内联模式不自动聚焦，避免进入视频页时抢占焦点。
              autofocus: !widget.inline,
              maxLength: 100,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _onSend(),
              onChanged: (_) => setState(() {}),
              style: theme.textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: '输入弹幕内容',
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Style.radiusSm),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: theme.colorScheme.onInverseSurface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: Style.md,
                  vertical: Style.sm,
                ),
              ),
            ),
          ),
          const SizedBox(width: Style.sm),
          if (_textController.text.isNotEmpty)
            IconButton(
              tooltip: '清空',
              icon: const Icon(Icons.clear, size: 20),
              onPressed: () {
                _textController.clear();
                setState(() {});
              },
            ),
          ValueListenableBuilder<bool>(
            valueListenable: _sending,
            builder: (context, sending, _) {
              return IconButton(
                tooltip: '发送',
                icon: sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send, size: 20),
                color: _canSend ? biliPink : theme.colorScheme.outline,
                onPressed: _canSend ? _onSend : null,
              );
            },
          ),
        ],
      ),
    );
  }

  /// 模式 + 颜色选项区。
  Widget _buildOptions(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Style.md,
        vertical: Style.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildModeRow(theme),
          const SizedBox(height: Style.md),
          _buildColorRow(theme),
        ],
      ),
    );
  }

  /// 模式切换：滚动(1) / 顶部(5) / 底部(4)。
  Widget _buildModeRow(ThemeData theme) {
    const modes = [
      (mode: 1, label: '滚动'),
      (mode: 5, label: '顶部'),
      (mode: 4, label: '底部'),
    ];
    return Row(
      children: [
        Text('弹幕样式', style: theme.textTheme.bodyMedium),
        const SizedBox(width: Style.md),
        Expanded(
          child: ValueListenableBuilder<int>(
            valueListenable: _mode,
            builder: (context, selected, _) {
              return Row(
                children: [
                  for (final m in modes) ...[
                    Expanded(child: _buildModeChip(theme, m.mode, m.label, selected == m.mode)),
                    if (m != modes.last) const SizedBox(width: Style.sm),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildModeChip(
    ThemeData theme,
    int mode,
    String label,
    bool selected,
  ) {
    return GestureDetector(
      onTap: () => _mode.value = mode,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: Style.sm),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.secondaryContainer
              : theme.colorScheme.onInverseSurface,
          borderRadius: BorderRadius.circular(Style.radiusSm),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? theme.colorScheme.onSecondaryContainer
                : theme.colorScheme.outline,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  /// 颜色预设色块网格。
  Widget _buildColorRow(ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('弹幕颜色', style: theme.textTheme.bodyMedium),
        const SizedBox(width: Style.md),
        Expanded(
          child: ValueListenableBuilder<Color>(
            valueListenable: _color,
            builder: (context, selected, _) {
              return Wrap(
                spacing: Style.sm,
                runSpacing: Style.sm,
                children: [
                  for (final c in _colorList) _buildColorItem(c, selected),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildColorItem(Color color, Color selected) {
    final isSelected = color == selected;
    return GestureDetector(
      onTap: () => _color.value = color,
      child: Container(
        width: 32,
        height: 32,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Style.radiusSm),
          border: isSelected
              ? Border.all(width: 2, color: biliPink)
              : null,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}
