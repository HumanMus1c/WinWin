import 'package:material_ui/material_ui.dart';

import 'package:winwin/theme/app_colors.dart';
import 'package:winwin/core/account/login_guard.dart';
import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/http/dyn.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/core/shell/app_dialogs.dart';
import 'package:winwin/ui/components/app_progress.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:winwin/ui/components/app_components.dart';

/// 动态转发弹窗（对标 PiliPlus RepostPanel 的精简桌面版）：
/// 展示被转发内容预览 + 转发理由输入，提交至 `/x/dynamic/feed/create/dyn`。
class DynRepostDialog extends StatefulWidget {
  const DynRepostDialog({super.key, required this.item});

  final DynItemModel item;

  /// 打开弹窗，返回是否转发成功。
  static Future<bool> show(BuildContext context, DynItemModel item) async {
    final res = await showAppDialog<bool>(
      context: context,
      builder: (_) => DynRepostDialog(item: item),
    );
    return res ?? false;
  }

  @override
  State<DynRepostDialog> createState() => _DynRepostDialogState();
}

class _DynRepostDialogState extends State<DynRepostDialog> {
  final TextEditingController _ctrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending) return;
    if (!await LoginGuard.requireLogin(context)) return;
    if (!mounted) return;

    setState(() => _sending = true);
    // 转发目标：转发动态以原动态为准，避免链式转发。
    final item = widget.item;
    final targetId =
        (item.orig?.id.isNotEmpty ?? false) ? item.orig!.id : item.id;
    final res = await DynHttp.repostDynamic(
      dynIdStr: targetId,
      text: _ctrl.text,
    );
    if (!mounted) return;
    setState(() => _sending = false);

    switch (res) {
      case Success():
        showToast(context, '转发成功', duration: const Duration(seconds: 2));
        Navigator.of(context).pop(true);
      case Error(:final errMsg):
        showToast(context, errMsg ?? '转发失败', duration: const Duration(seconds: 2));
      case Loading():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final target = widget.item.orig ?? widget.item;

    return AlertDialog(
      title: const Text(
        '转发动态',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 被转发内容预览
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Style.sm),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(Style.radiusSm),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (target.author?.name?.isNotEmpty == true)
                    Text(
                      '@${target.author!.name}',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (_previewText(target).isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _previewText(target),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.text.bodySmall?.copyWith(
                        color: cs.outline,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: Style.md),
            AppTextField(
              controller: _ctrl,
              maxLines: 3,
              minLines: 2,
              autofocus: true,
              hint: '说点什么…（可留空）',
            ),
          ],
        ),
      ),
      actions: [
        MiuixTextButton('取消', onPressed: _sending ? null : () => Navigator.of(context).pop(false)),
        AppPrimaryButton(onPressed: _sending ? null : _submit, child: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: AppProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.white,
                  ),
                )
              : const Text('转发')),
      ],
    );
  }

  String _previewText(DynItemModel item) {
    final text = item.text;
    if (text != null && text.trim().isNotEmpty) return text.trim();
    return item.archive?.title ??
        item.article?.title ??
        item.opus?.title ??
        item.pgc?.title ??
        '';
  }
}
