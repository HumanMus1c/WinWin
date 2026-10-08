import 'package:material_ui/material_ui.dart';

import 'package:winwin/common/skeleton/skeleton.dart';
import 'package:winwin/common/widgets/miuix_context_menu.dart';
import 'package:winwin/core/account/account_service.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/msg.dart';
import 'package:winwin/pages/whisper/msg_feed/msg_feed_page.dart'
    show MsgFeedAvatar, MsgFeedEmptyView, msgFeedTime;
import 'package:winwin/pages/whisper/session/chat_detail_page.dart';
import 'package:winwin/pages/whisper/session/message_preview_parser.dart';
import 'package:winwin/pages/whisper/session/session_account_resolver.dart';
import 'package:winwin/pages/whisper/session/session_more_menu_button.dart';
import 'package:winwin/pages/whisper/session/session_pagination_policy.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/core/shell/app_theme_host.dart';

/// 可内嵌的会话列表区（用于消息页直接展示）。
///
/// 筛选 chips 固定在顶部，仅会话列表内部滚动。
class SessionListSection extends StatefulWidget {
  const SessionListSection({super.key, this.onRefreshUnread});

  final VoidCallback? onRefreshUnread;

  @override
  State<SessionListSection> createState() => SessionListSectionState();
}

class SessionListSectionState extends State<SessionListSection> {
  final List<Map<String, dynamic>> _sessions = [];

  /// 特别关注筛选模式下维护的完整合并列表（仅显示其中特别关注会话）。
  final List<Map<String, dynamic>> _mergedAll = [];
  Set<int>? _specialMids;
  int _selectedType = 4;
  int _endTs = 0;
  bool _hasMore = true;
  bool _loading = true;
  String? _error;
  bool _isLoadingMore = false;

  bool get _isSpecialMode => _selectedType == _specialCategoryType;

  /// 演示模式：本地追加的会话行数（滚动每次仅 +1 行）。
  int _demoExtra = 0;

