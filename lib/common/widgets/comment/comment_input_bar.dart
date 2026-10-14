import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

import 'package:winwin/theme/app_colors.dart';
import 'package:winwin/common/widgets/comment/emote_picker.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/ui/components/app_progress.dart';
import 'package:winwin/ui/components/app_components.dart';

/// 全站统一底部输入条（评论 / 直播互动 / 番剧 / 弹幕内联 / 专栏 / 动态 / 私信共用）。
///
/// 统一口径的承载：官方表情按钮（可关） + 胶囊输入框（可带后缀/多行/格式化器）
/// + 可插拔的附加控件 + 紧凑发送按钮。容器样式：surface 底 + 顶部 0.5 描边
/// + SafeArea 底适配 + [Style.xs] 上下留白；各页只需传入各自的 controller /
/// 回调 / 文案即可，禁止再各自拼装容器。
class CommentInputBar extends StatelessWidget {
  const CommentInputBar({
    super.key,
    required this.controller,
    this.focusNode,
    required this.sending,
    required this.onSend,
    this.hintText = '发一条友善的评论吧~',
    this.enabled = true,
    this.onPressed,
    this.suffix,
    this.showClear = false,
    this.requireText = false,
    this.showEmote = true,
    this.sendLabel = '发送',
    this.inputFormatters,
    this.textStyle,
    this.onChanged,
    this.minLines = 1,
    this.maxLines = 1,
    this.fillColor,
    this.trailing,
    this.sendButton,
  });

  /// 输入控制器。
  final TextEditingController controller;

  /// 输入焦点（同时传给表情面板按钮，插入后恢复焦点）。
  final FocusNode? focusNode;

  /// 是否正在发送（true 时按钮转圈且不可重复提交）。
  final bool sending;

  /// 发送回调。
  final VoidCallback onSend;

  /// 占位提示文案。
  final String hintText;

  /// 是否可用（同时控制输入框、表情按钮与发送按钮）。
  final bool enabled;

  /// 点击输入框时的前置动作（如登录态校验）。
  final VoidCallback? onPressed;

  /// 输入框右侧自定义后缀（如「取消回复」按钮）。
  final Widget? suffix;

  /// 是否内置「文本非空即显示」的一键清空按钮。
  final bool showClear;

  /// 发送按钮是否要求文本非空才可用（直播弹幕等场景）。
  final bool requireText;

  /// 是否展示左侧官方表情按钮。
  final bool showEmote;

  /// 发送按钮文案。
  final String sendLabel;

  /// 字段输入格式化器（如长度限制）。
  final List<TextInputFormatter>? inputFormatters;

  /// 字段文本样式。
  final TextStyle? textStyle;

  /// 字段文本变化回调。
  final ValueChanged<String>? onChanged;

  /// 字段最小/最大行数（聊天多行输入用）。
  final int minLines;
  final int maxLines;

  /// 字段填充色（为空则走 AppCapsuleTextField 自身口径）。
  final Color? fillColor;

  /// 输入框与发送按钮之间的附加控件（如弹幕样式设置钮）。
  final Widget? trailing;

  /// 发送按钮整体覆盖（如需图标式发送键）；为空则用标准文本发送键。
  final Widget? sendButton;

  Widget? _buildSuffix() {
    final parts = <Widget>[];
    if (suffix != null) parts.add(suffix!);
    if (showClear) {
      parts.add(
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => value.text.isEmpty
              ? const SizedBox.shrink()
              : MiuixIconButton(
                  minWidth: 24,
                  minHeight: 24,
                  onPressed: () => controller.clear(),
                  child: AppIcon(AppIcons.clear(), size: 16),
                ),
        ),
      );
    }
    if (parts.isEmpty) return null;
    if (parts.length == 1) return parts.first;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final part in parts) ...[part, const SizedBox(width: Style.xs)],
      ],
    );
  }

  Widget _buildSendButton() {
    Widget buttonFor(bool hasText) {
      final canSend = enabled && !sending && (!requireText || hasText);
      return AppPrimaryButton(
        onPressed: canSend ? onSend : null,
        minWidth: 56,
        minHeight: 34,
        insideMargin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        cornerRadius: 10,
        child: sending
            ? const SizedBox(
                width: 16,
                height: 16,
                child: AppProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.white,
                ),
              )
            : Text(sendLabel),
      );
    }

    if (!requireText) return buttonFor(true);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => buttonFor(value.text.trim().isNotEmpty),
    );
  }

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
            if (showEmote) ...[
              // 官方表情面板按钮（输入框左侧）
              OfficialEmotePickerButton(
                controller: controller,
                focusNode: focusNode,
                enabled: enabled,
              ),
              const SizedBox(width: Style.sm),
            ],
            Expanded(
              child: AppCapsuleTextField(
                controller: controller,
                focusNode: focusNode,
                enabled: enabled,
                onPressed: onPressed,
                hint: hintText,
                suffix: _buildSuffix(),
                onSubmitted: (_) => onSend(),
                inputFormatters: inputFormatters,
                textStyle: textStyle,
                onChanged: onChanged,
                minLines: minLines,
                maxLines: maxLines,
                fillColor: fillColor,
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: Style.sm),
              trailing!,
            ],
            const SizedBox(width: Style.sm),
            sendButton ?? _buildSendButton(),
          ],
        ),
      ),
    );
  }
}
