import 'package:flutter_miuix/miuix.dart'
    show
        MiuixCard,
        MiuixCardDefaults,
        MiuixPressFeedbackType,
        MiuixPressable,
        MiuixTextButton;
import 'package:flutter/widgets.dart';

import 'package:winwin/common/widgets/app_chip.dart';
import 'package:winwin/theme/app_colors.dart';
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
import 'package:winwin/core/shell/app_dialogs.dart';
import 'package:winwin/ui/components/app_progress.dart';
import 'package:winwin/common/widgets/app_dialog_shell.dart';

/// 会话列表区（消息页内嵌）。
///
/// **仅承载列表**：顶部「分类栏」（筛选 chips）已上移到消息页的**浮动毛玻璃合并栏**
/// （[SessionFilterBar]），筛选类型经 [sessionType] 由宿主页下传；本部件不再持有
/// 筛选状态，[sessionType] 变化时自动重载。列表顶部按 [topInset] 避让合并栏。
class SessionListSection extends StatefulWidget {
  const SessionListSection({
    super.key,
    this.onRefreshUnread,
    this.sessionType = 4,
    this.topInset = 0,
  });

  final VoidCallback? onRefreshUnread;

  /// 当前筛选类型（服务端 `session_type`；[kSpecialSessionFilterType] = 特别关注）。
  final int sessionType;

  /// 滚动内容顶部避让高度（宿主页浮动合并栏的高度），使会话行不被合并栏遮住，
  /// 同时内容可从合并栏**后方穿过** → 合并栏毛玻璃可见。
  final double topInset;

  @override
  State<SessionListSection> createState() => SessionListSectionState();
}

class SessionListSectionState extends State<SessionListSection> {
  final List<Map<String, dynamic>> _sessions = [];

  /// 特别关注筛选模式下维护的完整合并列表（仅显示其中特别关注会话）。
  final List<Map<String, dynamic>> _mergedAll = [];
  Set<int>? _specialMids;
  int _endTs = 0;
  bool _hasMore = true;
  bool _loading = true;
  String? _error;
  bool _isLoadingMore = false;

  bool get _isSpecialMode =>
      widget.sessionType == kSpecialSessionFilterType;

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
  void didUpdateWidget(covariant SessionListSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 顶部「分类栏」切换筛选类型（宿主页下传）→ 重载该类型会话。
    if (oldWidget.sessionType != widget.sessionType) {
      _load(refresh: true);
    }
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
    final rowsFit = ((MediaQuery.sizeOf(context).height - 260) / 76)
        .ceil()
        .clamp(4, 20);
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
      // B7 反馈轮#2：刷新期间保留现有列表（不再清空置 _loading —— 消除与
      // Miuix 下拉指示器同屏的居中加载环）；成功路径（merged.sessions）
      // 仍整体替换列表内容。
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
      sessionType: _isSpecialMode ? 4 : widget.sessionType,
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
    // 仅会话列表；顶部「分类栏」已上移到宿主页的浮动合并栏（[SessionFilterBar]）。
    // 顶部按 [SessionListSection.topInset] 避让合并栏，使会话行不被遮住，且内容可
    // 从合并栏**后方穿过**（合并栏毛玻璃因此可见）。
    return CustomScrollView(
      controller: _scrollCtrl,
      // AlwaysScrollable：列表不满一屏时仍可下拉刷新。
      // Clamping 包裹：MiuixPullToRefresh 靠 OverscrollNotification 驱动
      // （裸 AlwaysScrollable 无边界条件、不产生过卷通知 → 下拉无响应）。
      physics: const ClampingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        // 顶部避让：宿主页浮动合并栏的高度（会话行不被遮住，且内容从其后方穿过）。
        if (widget.topInset > 0)
          SliverToBoxAdapter(child: SizedBox(height: widget.topInset)),
        // 会话列表
        if (Pref.demoMode)
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _SessionTile(
                session: const {'talker_id': 0, 'session_type': 1},
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
              child: Center(child: AppProgressIndicator(color: biliPink)),
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
                    MiuixTextButton('重试', onPressed: () => _load(refresh: true)),
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
                    child: AppProgressIndicator(
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
    );
  }
}

/// 特别关注筛选类的客户端标记（非服务端 session_type）。
const kSpecialSessionFilterType = -10;

/// 会话分类栏（筛选 chips）。
///
/// 由宿主页（消息页）的**浮动毛玻璃合并栏**承载，故本身不持有筛选状态：
/// 选中项经 [selectedType] 传入、点击经 [onSelected] 回传（状态由宿主页持有，
/// 并经 [SessionListSection.sessionType] 下传列表区）。
class SessionFilterBar extends StatelessWidget {
  const SessionFilterBar({
    super.key,
    required this.selectedType,
    required this.onSelected,
  });

  final int selectedType;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Style.sm),
        children: [
          for (final c in _categories)
            Padding(
              padding: const EdgeInsets.only(right: 6, top: 6),
              child: AppChoiceChip(
                label: Text(c.label),
                selected: c.type == selectedType,
                onSelected: (_) => onSelected(c.type),
              ),
            ),
        ],
      ),
    );
  }
}