  /// 演示模式：上次追加行的滚动位置（需继续滚动约半屏后才再追加）。
  double _demoLastAppendAt = double.negativeInfinity;

  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    AccountService().addListener(_onAccountChanged);
    Pref.demoModeNotifier.addListener(_onDemoChanged);
    _scrollCtrl.addListener(_onDemoScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onDemoScroll);
    _scrollCtrl.dispose();
    Pref.demoModeNotifier.removeListener(_onDemoChanged);
    AccountService().removeListener(_onAccountChanged);
    super.dispose();
  }

  void _onDemoChanged() {
    if (!mounted) return;
    setState(() {});
    if (!Pref.demoMode && _sessions.isEmpty) {
      _load(refresh: true);
    }
  }

  /// 演示模式滚动追加：到达底部且再滚动约半屏后，追加"一行"（一个会话项）。
  void _onDemoScroll() {
    if (!Pref.demoMode) return;
    if (!_scrollCtrl.hasClients || !_scrollCtrl.position.hasContentDimensions) {
      return;
    }
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 80 &&
        pos.pixels > _demoLastAppendAt + pos.viewportDimension * 0.5) {
      _demoLastAppendAt = pos.pixels;
      setState(() => _demoExtra += 1);
    }
  }

  /// 演示模式：初始仅填充当前视口所需的会话行数（+ 滚动追加数）。
  int _demoVisibleRows(BuildContext context) {
    final rowsFit =
        ((MediaQuery.sizeOf(context).height - 260) / 76).ceil().clamp(4, 20);
    return rowsFit + _demoExtra;
  }

  void _onAccountChanged() {
    if (!mounted) return;
    if (AccountService().isLogin) {
      _load(refresh: true);
    } else {
      setState(() {
        _sessions.clear();
        _mergedAll.clear();
        _specialMids = null;
        _endTs = 0;
        _hasMore = true;
        _loading = false;
        _isLoadingMore = false;
        _error = null;
      });
    }
  }

  Future<void> reload() => _load(refresh: true);

  Future<void> _load({bool refresh = false, int dupRetry = 0}) async {
    // 演示模式：不拉取云端会话（滚动追加在 _onDemoScroll 中本地处理）。
    if (Pref.demoMode) {
      _loading = false;
      return;
    }
    // 启动时本页可能先于 bootstrap 完成前构建（main 不阻塞 runApp），
    // 须先等 Dio 初始化，否则 Request.dio LateInitializationError 导致白屏。
    await ensureBootstrap();
    if (!AccountService().isLogin) {
      setState(() {
        _loading = false;
        _isLoadingMore = false;
        _sessions.clear();
        _mergedAll.clear();
        _error = null;
      });
      return;
    }
    if (refresh) {
      _endTs = 0;
      _hasMore = true;
      _sessions.clear();
      _mergedAll.clear();
      setState(() => _loading = true);
    }
    if (!_hasMore || _isLoadingMore) return;
    _isLoadingMore = true;
    final requestedEndTs = _endTs;
    // 特别关注筛选依赖分组 mid 全集，先拉取（进程内缓存）。
    if (_isSpecialMode && _specialMids == null) {
      _specialMids = await SessionAccountResolver.fetchSpecialMids() ?? {};
      if (!mounted) {
        _isLoadingMore = false;
        return;
      }
    }
    final res = await MsgHttp.sessionList(
      sessionType: _isSpecialMode ? 4 : _selectedType,
      // size 对齐 BiliPai 取 100：置顶会话会在每页重复返回，
      // 页容量太小会导致整页去重后提前终止翻页、会话大量缺失。
      size: 100,
      endTs: requestedEndTs > 0 ? requestedEndTs : null,
    );
    _isLoadingMore = false;
    if (!mounted) return;
    switch (res) {
      case Success(:final response):
        final incoming =
            (response['session_list'] as List?)
                ?.map((e) => (e as Map).cast<String, dynamic>())
                .toList() ??
            const [];
        // mergePage：置顶优先排序 + 按会话键去重 + 严格递减游标。
        final merged = SessionPaginationPolicy.mergePage(
          existing: refresh ? const [] : _mergedAll,
          incoming: incoming,
          responseHasMore: response['has_more'] == 1,
          requestedEndTs: requestedEndTs,
          canRetryDuplicatePage: dupRetry < 3,
        );
        setState(() {
          _loading = false;
          _error = null;
          _mergedAll
            ..clear()
            ..addAll(merged.sessions);
          _sessions
            ..clear()
            ..addAll(
              _isSpecialMode
                  ? _mergedAll.where(_isSpecialSession)
                  : merged.sessions,
            );
          _hasMore = merged.hasMore;
          _endTs = merged.nextEndTs;
        });
        // 整页重复时用更早的游标自动重试（对齐 BiliPai 分页策略）。
        if (merged.shouldRetry) {
          _load(dupRetry: dupRetry + 1);
          return;
        }
        // 加载成功后通知父组件清零私信未读角标
        if (refresh && merged.newCount > 0) {
          widget.onRefreshUnread?.call();
        }
        // 异步补全会话用户信息（get_sessions 通常不带 account_info）
        final filled = await SessionAccountResolver.fillSessionAccounts(
          merged.sessions,
        );
        final specialUpdated = await SessionAccountResolver.fillSpecialFollows(
          merged.sessions,
        );
        if (mounted && (filled || specialUpdated)) setState(() {});
      case Error(:final errMsg):
        setState(() {
          _loading = false;
          _error = errMsg ?? '加载失败';
        });
      case Loading():
        break;
    }
  }

  bool _isSpecialSession(Map<String, dynamic> s) {
    final talkerId = (s['talker_id'] as num?)?.toInt() ?? 0;
    return talkerId > 0 && (_specialMids?.contains(talkerId) ?? false);
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
      showToast(context, '已删除会话', duration: const Duration(seconds: 1));
    } else {
      _toast(res);
    }
  }

  void _toast(LoadingState res) {
    final msg = res is Error ? (res.errMsg ?? '操作失败') : '操作失败';
    showToast(context, msg);
  }

  static int _nowMicros() => DateTime.now().microsecondsSinceEpoch;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    // 筛选 chips 固定在顶部，仅会话列表区域可滚动。
    return Column(
      children: [
        SizedBox(
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
        const Divider(height: 1),
        Expanded(
          child: Material(
            // ListTile 的 hover 高亮绘制在最近的 Material 祖先上，若为页面
            // Scaffold 则不受滚动裁剪，滚动时会“残留”到固定栏区域；
            // 在视口内提供独立的透明 Material 并硬裁剪即可限定绘制范围。
            type: MaterialType.transparency,
            clipBehavior: Clip.hardEdge,
            child: CustomScrollView(
              controller: _scrollCtrl,
              // AlwaysScrollable：列表不满一屏时仍可下拉刷新。
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // 会话列表
                if (Pref.demoMode)
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _SessionTile(
                        session: const {
                          'talker_id': 0,
                          'session_type': 1,
                        },
                        index: index,
                        onToggleTop: _handleToggleTop,
                        onToggleDnd: _handleToggleDnd,
                        onRemove: _handleRemove,
                      ),
                      childCount: _demoVisibleRows(context),
                    ),
                  )
                else if (_loading && _sessions.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(Style.xxl),
                      child: Center(
                        child: CircularProgressIndicator(color: biliPink),
                      ),
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
                            Text(
                              _error!,
                              style: TextStyle(color: tokens.colors.error),
                            ),
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
                    delegate: SliverChildBuilderDelegate((context, index) {
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
                    }, childCount: _sessions.length + (_hasMore ? 1 : 0)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 特别关注筛选类的客户端标记（非服务端 session_type）。
const _specialCategoryType = -10;

const _categories = <_Category>[
  _Category('全部', 4),
  _Category('特别关注', _specialCategoryType),
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

  Map? get _lastMsg => session['last_msg'] as Map?;

  String get _name => SessionAccountResolver.displayName(session);

  String get _avatar => SessionAccountResolver.displayAvatar(session);

  bool get _isPinned => ((session['top_ts'] as num?)?.toInt() ?? 0) > 0;

  bool get _isDnd => (session['is_dnd'] as num?)?.toInt() == 1;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final unread = (session['unread_count'] as num?)?.toInt() ?? 0;
    final isPinned = _isPinned;
    final isDnd = _isDnd;
    final isSpecial = SessionAccountResolver.isSpecialFollow(session);
    final msgType = (_lastMsg?['msg_type'] as num?)?.toInt() ?? 1;
    final content = _lastMsg?['content']?.toString();
    final ts = (_lastMsg?['timestamp'] as num?)?.toInt();

    return GestureDetector(
      onSecondaryTapUp: (details) =>
          _openMoreMenu(context, details.globalPosition),
      child: ListTile(
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
            if (!Pref.demoMode && unread > 0)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: tokens.colors.error,
                    border: Border.all(
                      color: tokens.colors.background,
                      width: 1.5,
                    ),
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
              child: Pref.demoMode
                  ? const SkeletonLine(width: 120, height: 14)
                  : Text(
                      _name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.text.bodyLarge,
                    ),
            ),
            if (isPinned) _flag(tokens, '置顶'),
            if (isSpecial) _flag(tokens, '特别关注', color: biliPink),
            if (isDnd) _flag(tokens, '免打扰'),
          ],
        ),
        subtitle: Pref.demoMode
            ? const SkeletonLine(width: double.infinity, height: 12)
            : Text(
                MessagePreviewParser.parseSessionPreview(content, msgType),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens.text.bodySmall?.copyWith(
                  color: tokens.colors.onSurfaceVariant,
                ),
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!Pref.demoMode && ts != null && ts > 0)
              Text(
                msgFeedTime(ts),
                style: tokens.text.bodySmall?.copyWith(
                  color: tokens.colors.outline,
                ),
              ),
            SessionMoreMenuButton(
              isPinned: isPinned,
              isDnd: isDnd,
              onToggleTop: () => onToggleTop(index),
              onToggleDnd: () => onToggleDnd(index),
              onRemove: () => _confirmRemove(context),
            ),
          ],
        ),
      ),
    );
  }

  /// 右键弹出与三点按钮一致的「更多选项」菜单（删除走二次确认）。
  Future<void> _openMoreMenu(BuildContext context, Offset position) async {
    final selected = await showMiuixContextMenu(
      context: context,
      position: position,
      actions: buildSessionMenuActions(
        context: context,
        isPinned: _isPinned,
        isDnd: _isDnd,
        onToggleTop: () => onToggleTop(index),
        onToggleDnd: () => onToggleDnd(index),
        onRemove: () => _confirmRemove(context),
      ),
      title: '更多选项',
    );
    selected?.call();
  }

  Widget _flag(AppTokens tokens, String text, {Color? color}) {
    final c = color ?? tokens.colors.primary;
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(text, style: TextStyle(fontSize: 10, color: c)),
    );
  }

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
