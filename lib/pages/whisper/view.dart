import 'package:material_ui/material_ui.dart';

import 'package:winwin/common/widgets/refresh_indicator.dart';
import 'package:winwin/core/account/account_service.dart';
import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/msg.dart';
import 'package:winwin/pages/whisper/msg_feed/at_me_page.dart';
import 'package:winwin/pages/whisper/msg_feed/like_me_page.dart';
import 'package:winwin/pages/whisper/msg_feed/reply_me_page.dart';
import 'package:winwin/pages/whisper/msg_feed/sys_msg_page.dart';
import 'package:winwin/pages/whisper/session/session_list_section.dart';
import 'package:winwin/services/msg_unread_service.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/inherited_ui_style.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/theme/ui_style.dart';

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
  final GlobalKey<SessionListSectionState> _sessionListKey =
      GlobalKey<SessionListSectionState>();
  LoadingState<Map<String, dynamic>> _unreadState = LoadingState.loading();
  bool _loading = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    AccountService().addListener(_onAccountChanged);
    _load();
  }

  @override
  void dispose() {
    AccountService().removeListener(_onAccountChanged);
    super.dispose();
  }

  void _onAccountChanged() {
    if (!mounted) return;
    if (AccountService().isLogin) {
      _load();
    } else {
      setState(() {
        _unreadState = LoadingState.loading();
      });
    }
  }

  Future<void> _load() async {
    if (!AccountService().isLogin) {
      setState(() {
        _unreadState = const Success({});
      });
      return;
    }
    if (_loading) return;
    _loading = true;
    setState(() {
      _unreadState = LoadingState.loading();
    });
    await ensureBootstrap();
    final results = await Future.wait([
      MsgHttp.msgUnread(),
      MsgUnreadService().fetchUnread(),
    ]);
    if (!mounted) return;
    final unreadRes = results[0] as LoadingState<Map<String, dynamic>>;
    setState(() {
      _unreadState = unreadRes;
    });
    _loading = false;
  }

  int get _replyUnread => MsgUnreadService().reply;
  int get _atUnread => MsgUnreadService().at;
  int get _likeUnread => MsgUnreadService().like;
  int get _sysUnread => MsgUnreadService().system;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final style = InheritedUiStyle.of(context);
    final renderer = resolvePrimitiveRenderer(style);
    final theme = Theme.of(context);
    // 四类互动入口固定在顶部，仅下方会话列表可滚动。
    return Scaffold(
      appBar: AppBar(
        title: const Text('消息'),
        scrolledUnderElevation: renderer == PrimitiveRenderer.material3 ? 3 : 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Style.safeSpace,
              vertical: Style.md,
            ),
            child: _buildEntries(theme),
          ),
          if (renderer == PrimitiveRenderer.miuix)
            const Divider(height: 1)
          else
            const SizedBox(height: 4),
          Expanded(
            child: AppRefreshIndicator(
              onRefresh: () async {
                await Future.wait([
                  _load(),
                  _sessionListKey.currentState?.reload() ?? Future.value(),
                ]);
              },
              child: SessionListSection(
                key: _sessionListKey,
                onRefreshUnread: () => _clearDmUnread(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntries(ThemeData theme) {
    return ListenableBuilder(
      listenable: MsgUnreadService(),
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _EntryItem(
              icon: Icon(Icons.reply_rounded),
              label: '回复我的',
              count: _replyUnread,
              color: iosBlue,
              onTap: () {
                _clearFeedUnread('reply');
                showReplyMePage(context);
              },
            ),
            _EntryItem(
              icon: Icon(Icons.alternate_email_rounded),
              label: '艾特我的',
              count: _atUnread,
              color: iosOrange,
              onTap: () {
                _clearFeedUnread('at');
                showAtMePage(context);
              },
            ),
            _EntryItem(
              icon: Icon(Icons.favorite_outline),
              label: '点赞我的',
              count: _likeUnread,
              color: iosPink,
              onTap: () {
                _clearFeedUnread('like');
                showLikeMePage(context);
              },
            ),
            _EntryItem(
              icon: Icon(Icons.campaign_outlined),
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
      },
    );
  }

  /// 乐观清零某类消息流未读角标（实际未读数下次刷新恢复）。
  void _clearFeedUnread(String key) {
    MsgUnreadService().clearKey(key);
  }

  /// 乐观清零私信未读角标。
  void _clearDmUnread() {
    final data = _unreadState.dataOrNull;
    if (data != null && (data['follow_unread'] as num? ?? 0) > 0) {
      setState(() => data['follow_unread'] = 0);
    }
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

  final Widget icon;
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
                child: IconTheme(
                  data: IconThemeData(color: color, size: 24),
                  child: icon,
                ),
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
