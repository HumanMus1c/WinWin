import 'package:flutter_miuix/miuix.dart' show MiuixBasicComponent, MiuixHorizontalDivider, MiuixTextButton;
import 'package:flutter/widgets.dart';

import 'package:winwin/common/widgets/app_chip.dart';
import 'package:winwin/common/widgets/refresh_indicator.dart';
import 'package:winwin/theme/app_colors.dart';
import 'package:winwin/common/widgets/demo_mask.dart';
import 'package:winwin/core/account/account_service.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/msg.dart';
import 'package:winwin/pages/whisper/msg_feed/msg_feed_page.dart'
    show MsgFeedAvatar, MsgFeedEmptyView, MsgFeedErrorView, msgFeedTime;
import 'package:winwin/pages/whisper/session/chat_detail_page.dart';
import 'package:winwin/pages/whisper/session/message_preview_parser.dart';
import 'package:winwin/pages/whisper/session/session_account_resolver.dart';
import 'package:winwin/pages/whisper/session/session_more_menu_button.dart';
import 'package:winwin/pages/whisper/session/session_pagination_policy.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/core/shell/app_routes.dart';
import 'package:winwin/core/shell/app_dialogs.dart';
import 'package:winwin/core/shell/app_scaffold.dart';
import 'package:winwin/ui/components/app_progress.dart';
import 'package:winwin/common/widgets/app_dialog_shell.dart';

/// 私信会话列表入口（阶段 C）。
///
/// 蓝本：BiliPai `InboxScreen` + `InboxSessionPaginationPolicy`。
/// 分类 chips 切换 session_type；end_ts 游标分页（session_ts 归一化为微秒 -1）。
void showSessionListPage(BuildContext context) {
  Navigator.of(
    context,
  ).push(AppRoute<void>(builder: (_) => const SessionListPage()));
}

class _Category {
  const _Category(this.label, this.type);
  final String label;
  final int type;
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

class SessionListPage extends StatefulWidget {
  const SessionListPage({super.key});

  @override
  State<SessionListPage> createState() => _SessionListPageState();
}

class _SessionListPageState extends State<SessionListPage> {
  final List<Map<String, dynamic>> _sessions = [];

  /// 特别关注筛选模式下维护的完整合并列表（仅显示其中特别关注会话）。
  final List<Map<String, dynamic>> _mergedAll = [];
  Set<int>? _specialMids;
  int _selectedType = 4;
  int _endTs = 0; // 游标（微秒）
  bool _hasMore = true;
  bool _loading = true;
  bool _isLoadingMore = false;
  String? _error;

  bool get _isSpecialMode => _selectedType == _specialCategoryType;

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

  Future<void> _load({bool refresh = false, int dupRetry = 0}) async {
    // 项目约定：触碰网络前等待 bootstrap（幂等），防 dio 未初始化。
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
    _selectedType = type;
    _load(refresh: true);
  }

  Future<void> _toggleTop(Map<String, dynamic> session) async {
    final talkerId = session['talker_id'];
    final isPinned = (session['top_ts'] as num?)?.toInt() ?? 0;
    // op_type：0=置顶 1=取消置顶（沿用 BiliPai MessageRepository 约定）。
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
    return AppScaffold(
      body: Column(
        children: [
          // 分类 chips
          SizedBox(
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
                      selected: c.type == _selectedType,
                      onSelected: (_) => _selectCategory(c.type),
                    ),
                  ),
              ],
            ),
          ),
          const MiuixHorizontalDivider(),
          // 会话列表
          Expanded(
            child: Pref.demoMode
                ? const DemoListSkeleton(coverWidth: 44, coverHeight: 44)
                : _loading && _sessions.isEmpty
                ? const Center(
                    child: AppProgressIndicator(color: biliPink),
                  )
                : _error != null && _sessions.isEmpty
                ? MsgFeedErrorView(
                    error: _error!,
                    onRetry: () => _load(refresh: true),
                  )
                : AppRefreshIndicator(
                    displacement: 40.0,
                    strokeWidth: 2.5,
                    color: biliPink,
                    onRefresh: () => _load(refresh: true),
                    child: ListView.builder(
                        itemCount: _sessions.length + 1,
                        itemBuilder: (context, index) {
                          if (index == _sessions.length) {
                            if (_hasMore) {
                              _load();
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
                            return _sessions.isEmpty
                                ? const MsgFeedEmptyView()
                                : const SizedBox.shrink();
                          }
                          return _SessionTile(
                            session: _sessions[index],
                            onToggleTop: () => _toggleTop(_sessions[index]),
                            onToggleDnd: () => _toggleDnd(_sessions[index]),
                            onRemove: () =>
                                _removeSession(_sessions[index], index),
                          );
                        },
                      ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.onToggleTop,
    required this.onToggleDnd,
    required this.onRemove,
  });

  final Map<String, dynamic> session;
  final VoidCallback onToggleTop;
  final VoidCallback onToggleDnd;
  final VoidCallback onRemove;

  Map? get _lastMsg => session['last_msg'] as Map?;

  String get _name => SessionAccountResolver.displayName(session);

  String get _avatar => SessionAccountResolver.displayAvatar(session);

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final unread = (session['unread_count'] as num?)?.toInt() ?? 0;
    final isPinned = ((session['top_ts'] as num?)?.toInt() ?? 0) > 0;
    final isDnd = (session['is_dnd'] as num?)?.toInt() == 1;
    final isSpecial = SessionAccountResolver.isSpecialFollow(session);
    final msgType = (_lastMsg?['msg_type'] as num?)?.toInt() ?? 1;
    final content = _lastMsg?['content']?.toString();
    final ts = (_lastMsg?['timestamp'] as num?)?.toInt();

    return MiuixBasicComponent(
      insideMargin: const EdgeInsets.symmetric(
        horizontal: Style.safeSpace,
        vertical: Style.xs,
      ),
      onClick: () => showChatDetailPage(
        context,
        talkerId: (session['talker_id'] as num?)?.toInt() ?? 0,
        sessionType: (session['session_type'] as num?)?.toInt() ?? 1,
      ),
      startAction: Stack(
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
                  color: tokens.colors.error,
                  border: Border.all(
                    color: tokens.colors.background,
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  unread > 99 ? '99+' : '$unread',
                  style: const TextStyle(color: AppColors.white, fontSize: 10),
                ),
              ),
            ),
        ],
      ),
      content: [
        Row(
          children: [
            Flexible(
              child: Text(
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
        Text(
          MessagePreviewParser.parseSessionPreview(content, msgType),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tokens.text.bodySmall?.copyWith(
            color: tokens.colors.onSurfaceVariant,
          ),
        ),
      ],
      endActions: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (ts != null && ts > 0)
              Text(
                msgFeedTime(ts),
                style: tokens.text.bodySmall?.copyWith(
                  color: tokens.colors.outline,
                ),
              ),
            SessionMoreMenuButton(
              isPinned: isPinned,
              isDnd: isDnd,
              onToggleTop: onToggleTop,
              onToggleDnd: onToggleDnd,
              onRemove: () => _confirmRemove(context),
            ),
          ],
        ),
      ],
    );
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
    if (ok == true) onRemove();
  }
}
