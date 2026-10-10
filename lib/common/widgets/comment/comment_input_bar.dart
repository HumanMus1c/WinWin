import 'package:material_ui/material_ui.dart';

import 'package:winwin/theme/app_colors.dart';
import 'package:winwin/common/widgets/comment/emote_picker.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/ui/components/app_progress.dart';
import 'package:winwin/ui/components/app_components.dart';

/// 简洁评论输入栏（专栏 / 动态详情页使用）：
/// 官方表情面板按钮 + 胶囊输入框 + 粉色发送按钮。
///
/// 容器样式对齐视频详情页 `_buildCommentInputBar`（surface 底、
/// 顶部 0.5 描边、SafeArea 底适配）。
class SimpleCommentInputBar extends StatelessWidget {
  const SimpleCommentInputBar({
    super.key,
    required this.controller,
    this.focusNode,
    required this.sending,
    required this.onSend,
    this.hintText = '发一条友善的评论吧~',
    this.enabled = true,
  });

  /// 评论输入控制器。
  final TextEditingController controller;

  /// 输入焦点（同时传给表情面板按钮，插入后恢复焦点）。
  final FocusNode? focusNode;

  /// 是否正在发送（true 时按钮转圈且不可重复提交）。
  final bool sending;

  /// 发送回调。
  final Future<void> Function() onSend;

  /// 占位提示文案。
  final String hintText;

  /// 是否可用。
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        Style.safeSpace,
        Style.xs,
        Style.cardSpace,
        Style.xs,
      ),
      decoration: BoxDecoration(
        color: tokens.colors.surface,
        border: Border(
          top: BorderSide(
            color: tokens.colors.outlineVariant.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // 官方表情面板按钮（输入框左侧，直播互动条同款）
            OfficialEmotePickerButton(
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
            ),
            const SizedBox(width: Style.sm),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                enabled: enabled,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: Style.md,
                    vertical: Style.sm,
                  ),
                  hintText: hintText,
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: tokens.colors.onSurfaceVariant,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(100),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: tokens.colors.surfaceContainer
                      .withValues(alpha: 0.5),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: Style.sm),
            AppPrimaryButton(onPressed: (enabled && !sending) ? () => onSend() : null, child: sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: AppProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.white,
                      ),
                    )
                  : const Text('发送')),
          ],
        ),
      ),
    );
  }
}
