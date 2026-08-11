import 'package:flutter/material.dart';

import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/msg.dart';
import 'package:winwin/pages/whisper/msg_feed/msg_feed_page.dart'
    show MsgFeedAvatar, MsgFeedEmptyView, msgFeedTime;
import 'package:winwin/pages/whisper/session/chat_detail_page.dart';
import 'package:winwin/pages/whisper/session/message_preview_parser.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';

/// 可内嵌的会话列表 Sliver（用于消息页直接展示）。
class SessionListSliver extends StatefulWidget {
  const SessionListSliver({super.key, this.onRefreshUnread});

  final VoidCallback? onRefreshUnread;

  @override
  State<SessionListSliver> createState() => _SessionListSliverState();
}

class _SessionListSliverState extends State<SessionListSliver> {
  final List<Map<String, dynamic>> _sessions = [];
  int _selectedType = 4;
  int _endTs = 0;
  bool _hasMore = true;
  bool _loading = true;
  String? _error;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    if (refresh) {
      _endTs = 0;
      _hasMore = true;
      _sessions.clear();
      setState(() => _loading = true);
    }
    if (!_hasMore || _isLoadingMore) return;
    _isLoadingMore = true;
    final res = await MsgHttp.sessionList(
      sessionType: _selectedType,
      endTs: _endTs > 0 ? _endTs : null,
    );
    _isLoadingMore = false;
    if (!mounted) return;
    switch (res) {
      case Success(:final response):
        final list = (response['session_list'] as List?)
                ?.map((e) => (e as Map).cast<String, dynamic>())
                .toList() ??
            const [];
        final nextEndTs = _resolveNextEndTs(list);
        setState(() {
          _loading = false;
          _error = null;
          _sessions.addAll(list);
          _hasMore = (response['has_more'] == 1) && nextEndTs > 0;
          _endTs = nextEndTs;
        });
        // 加载成功后通知父组件清零私信未读角标
        if (refresh && list.isNotEmpty) {
          widget.onRefreshUnread?.call();
        }
      case Error(:final errMsg):
        setState(() {
          _loading = false;
          _error = errMsg ?? '加载失败';
        });
      case Loading():
        break;
    }
  }

  int _resolveNextEndTs(List<Map<String, dynamic>> sessions) {
    if (sessions.isEmpty) return 0;
    final last = sessions.last;
    final raw = (last['session_ts'] as num?)?.toInt() ?? 0;
    return _normalizeSessionTs(raw) > 0 ? _normalizeSessionTs(raw) - 1 : 0;
  }

  static int _normalizeSessionTs(int ts) {
    if (ts <= 0) return 0;
    if (ts >= 1000000000000000) return ts;
    if (ts >= 1000000000000) return ts * 1000;
    return ts * 1000000;
  }

  void _selectCategory(int type) {
    if (type == _selectedType) return;
    setState(() {
      _selectedType = type;
      _load(refresh: true);
    });
  }

  // 回调处理方法 - 避免闭包创建
  void _handleToggleTop(int index) => _toggleTop(_sessions[index]);
  void _handleToggleDnd(int index) => _toggleDnd(_sessions[index]);
  void _handleRemove(int index) => _removeSession(_sessions[index], index);

  Future<void> _toggleTop(Map<String, dynamic> session) async {
    final talkerId = session['talker_id'];
    final isPinned = (session['top_ts'] as num?)?.toInt() ?? 0;
    final res = await MsgHttp.setTop(
      talkerId: talkerId,
      opType: isPinned > 0 ? 1 : 0,
    );
    if (!mounted) return;
    if (res.isSuccess) {
      setState(() {
        session['top_ts'] = isPinned > 0 ? 0 : _nowMicros();
      });
      _load(refresh: true);
    } else {
      _toast(res);
    }
  }

  Future<void> _toggleDnd(Map<String, dynamic> session) async {
    final talkerId = session['talker_id'];
    final isDnd = (session['is_dnd'] as num?)?.toInt() ?? 0;
    final res = await MsgHttp.setMsgDnd(
      uid: Accounts.main.mid,
      setting: isDnd == 1 ? 0 : 1,
      dndUid: talkerId,
    );
    if (!mounted) return;
    if (res.isSuccess) {
      setState(() => session['is_dnd'] = isDnd == 1 ? 0 : 1);
    } else {
      _toast(res);
    }
  }

  Future<void> _removeSession(Map<String, dynamic> session, int index) async {
    final res = await MsgHttp.removeMsg(session['talker_id']);
    if (!mounted) return;
    if (res.isSuccess) {
      setState(() => _sessions.removeAt(index));
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('已删除会话'), duration: Duration(seconds: 1)),
      );
    } else {
      _toast(res);
    }
  }

  void _toast(LoadingState res) {
    final msg = res is Error ? (res.errMsg ?? '操作失败') : '操作失败';
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(msg)));
  }

  static int _nowMicros() => DateTime.now().microsecondsSinceEpoch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SliverMainAxisGroup(
      slivers: [
        // 分类 chips
        SliverToBoxAdapter(
          child: SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Style.sm),
              children: [
                for (final c in _categories)
                  Padding(
                    padding: const EdgeInsets.only(right: 6, top: 6),
                    child: ChoiceChip(
                      label: Text(c.label),
                      selected: c.type == _selectedType,
                      onSelected: (_) => _selectCategory(c.type),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: Divider(height: 1)),
        // 会话列表
        if (_loading && _sessions.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(Style.xxl),
              child: Center(child: CircularProgressIndicator(color: biliPink)),
            ),
          )
        else if (_error != null && _sessions.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(Style.xxl),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                    const SizedBox(height: Style.sm),
                    TextButton(
                      onPressed: () => _load(refresh: true),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          )
        else if (_sessions.isEmpty && !_hasMore)
          const SliverToBoxAdapter(child: MsgFeedEmptyView())
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index == _sessions.length) {
                  // 加载更多指示器 - 使用 addPostFrameCallback 避免在 build 中调用 _load
                  if (_hasMore && !_isLoadingMore) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && _hasMore && !_isLoadingMore) {
                        _load();
                      }
                    });
                  }
                  return const Padding(
                    padding: EdgeInsets.all(Style.md),
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: biliPink,
                      ),
                    ),
                  );
                }
                return _SessionTile(
                  session: _sessions[index],
                  index: index,
                  onToggleTop: _handleToggleTop,
                  onToggleDnd: _handleToggleDnd,
                  onRemove: _handleRemove,
                );
              },
              childCount: _sessions.length + (_hasMore ? 1 : 0),
            ),
          ),
      ],
    );
  }
}

