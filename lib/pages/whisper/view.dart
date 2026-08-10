import 'package:flutter/material.dart';

import 'package:winwin/common/widgets/refresh_indicator.dart';
import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/msg.dart';
import 'package:winwin/pages/whisper/msg_feed/at_me_page.dart';
import 'package:winwin/pages/whisper/msg_feed/like_me_page.dart';
import 'package:winwin/pages/whisper/msg_feed/reply_me_page.dart';
import 'package:winwin/pages/whisper/msg_feed/sys_msg_page.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';

/// 消息页（Phase 7.7.3）。
///
/// 参照 PiliPlus 的 `WhisperPage`：顶部 4 个 CircleAvatar 入口
/// （回复/艾特/点赞/系统），下方为未读数汇总。
/// 桌面端精简：不实现完整私信会话列表（需 IM SDK），聚焦消息中心入口。
class WhisperPage extends StatefulWidget {
  const WhisperPage({super.key});

  @override
  State<WhisperPage> createState() => _WhisperPageState();
}

class _WhisperPageState extends State<WhisperPage>
    with AutomaticKeepAliveClientMixin {
  LoadingState<Map<String, dynamic>> _unreadState = LoadingState.loading();
  LoadingState<Map<String, dynamic>> _feedUnreadState = LoadingState.loading();
  bool _loading = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    setState(() {
      _unreadState = LoadingState.loading();
      _feedUnreadState = LoadingState.loading();
    });
    await ensureBootstrap();
    final results = await Future.wait([
      MsgHttp.msgUnread(),
      MsgHttp.msgFeedUnread(),
    ]);
    if (!mounted) return;
    final unreadRes = results[0];
    final feedRes = results[1];
    setState(() {
      _unreadState = unreadRes is Success<Map<String, dynamic>>
          ? unreadRes
          : unreadRes as LoadingState<Map<String, dynamic>>;
      _feedUnreadState = feedRes is Success<Map<String, dynamic>>
          ? feedRes
          : feedRes as LoadingState<Map<String, dynamic>>;
    });
    _loading = false;
  }

  int get _replyUnread =>
      (_feedUnreadState.dataOrNull?['reply'] as num?)?.toInt() ?? 0;
  int get _atUnread =>
      (_feedUnreadState.dataOrNull?['at'] as num?)?.toInt() ?? 0;
  int get _likeUnread =>
      (_feedUnreadState.dataOrNull?['like'] as num?)?.toInt() ?? 0;
  int get _sysUnread =>
      (_feedUnreadState.dataOrNull?['system'] as num?)?.toInt() ?? 0;
  int get _dmUnread =>
      (_unreadState.dataOrNull?['follow_unread'] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('消息')),
      body: AppRefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Style.safeSpace,
                  vertical: Style.md,
                ),
                child: _buildEntries(theme),
              ),
            ),
            const SliverToBoxAdapter(child: Divider(height: 1)),
            SliverList(
              delegate: SliverChildListDelegate.fixed(
                [
                  _buildSummaryTile(
                    theme,
                    icon: Icons.mail_outline,
                    title: '私信',
                    count: _dmUnread,
                    color: iosBlue,
                    onTap: () => _showTodo(context, '私信会话'),
                  ),
                  _buildSummaryTile(
                    theme,
                    icon: Icons.system_update_alt_outlined,
                    title: '系统通知',
                    count: _sysUnread,
                    color: iosTeal,
                    onTap: () {
                      _clearFeedUnread('system');
                      showSysMsgPage(context);
                    },
                  ),
                ],
              ),
            ),
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(Style.xxl),
                  child: Text(
                    '点击上方入口查看回复 / 艾特 / 点赞 / 系统消息\n私信会话列表待后续集成',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntries(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _EntryItem(
          icon: Icons.reply_rounded,
          label: '回复我的',
          count: _replyUnread,
          color: iosBlue,
          onTap: () {
            _clearFeedUnread('reply');
            showReplyMePage(context);
          },
        ),
        _EntryItem(
          icon: Icons.alternate_email_rounded,
          label: '艾特我的',
          count: _atUnread,
          color: iosOrange,
          onTap: () {
            _clearFeedUnread('at');
            showAtMePage(context);
          },
        ),
        _EntryItem(
          icon: Icons.favorite_outline,
          label: '点赞我的',
          count: _likeUnread,
          color: iosPink,
          onTap: () {
            _clearFeedUnread('like');
            showLikeMePage(context);
          },
        ),
        _EntryItem(
          icon: Icons.campaign_outlined,
          label: '系统消息',
          count: _sysUnread,
          color: iosTeal,
          onTap: () {
            _clearFeedUnread('system');
            showSysMsgPage(context);
          },
        ),
      ],
    );
  }

  /// 乐观清零某类消息流未读角标（实际未读数下次刷新恢复）。
  void _clearFeedUnread(String key) {
    final data = _feedUnreadState.dataOrNull;
    if (data != null && (data[key] as num? ?? 0) > 0) {
      setState(() => data[key] = 0);
    }
  }

  Widget _buildSummaryTile(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required int count,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(title),
      trailing: count > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: theme.colorScheme.error,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : Icon(
              Icons.keyboard_arrow_right_rounded,
              color: theme.colorScheme.outline,
            ),
      onTap: onTap,
    );
  }

  void _showTodo(BuildContext context, String title) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text('$title · 待后续集成'),
        duration: const Duration(seconds: 1),
      ),
    );
  }
}

/// 顶部圆形入口项。
class _EntryItem extends StatelessWidget {
  const _EntryItem({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              if (count > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error,
                      border: Border.all(color: theme.scaffoldBackgroundColor, width: 1.5),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}
