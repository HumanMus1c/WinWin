import 'package:material_ui/material_ui.dart';

import 'package:winwin/http/msg.dart';
import 'package:winwin/pages/whisper/msg_feed/like_detail_page.dart';
import 'package:winwin/pages/whisper/msg_feed/msg_feed_page.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/core/shell/app_routes.dart';
import 'package:winwin/core/shell/app_dialogs.dart';

/// 「点赞我的」入口。
void showLikeMePage(BuildContext context) {
  Navigator.of(context).push(
    AppRoute<void>(builder: (_) => const LikeMePage()),
  );
}

class LikeMePage extends StatelessWidget {
  const LikeMePage({super.key});

  @override
  Widget build(BuildContext context) {
    return MsgFeedPage(
      title: '点赞我的',
      loader: MsgHttp.msgFeedLikeMe,
      delType: 0,
      extractItems: (d) {
        final total = d['total'] as Map?;
        final items = total?['items'] as List?;
        return items
                ?.map((e) => (e as Map).cast<String, dynamic>())
                .toList() ??
            const [];
      },
      extractCursor: (d) {
        final total = d['total'] as Map?;
        return (total?['cursor'] as Map?)?.cast<String, dynamic>();
      },
      tileBuilder: (item, onDelete) => _LikeTile(item: item, onDelete: onDelete),
    );
  }
}

class _LikeTile extends StatelessWidget {
  const _LikeTile({required this.item, required this.onDelete});

  final Map<String, dynamic> item;
  final VoidCallback onDelete;

  List get _users => (item['users'] as List?) ?? const [];
  Map? get _content => item['item'] as Map?;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final users = _users;
    final first = users.isNotEmpty ? users.first as Map : null;
    final nickname = first?['nickname']?.toString() ?? '';
    final counts = (item['counts'] as num?)?.toInt() ?? 0;
    final title = _content?['title']?.toString() ?? '';
    final isMulti = users.length > 1;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Style.safeSpace,
        vertical: Style.xs,
      ),
      leading: MsgFeedAvatar(src: first?['avatar']?.toString()),
      title: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: nickname,
              style: tokens.text.titleSmall
                  ?.copyWith(color: tokens.colors.primary),
            ),
            if (isMulti)
              TextSpan(
                text: ' 等${users.length}人',
                style: tokens.text.labelSmall,
              ),
            TextSpan(
              text: ' 赞了我的动态',
              style: tokens.text.titleSmall
                  ?.copyWith(color: tokens.colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: tokens.text.bodyMedium,
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '共 $counts 个赞 · ${msgFeedTime(item['like_time'] as int?)}',
            style: tokens.text.bodySmall
                ?.copyWith(color: tokens.colors.outline),
          ),
        ],
      ),
      onTap: () => showLikeDetailPage(
        context,
        cardId: item['id']?.toString() ?? '',
        counts: counts,
      ),
      onLongPress: () => _confirmDelete(context),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showAppDialog<bool>(
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