const _categories = <_Category>[
  _Category('全部', 4),
  _Category('关注', 9),
  _Category('未关注', 2),
  _Category('陌生人', 8),
  _Category('粉丝团', 3),
  _Category('拦截', 5),
  _Category('系统', 7),
];

class _Category {
  const _Category(this.label, this.type);
  final String label;
  final int type;
}

/// 会话列表项。
class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.index,
    required this.onToggleTop,
    required this.onToggleDnd,
    required this.onRemove,
  });

  final Map<String, dynamic> session;
  final int index;
  final void Function(int) onToggleTop;
  final void Function(int) onToggleDnd;
  final void Function(int) onRemove;

  Map? get _account => session['account_info'] as Map?;
  Map? get _lastMsg => session['last_msg'] as Map?;

  String get _name {
    final n = _account?['name']?.toString();
    if (n != null && n.isNotEmpty) return n;
    return session['group_name']?.toString() ?? '未知会话';
  }

  String get _avatar {
    final a = _account?['pic_url']?.toString();
    if (a != null && a.isNotEmpty) return a;
    final f = _account?['face']?.toString();
    if (f != null && f.isNotEmpty) return f;
    return session['group_cover']?.toString() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = (session['unread_count'] as num?)?.toInt() ?? 0;
    final isPinned = ((session['top_ts'] as num?)?.toInt() ?? 0) > 0;
    final isDnd = (session['is_dnd'] as num?)?.toInt() == 1;
    final msgType = (_lastMsg?['msg_type'] as num?)?.toInt() ?? 1;
    final content = _lastMsg?['content']?.toString();
    final ts = (_lastMsg?['timestamp'] as num?)?.toInt();

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Style.safeSpace,
        vertical: Style.xs,
      ),
      onTap: () => showChatDetailPage(
        context,
        talkerId: (session['talker_id'] as num?)?.toInt() ?? 0,
        sessionType: (session['session_type'] as num?)?.toInt() ?? 1,
        title: _name,
      ),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          MsgFeedAvatar(src: _avatar),
          if (unread > 0)
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
                  unread > 99 ? '99+' : '$unread',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
        ],
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              _name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge,
            ),
          ),
          if (isPinned) _flag(theme, '置顶'),
          if (isDnd) _flag(theme, '免打扰'),
        ],
      ),
      subtitle: Text(
        MessagePreviewParser.parseSessionPreview(content, msgType),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ts != null && ts > 0)
            Text(
              msgFeedTime(ts),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert,
                size: 20, color: theme.colorScheme.outline),
            onSelected: (v) {
              switch (v) {
                case 'top':
                  onToggleTop(index);
                case 'dnd':
                  onToggleDnd(index);
                case 'remove':
                  _confirmRemove(context);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'top',
                child: Text(isPinned ? '取消置顶' : '置顶'),
              ),
              PopupMenuItem(
                value: 'dnd',
                child: Text(isDnd ? '关闭免打扰' : '开启免打扰'),
              ),
              const PopupMenuItem(value: 'remove', child: Text('删除会话')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _flag(ThemeData theme, String text) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 10,
            color: theme.colorScheme.primary,
          ),
        ),
      );

  Future<void> _confirmRemove(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除会话'),
        content: const Text('会话会从列表中移除，但不会删除聊天记录。'),
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
    if (ok == true) onRemove(index);
  }
}
