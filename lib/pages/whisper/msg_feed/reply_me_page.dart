import 'package:flutter_miuix/miuix.dart' show MiuixBasicComponent, MiuixTextButton;
import 'package:flutter/widgets.dart';

import 'package:winwin/http/msg.dart';
import 'package:winwin/pages/member/member_space_page.dart';
import 'package:winwin/pages/whisper/msg_feed/msg_feed_page.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/core/shell/app_routes.dart';
import 'package:winwin/core/shell/app_dialogs.dart';
import 'package:winwin/common/widgets/app_dialog_shell.dart';

/// 「回复我的」入口。
void showReplyMePage(BuildContext context) {
  Navigator.of(context).push(
    AppRoute<void>(builder: (_) => const ReplyMePage()),
  );
}

class ReplyMePage extends StatelessWidget {
  const ReplyMePage({super.key});

  @override
  Widget build(BuildContext context) {
    return MsgFeedPage(
      title: '回复我的',
      loader: MsgHttp.msgFeedReplyMe,
      delType: 1,
      extractItems: (d) => (d['items'] as List?)
          ?.map((e) => (e as Map).cast<String, dynamic>())
          .toList() ??
          const [],
      extractCursor: (d) => (d['cursor'] as Map?)?.cast<String, dynamic>(),
      tileBuilder: (item, onDelete) => _ReplyTile(item: item, onDelete: onDelete),
    );
  }
}

class _ReplyTile extends StatelessWidget {
  const _ReplyTile({required this.item, required this.onDelete});

  final Map<String, dynamic> item;
  final VoidCallback onDelete;

  Map? get _user => item['user'] as Map?;
  Map? get _content => item['item'] as Map?;
  int? get _mid => _user?['mid'] as int?;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final nickname = _user?['nickname']?.toString() ?? '';
    final business = _content?['business']?.toString() ?? '';
    final source = _content?['source_content']?.toString() ?? '';
    final targetReply = _content?['target_reply_content']?.toString() ?? '';
    final rootReply = _content?['root_reply_content']?.toString() ?? '';
    final counts = item['counts'];
    final isMulti = item['is_multi'] == 1;

    return GestureDetector(
      onLongPress: () => _confirmDelete(context),
      child: MiuixBasicComponent(
        insideMargin: const EdgeInsets.symmetric(
          horizontal: Style.safeSpace,
          vertical: Style.xs,
        ),
        startAction: GestureDetector(
          onTap: () => _goMember(context),
          child: MsgFeedAvatar(src: _user?['avatar']?.toString()),
        ),
        content: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: nickname,
                  style: tokens.text.titleSmall
                      ?.copyWith(color: tokens.colors.primary),
                ),
                if (isMulti)
                  TextSpan(
                    text: ' 等人',
                    style: tokens.text.labelSmall,
                  ),
                TextSpan(
                  text: ' 对我的$business发布了${counts ?? 0}条评论',
                  style: tokens.text.titleSmall
                      ?.copyWith(color: tokens.colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (source.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(source, style: tokens.text.bodyMedium),
          ],
          if (targetReply.isNotEmpty)
            _quoteLine(tokens, '| $targetReply'),
          if (rootReply.isNotEmpty)
            _quoteLine(tokens, '| $rootReply'),
          const SizedBox(height: 4),
          Text(
            msgFeedTime(item['reply_time'] as int?),
            style: tokens.text.bodySmall
                ?.copyWith(color: tokens.colors.outline),
          ),
        ],
      ),
    );
  }

  Widget _quoteLine(AppTokens tokens, String text) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tokens.text.labelSmall
              ?.copyWith(color: tokens.colors.outline, height: 1.5),
        ),
      );

  Future<void> _goMember(BuildContext context) async {
    final mid = _mid;
    if (mid == null) return;
    await Navigator.of(context).push(
      AppRoute(builder: (_) => MemberSpacePage(mid: mid)),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: const Text('删除该通知？'),
        actions: [
          MiuixTextButton('取消', onPressed: () => Navigator.pop(ctx, false)),
          MiuixTextButton('删除', onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (ok == true) onDelete();
  }
}
