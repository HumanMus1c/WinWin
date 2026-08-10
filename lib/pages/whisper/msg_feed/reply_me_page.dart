import 'package:flutter/material.dart';

import 'package:winwin/http/msg.dart';
import 'package:winwin/pages/member/member_space_page.dart';
import 'package:winwin/pages/whisper/msg_feed/msg_feed_page.dart';
import 'package:winwin/theme/style.dart';

/// 「回复我的」入口。
void showReplyMePage(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const ReplyMePage()),
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
    final theme = Theme.of(context);
    final nickname = _user?['nickname']?.toString() ?? '';
    final business = _content?['business']?.toString() ?? '';
    final source = _content?['source_content']?.toString() ?? '';
    final targetReply = _content?['target_reply_content']?.toString() ?? '';
    final rootReply = _content?['root_reply_content']?.toString() ?? '';
    final counts = item['counts'];
    final isMulti = item['is_multi'] == 1;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Style.safeSpace,
        vertical: Style.xs,
      ),
      leading: GestureDetector(
        onTap: () => _goMember(context),
        child: MsgFeedAvatar(src: _user?['avatar']?.toString()),
      ),
      title: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: nickname,
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
            if (isMulti)
              TextSpan(
                text: ' 等人',
                style: theme.textTheme.labelSmall,
              ),
            TextSpan(
              text: ' 对我的$business发布了${counts ?? 0}条评论',
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (source.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(source, style: theme.textTheme.bodyMedium),
          ],
          if (targetReply.isNotEmpty)
            _quoteLine(theme, '| $targetReply'),
          if (rootReply.isNotEmpty)
            _quoteLine(theme, '| $rootReply'),
          const SizedBox(height: 4),
          Text(
            msgFeedTime(item['reply_time'] as int?),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
      onLongPress: () => _confirmDelete(context),
    );
  }

  Widget _quoteLine(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.outline, height: 1.5),
        ),
      );

  Future<void> _goMember(BuildContext context) async {
    final mid = _mid;
    if (mid == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MemberSpacePage(mid: mid)),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除该通知？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) onDelete();
  }
}