const _categories = <_Category>[
  _Category('全部', 4),
  _Category('特别关注', kSpecialSessionFilterType),
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

    // 会话行 = **圆角长条 MiuixCard**（与会话列表外的历史/收藏列表卡片同源）。
    // 此前用无背景的 `MiuixBasicComponent`（透明行，靠 12px 内距分隔），观感是
    // 无缝列表；改为卡片后：左右 12px 出血边距 + 卡间纵向 4px 外距（视觉 8px），
    // 内容内距 12×8，squircle 圆角走库默认 [MiuixCardDefaults.cornerRadius]。
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Style.md,
        vertical: Style.xs,
      ),
      child: GestureDetector(
        onSecondaryTapUp: (details) =>
            _openMoreMenu(context, details.globalPosition),
        child: MiuixCard(
          insideMargin: const EdgeInsets.symmetric(
            horizontal: Style.md,
            vertical: Style.sm,
          ),
          child: MiuixPressable(
            onPressed: () => showChatDetailPage(
              context,
              talkerId: (session['talker_id'] as num?)?.toInt() ?? 0,
              sessionType: (session['session_type'] as num?)?.toInt() ?? 1,
            ),
            // 整卡轻下沉微缩（项目既定点击反馈），替代整卡变暗/波纹。
            feedbackType: MiuixPressFeedbackType.sink,
            sinkAmount: 0.98,
            borderRadius: BorderRadius.circular(
              MiuixCardDefaults.cornerRadius,
            ),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    MsgFeedAvatar(src: _avatar),
                    if (!Pref.demoMode && unread > 0)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 18),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
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
                            style: const TextStyle(
                              color: AppColors.white,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: Style.md),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
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
                          if (isSpecial)
                            _flag(tokens, '特别关注', color: biliPink),
                          if (isDnd) _flag(tokens, '免打扰'),
                        ],
                      ),
                      const SizedBox(height: Style.xs),
                      (Pref.demoMode
                          ? const SkeletonLine(
                              width: double.infinity,
                              height: 12,
                            )
                          : Text(
                              MessagePreviewParser.parseSessionPreview(
                                content,
                                msgType,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tokens.text.bodySmall?.copyWith(
                                color: tokens.colors.onSurfaceVariant,
                              ),
                            )),
                    ],
                  ),
                ),
                const SizedBox(width: Style.sm),
                Row(
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
                      onReport: () => reportSession(
                        context,
                        talkerId: (session['talker_id'] as num?)?.toInt() ?? 0,
                        sessionType:
                            (session['session_type'] as num?)?.toInt() ?? 1,
                      ),
                      onRemove: () => _confirmRemove(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
        onReport: () => reportSession(
          context,
          talkerId: (session['talker_id'] as num?)?.toInt() ?? 0,
          sessionType: (session['session_type'] as num?)?.toInt() ?? 1,
        ),
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
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: const Text('删除会话'),
        content: const Text('会话会从列表中移除，但不会删除聊天记录。'),
        actions: [
          MiuixTextButton('取消', onPressed: () => Navigator.pop(ctx, false)),
          MiuixTextButton('删除', onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (ok == true) onRemove(index);
  }
}
