import 'package:flutter/material.dart';

import 'package:winwin/utils/bilibili_emotes.dart';
import 'package:winwin/utils/image_utils.dart';

/// 官方表情面板按钮（自直播互动条 `_buildEmotePickerButton` 移植为共享组件）。
///
/// 40×40 圆形按钮弹出 6 列官方高频表情网格，点选后把 `[xxx]` 转义符
/// 插入 [controller] 选区/光标处，并可选恢复输入焦点。
class OfficialEmotePickerButton extends StatelessWidget {
  const OfficialEmotePickerButton({
    super.key,
    required this.controller,
    this.focusNode,
    this.size = 40.0,
    this.enabled = true,
    this.menuOffset = const Offset(0, -220),
    this.onInserted,
  });

  /// 表情插入目标输入控制器。
  final TextEditingController controller;

  /// 插入后恢复焦点（可空，不传则不请求焦点）。
  final FocusNode? focusNode;

  /// 按钮尺寸（宽高一致）。
  final double size;

  /// 是否可用（false 时置灰且不可点开）。
  final bool enabled;

  /// 弹层相对按钮的偏移（默认向上弹出，适配底部输入栏）。
  final Offset menuOffset;

  /// 插入完成回调（供调用方刷新依赖输入文本的 UI）。
  final VoidCallback? onInserted;

  void _insert(String code) {
    final currentText = controller.text;
    final selection = controller.selection;
    final newText = (selection.start >= 0 && selection.end >= 0)
        ? currentText.replaceRange(selection.start, selection.end, code)
        : '$currentText$code';
    controller.text = newText;
    controller.selection = TextSelection.collapsed(
      offset: selection.start >= 0
          ? selection.start + code.length
          : newText.length,
    );
    onInserted?.call();
    focusNode?.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      tooltip: '选择官方表情',
      enabled: enabled,
      padding: EdgeInsets.zero,
      color: const Color(0xF01E1E1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.white12),
      ),
      offset: menuOffset,
      onSelected: _insert,
      itemBuilder: (context) {
        return [
          PopupMenuItem<String>(
            enabled: false,
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              width: 260,
              height: 200,
              child: GridView.builder(
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                ),
                itemCount: BilibiliEmotes.popularEmotes.length,
                itemBuilder: (context, i) {
                  final code = BilibiliEmotes.popularEmotes[i];
                  final url = BilibiliEmotes.defaultEmotes[code];
                  return InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => Navigator.pop(context, code),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: url != null
                          ? Image.network(
                              ImageUtils.thumbnailUrl(url, type: 'emote'),
                              width: 28,
                              height: 28,
                              fit: BoxFit.contain,
                              cacheWidth: 64,
                              cacheHeight: 64,
                              errorBuilder: (_, _, _) => Center(
                                child: Text(
                                  code,
                                  style: const TextStyle(fontSize: 10),
                                ),
                              ),
                            )
                          : Center(
                              child: Text(
                                code,
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                    ),
                  );
                },
              ),
            ),
          ),
        ];
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: enabled
              ? cs.surface.withValues(alpha: 0.75)
              : cs.surface.withValues(alpha: 0.4),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.sentiment_satisfied_alt_outlined,
          color: enabled ? cs.outline : cs.outline.withValues(alpha: 0.4),
          size: 20,
        ),
      ),
    );
  }
}
