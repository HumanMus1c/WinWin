import 'package:material_ui/material_ui.dart';

import 'package:winwin/http/msg.dart';
import 'package:winwin/pages/member/member_space_page.dart';
import 'package:winwin/pages/whisper/msg_feed/msg_feed_page.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/core/shell/app_routes.dart';
import 'package:winwin/core/shell/app_dialogs.dart';

/// 「艾特我的」入口。
void showAtMePage(BuildContext context) {
  Navigator.of(context).push(
    AppRoute<void>(builder: (_) => const AtMePage()),
  );
}

class AtMePage extends StatelessWidget {
  const AtMePage({super.key});

  @override
  Widget build(BuildContext context) {
    return MsgFeedPage(
      title: '艾特我的',
      loader: MsgHttp.msgFeedAtMe,
      delType: 2,
      extractItems: (d) => (d['items'] as List?)
          ?.map((e) => (e as Map).cast<String, dynamic>())
          .toList() ??
          const [],
      extractCursor: (d) => (d['cursor'] as Map?)?.cast<String, dynamic>(),
      tileBuilder: (item, onDelete) => _AtTile(item: item, onDelete: onDelete),
    );
  }
}

class _AtTile extends StatelessWidget {
  const _AtTile({required this.item, required this.onDelete});

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
              style: tokens.text.titleSmall
                  ?.copyWith(color: tokens.colors.primary),
            ),
            TextSpan(
              text: ' 在$business中@了我',
              style: tokens.text.titleSmall
                  ?.copyWith(color: tokens.colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
      subtitle: source.isNotEmpty
          ? Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                source,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: tokens.text.bodyMedium,
              ),
            )
          : null,
      onLongPress: () => _confirmDelete(context),
    );
  }

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
