import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/common/widgets/sliver/video_header.dart';
import 'package:winwin/core/account/login_guard.dart';
import 'package:winwin/core/log/app_logger.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/pgc.dart';
import 'package:winwin/http/toview.dart';
import 'package:winwin/http/video.dart';
import 'package:winwin/main.dart';
import 'package:winwin/models/bangumi/bangumi_detail.dart';
import 'package:winwin/models/video/reply_item.dart';
import 'package:winwin/models/video/video_detail.dart';
import 'package:winwin/pages/bangumi/bangumi_detail_page.dart';
import 'package:winwin/pages/member/member_space_page.dart';
import 'package:winwin/pages/video/coin_dialog.dart';
import 'package:winwin/pages/video/desktop_pip.dart';
import 'package:winwin/pages/video/detail_page.dart' show kDetailNarrowBreakpoint;
import 'package:winwin/pages/video/player_controller.dart';
import 'package:winwin/pages/video/player_panel.dart';
import 'package:winwin/pages/video/send_danmaku_panel.dart';
import 'package:winwin/pages/video/video_action_row.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/utils/num_utils.dart';

/// 番剧播放页面（对标 BiliPai `BangumiPlayerScreen` 与 PiliPlus PGC 播放体系）。
///
/// 桌面宽屏采用双栏分治布局：
/// - 左栏（flex 7）：播放器面板（MDK/纹理/画质/倍速/HDR/弹幕/全屏/PiP）、弹幕发送栏、当集信息、互动按钮组；
/// - 右栏（flex 3）：选集（即时一键换集，无缝切流无需退页）、评论（当集独立评论流）、简介。
/// 窄屏自动平滑退化为单列流式布局。
class BangumiPlayerPage extends StatefulWidget {
  const BangumiPlayerPage({
    super.key,
    required this.detail,
    required this.initialEpisode,
    this.allEpisodes,
  });

  final BangumiDetail detail;
  final BangumiEpisode initialEpisode;
  final List<BangumiEpisode>? allEpisodes;

  @override
  State<BangumiPlayerPage> createState() => _BangumiPlayerPageState();
}

class _BangumiPlayerPageState extends State<BangumiPlayerPage>
    with RouteAware, WindowListener, TickerProviderStateMixin {
  late BangumiEpisode _currentEpisode;
  late List<BangumiEpisode> _episodes;
  WinWinPlayerController? playerController;

  late final TabController _wideTabCtrl;
  late final TabController _narrowTabCtrl;
  final ScrollController _scrollController = ScrollController();

  // 选集排序与状态
  bool _episodesDescending = false;

  // 评论状态（针对当集 aid/oid）
  final List<ReplyItemModel> _replies = [];
  String? _nextOffset;
  bool _replyEnd = false;
  bool _loadingReplies = false;
  bool _replyFailed = false;
  int _replyMode = 3; // 3=最热, 2=最新

  // 楼中楼回复
  final Map<int, List<ReplyItemModel>> _subReplies = {};
  final Map<int, String?> _subNextOffset = {};
  final Map<int, bool> _subEnd = {};
  final Map<int, bool> _subLoading = {};

  final TextEditingController _commentCtrl = TextEditingController();
  bool _sendingComment = false;
  int? _replyRoot;
  String? _replyHint;

  bool _fullscreen = false;
  bool _hasLike = false;
  int _coinNum = 0;
  bool _hasFav = false;
  bool _isFollowed = false;
  int _followStatus = 0; // 1=想看, 2=在看, 3=看过
  bool _descExpanded = false;
  bool? _inWatchLater;

  // 记录页面被覆盖前的状态
  bool _wasPlaying = false;
  Duration _savedPosition = Duration.zero;

  // OP/ED 自动跳过防重标记
  int? _lastOpSkippedEpId;
  int? _lastEdSkippedEpId;

  @override
  void initState() {
    super.initState();
    _currentEpisode = widget.initialEpisode;
    _episodes = widget.allEpisodes ?? widget.detail.episodes;
    _isFollowed = widget.detail.userStatus?.follow == 1;
    _followStatus = widget.detail.userStatus?.followStatus ?? (_isFollowed ? 2 : 0);
    _wideTabCtrl = TabController(length: 2, vsync: this);
    _narrowTabCtrl = TabController(length: 3, vsync: this);
    windowManager.addListener(this);

    _initPlayerForEpisode(_currentEpisode);
    _loadReplies();
    _loadEpisodeInteraction();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic>) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    windowManager.removeListener(this);
    _wideTabCtrl.dispose();
    _narrowTabCtrl.dispose();
    DesktopPipController.instance.exitPip();
    playerController?.dispose();
    _scrollController.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────── RouteAware ───────────────────────────

  @override
  void didPushNext() {
    final ctrl = playerController;
    if (ctrl != null) {
      _wasPlaying = ctrl.playing.value;
      _savedPosition = ctrl.position.value;
      unawaited(ctrl.reportCurrentProgress());
      ctrl.pause();
      ctrl.detachListeners();
    }
  }

  @override
  void didPopNext() {
    final ctrl = playerController;
    if (ctrl != null) {
      ctrl.attachListeners();
      unawaited(ctrl.load(start: _savedPosition, autoplay: _wasPlaying));
    }
  }

  // ─────────────────────────── WindowListener ───────────────────────────

  @override
  void onWindowEnterFullScreen() {
    if (mounted) setState(() => _fullscreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) setState(() => _fullscreen = false);
  }

  // ─────────────────────────── 播放器初始化与切集 ───────────────────────────

  void _initPlayerForEpisode(BangumiEpisode ep, {Duration? startPos}) {
    final bvid = ep.bvid ?? '';
    final cid = ep.cid ?? 0;
    if (cid <= 0 && bvid.isEmpty) {
      AppLogger.w('BangumiPlayer', 'Episode has invalid bvid/cid: id=${ep.id}');
      return;
    }

    final oldCtrl = playerController;
    oldCtrl?.dispose();

    final ctrl = WinWinPlayerController(
      bvid: bvid,
      cid: cid,
      epId: ep.id,
      seasonId: widget.detail.seasonId,
    );
    ctrl.aid = ep.aid;
    playerController = ctrl;

    // 监听播放进度，触发 OP/ED 自动跳过（对标 BiliPai BangumiEpisodeSkipPolicy）
    ctrl.position.addListener(_checkOpEdSkip);

    // 播放结束监听，自动播放下一集（对标 BiliPai playNextEpisode）
    ctrl.duration.addListener(_checkEpisodeEnd);

    // 并行拉取 playInfo（恢复进度与字幕）
    if (cid > 0 && bvid.isNotEmpty) {
      unawaited(_applyPlayInfo(ctrl, cid, bvid, aid: ep.aid, startPos: startPos));
    }

    ctrl.load(start: startPos);
    if (mounted) setState(() {});
  }

  Future<void> _applyPlayInfo(
    WinWinPlayerController ctrl,
    int cid,
    String bvid, {
    int? aid,
    Duration? startPos,
  }) async {
    try {
      final res = await VideoHttp.playInfo(aid: aid, bvid: bvid, cid: cid);
      if (!mounted) return;
      if (res case Success(:final response)) {
        final subtitles = response.subtitle?.subtitles ?? const [];
        if (subtitles.isNotEmpty) {
          ctrl.setSubtitleList(subtitles);
        }
        if (startPos == null && response.lastPlayTime > 0) {
          ctrl.resumeTo(Duration(milliseconds: response.lastPlayTime));
        }
      }
    } catch (_) {}
  }

  /// 切换到指定分集（即时无缝切换）
  void _switchEpisode(BangumiEpisode ep) {
    if (_currentEpisode.id == ep.id) return;
    setState(() {
      _currentEpisode = ep;
      _replies.clear();
      _nextOffset = null;
      _replyEnd = false;
      _subReplies.clear();
    });

    _initPlayerForEpisode(ep);
    _loadReplies();
    _loadEpisodeInteraction();

    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text('正在播放：${ep.displayTitle}'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  /// 检查并跳过 OP/ED
  void _checkOpEdSkip() {
    final ctrl = playerController;
    if (ctrl == null) return;
    final skip = _currentEpisode.skip;
    if (skip == null) return;

    final posMs = ctrl.position.value.inMilliseconds;
    final epId = _currentEpisode.id;

    // 片头跳过
    final op = skip.op;
    if (op != null && op.end > 0 && _lastOpSkippedEpId != epId) {
      if (posMs >= op.start * 1000 && posMs < op.end * 1000) {
        _lastOpSkippedEpId = epId;
        unawaited(ctrl.resumeTo(Duration(milliseconds: op.end * 1000)));
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('已跳过片头'),
            duration: Duration(seconds: 1),
          ),
        );
        return;
      }
    }

    // 片尾跳过
    final ed = skip.ed;
    if (ed != null && ed.start > 0 && _lastEdSkippedEpId != epId) {
      if (posMs >= ed.start * 1000) {
        _lastEdSkippedEpId = epId;
        _playNextEpisode();
      }
    }
  }

  /// 自动播放下一集
  void _playNextEpisode() {
    final all = _episodes;
    final currentIndex = all.indexWhere((e) => e.id == _currentEpisode.id);
    if (currentIndex >= 0 && currentIndex < all.length - 1) {
      final nextEp = all[currentIndex + 1];
      _switchEpisode(nextEp);
    }
  }

  void _checkEpisodeEnd() {
    final ctrl = playerController;
    if (ctrl == null) return;
    final dur = ctrl.duration.value;
    final pos = ctrl.position.value;
    if (dur.inSeconds > 0 && pos.inMilliseconds >= dur.inMilliseconds - 800) {
      _playNextEpisode();
    }
  }

  // ─────────────────────────── 社区与评论 ───────────────────────────

  Future<void> _loadEpisodeInteraction() async {
    final res = await PgcHttp.pgcLikeCoinFav(epId: _currentEpisode.id);
    if (!mounted) return;
    if (res case Success(:final response)) {
      setState(() {
        _hasLike = response['like'] == 1;
        _hasFav = response['favorite'] == 1 || _isFollowed;
        final rawCoin = response['coin_number'];
        if (rawCoin is int) {
          _coinNum = rawCoin;
        } else if (rawCoin is num) {
          _coinNum = rawCoin.toInt();
        }
      });
    }

    final statusRes = await PgcHttp.seasonStatus(widget.detail.seasonId);
    if (!mounted) return;
    if (statusRes case Success(:final response)) {
      final follow = response['follow'] == 1;
      final fStatus = (response['follow_status'] as num?)?.toInt() ?? (follow ? 2 : 0);
      setState(() {
        _isFollowed = follow;
        _followStatus = fStatus;
        if (follow) _hasFav = true;
      });
    }
  }

  Future<void> _loadReplies({bool refresh = true}) async {
    final oid = _currentEpisode.aid;
    if (oid == null || oid <= 0) return;
    if (_loadingReplies) return;
    if (!refresh && _replyEnd) return;

    _loadingReplies = true;
    if (refresh) {
      _replies.clear();
      _nextOffset = null;
      _replyEnd = false;
      _replyFailed = false;
    }

    final res = await VideoHttp.replyMain(
      oid: oid,
      mode: _replyMode,
      nextOffset: _nextOffset,
    );

    if (!mounted) return;
    if (res case Success(:final response)) {
      final newItems = response.replies;
      if (newItems.isEmpty) {
        _replyEnd = true;
      } else {
        _replies.addAll(newItems);
        _nextOffset = response.cursor?.nextOffset;
        if (response.cursor?.isEnd == true) {
          _replyEnd = true;
        }
      }
    } else {
      _replyFailed = true;
    }
    _loadingReplies = false;
    setState(() {});
  }

  void _gotoMemberSpace(int? mid) {
    if (mid == null || mid <= 0) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MemberSpacePage(mid: mid)),
    );
  }

  Future<void> _toggleLikeReply(ReplyItemModel reply) async {
    final aid = _currentEpisode.aid;
    final rpid = reply.rpid;
    if (aid == null || aid <= 0 || rpid == null) return;
    if (!await LoginGuard.requireLogin(context)) return;
    if (!mounted) return;

    final wasLiked = reply.isLiked;
    // 乐观更新
    setState(() {
      final idx = _replies.indexWhere((r) => r.rpid == rpid);
      if (idx >= 0) {
        final r = _replies[idx];
        _replies[idx] = r.copyWith(
          like: (r.like ?? 0) + (wasLiked ? -1 : 1),
          action: wasLiked ? 0 : 1,
        );
      }
    });

    final res = await VideoHttp.likeReply(
      oid: aid,
      rpid: rpid,
      action: wasLiked ? 0 : 1,
    );
    if (!mounted) return;
    if (res case Error(:final errMsg)) {
      setState(() {
        final idx = _replies.indexWhere((r) => r.rpid == rpid);
        if (idx >= 0) {
          final r = _replies[idx];
          _replies[idx] = r.copyWith(
            like: (r.like ?? 0) + (wasLiked ? 1 : -1),
            action: wasLiked ? 1 : 0,
          );
        }
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(errMsg ?? '操作失败')),
      );
    }
  }

  Future<void> _toggleLikeSubReply(ReplyItemModel sub) async {
    final aid = _currentEpisode.aid;
    final rpid = sub.rpid;
    if (aid == null || aid <= 0 || rpid == null) return;
    if (!await LoginGuard.requireLogin(context)) return;
    if (!mounted) return;

    final wasLiked = sub.isLiked;
    setState(() {
      for (final entry in _subReplies.entries) {
        final idx = entry.value.indexWhere((r) => r.rpid == rpid);
        if (idx >= 0) {
          final r = entry.value[idx];
          entry.value[idx] = r.copyWith(
            like: (r.like ?? 0) + (wasLiked ? -1 : 1),
            action: wasLiked ? 0 : 1,
          );
          break;
        }
      }
    });

    final res = await VideoHttp.likeReply(
      oid: aid,
      rpid: rpid,
      action: wasLiked ? 0 : 1,
    );
    if (!mounted) return;
    if (res case Error(:final errMsg)) {
      setState(() {
        for (final entry in _subReplies.entries) {
          final idx = entry.value.indexWhere((r) => r.rpid == rpid);
          if (idx >= 0) {
            final r = entry.value[idx];
            entry.value[idx] = r.copyWith(
              like: (r.like ?? 0) + (wasLiked ? 1 : -1),
              action: wasLiked ? 1 : 0,
            );
            break;
          }
        }
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(errMsg ?? '操作失败')),
      );
    }
  }

  Future<void> _toggleSubReplies(ReplyItemModel reply) async {
    final rpid = reply.rpid;
    if (rpid == null) return;
    if (_subReplies.containsKey(rpid)) {
      setState(() {
        _subReplies.remove(rpid);
        _subNextOffset.remove(rpid);
        _subEnd.remove(rpid);
        _subLoading.remove(rpid);
      });
      return;
    }
    setState(() {
      _subReplies[rpid] = <ReplyItemModel>[];
      _subLoading[rpid] = true;
    });
    await _loadSubReplies(reply);
  }

  Future<void> _loadSubReplies(ReplyItemModel reply) async {
    final aid = _currentEpisode.aid;
    final rpid = reply.rpid;
    if (aid == null || aid <= 0 || rpid == null) return;
    final res = await VideoHttp.replyReplyList(
      oid: aid,
      root: rpid,
      nextOffset: _subNextOffset[rpid],
    );
    if (!mounted) return;
    switch (res) {
      case Success(:final response):
        _subNextOffset[rpid] = response.cursor?.nextOffset;
        _subEnd[rpid] = response.cursor?.isEnd ?? response.replies.isEmpty;
        _subLoading[rpid] = false;
        setState(() {
          _subReplies[rpid]?.addAll(response.replies);
          if (!_subReplies.containsKey(rpid)) {
            _subReplies[rpid] = response.replies;
          }
        });
      case Error():
        _subLoading[rpid] = false;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('加载回复失败')),
        );
      case Loading():
        break;
    }
  }

  void _setReplyTarget(ReplyItemModel reply, {String? targetName}) async {
    if (!await LoginGuard.requireLogin(context)) return;
    if (!mounted) return;
    final name = targetName ?? reply.member?.uname ?? '';
    setState(() {
      _replyRoot = reply.rpid;
      _replyHint = name.isNotEmpty ? '回复 @$name' : null;
    });
    _commentCtrl.clear();
  }

  void _clearReplyTarget() {
    setState(() {
      _replyRoot = null;
      _replyHint = null;
    });
    _commentCtrl.clear();
  }

  Future<void> _sendComment() async {
    final content = _commentCtrl.text.trim();
    if (content.isEmpty) return;
    final oid = _currentEpisode.aid;
    if (oid == null || oid <= 0) return;

    if (!await LoginGuard.requireLogin(context)) return;

    setState(() => _sendingComment = true);
    final res = await VideoHttp.replyAdd(
      oid: oid,
      message: content,
      root: _replyRoot,
      parent: _replyRoot,
    );
    if (!mounted) return;
    setState(() => _sendingComment = false);

    if (res case Success()) {
      _commentCtrl.clear();
      _replyRoot = null;
      _replyHint = null;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('评论发表成功')),
      );
      _loadReplies(refresh: true);
    } else if (res case Error(:final errMsg)) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(errMsg ?? '发送失败')),
      );
    }
  }

  // ─────────────────────────── 快捷键与全屏 ───────────────────────────

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final ctrl = playerController;
    if (ctrl == null) return;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
        ctrl.togglePlay();
      case LogicalKeyboardKey.arrowLeft:
        final p = ctrl.position.value - const Duration(seconds: 5);
        ctrl.seek(p < Duration.zero ? Duration.zero : p);
      case LogicalKeyboardKey.arrowRight:
        final p = ctrl.position.value + const Duration(seconds: 5);
        final d = ctrl.duration.value;
        ctrl.seek(p > d ? d : p);
      case LogicalKeyboardKey.arrowUp:
        ctrl.setVolume((ctrl.volume.value + 5).clamp(0, 100));
      case LogicalKeyboardKey.arrowDown:
        ctrl.setVolume((ctrl.volume.value - 5).clamp(0, 100));
      case LogicalKeyboardKey.keyF:
        _toggleFullscreen();
    }
  }

  Future<void> _toggleFullscreen() async {
    final next = !_fullscreen;
    setState(() => _fullscreen = next);
    await windowManager.setFullScreen(next);
  }

  static String _formatDate(int? seconds) {
    if (seconds == null || seconds <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    String pad(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${pad(dt.month)}-${pad(dt.day)} ${pad(dt.hour)}:${pad(dt.minute)}';
  }

  // ─────────────────────────── UI 构建 ───────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_fullscreen) {
      return KeyboardListener(
        focusNode: FocusNode()..requestFocus(),
        onKeyEvent: _handleKey,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: playerController != null
              ? PlayerPanel(
                  controller: playerController!,
                  cover: _currentEpisode.cover ?? widget.detail.cover,
                  fullscreen: true,
                  onToggleFullscreen: _toggleFullscreen,
                )
              : const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      onKeyEvent: _handleKey,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            '${widget.detail.title} · ${_currentEpisode.displayTitle}',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          titleSpacing: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          actions: [
            // 跳转回详情页
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: '查看番剧详情',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BangumiDetailPage(
                      seasonId: widget.detail.seasonId,
                      detail: widget.detail,
                    ),
                  ),
                );
              },
            ),
            // 画中画
            IconButton(
              icon: const Icon(Icons.picture_in_picture_alt_outlined),
              tooltip: '画中画',
              onPressed: () => DesktopPipController.instance.enterPip(),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= kDetailNarrowBreakpoint;
            return isWide ? _buildWideLayout(cs) : _buildNarrowLayout(cs);
          },
        ),
      ),
    );
  }

  Widget _buildPlayerContent() {
    return Container(
      color: Colors.black,
      child: playerController != null
          ? PlayerPanel(
              controller: playerController!,
              cover: _currentEpisode.cover ?? widget.detail.cover,
              fullscreen: false,
              onToggleFullscreen: _toggleFullscreen,
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }

  /// 桌面宽屏双栏布局（左 7: 播放器+互动+简介，右 3: 选集/评论 Tab）
  Widget _buildWideLayout(ColorScheme cs) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左栏：播放器核心 + 视频下方交互控件与番剧简介（支持向上滚动挤压缩放）
        Expanded(
          flex: 7,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxExtent = constraints.maxWidth * 9 / 16;
              final minExtent = (maxExtent * 0.56).clamp(180.0, 240.0);
              return CustomScrollView(
                controller: _scrollController,
                slivers: [
                  VideoHeader(
                    maxExtent: maxExtent,
                    minExtent: minExtent,
                    child: _buildPlayerContent(),
                  ),
                  // 弹幕发送栏（宽度与视频一致）
                  if (playerController != null)
                    SliverToBoxAdapter(
                      child: SendDanmakuPanel(
                        controller: playerController!,
                        inline: true,
                      ),
                    ),
                  // 视频下方交互控件与简介区
                  SliverPadding(
                    padding: const EdgeInsets.all(Style.safeSpace),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _buildInfoSection(cs),
                        _buildDescSection(cs),
                        _buildTagsSection(cs),
                        const SizedBox(height: 32),
                      ]),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        // 分割线
        VerticalDivider(width: 1, thickness: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),
        // 右栏：选集 / 评论
        Expanded(
          flex: 3,
          child: Column(
            children: [
              TabBar(
                controller: _wideTabCtrl,
                tabs: [
                  Tab(text: '选集 (${_episodes.length})'),
                  Tab(text: '评论 (${_replies.length})'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _wideTabCtrl,
                  children: [
                    _buildEpisodesSidebar(cs),
                    _buildCommentsSidebar(cs),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 窄屏单列布局（视频 + 弹幕 + 选集/简介/评论 Tab，支持滚动挤压缩放）
  Widget _buildNarrowLayout(ColorScheme cs) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxExtent = constraints.maxWidth * 9 / 16;
        final minExtent = (maxExtent * 0.56).clamp(180.0, 240.0);
        return NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            VideoHeader(
              maxExtent: maxExtent,
              minExtent: minExtent,
              child: _buildPlayerContent(),
            ),
            if (playerController != null)
              SliverToBoxAdapter(
                child: SendDanmakuPanel(
                  controller: playerController!,
                  inline: true,
                ),
              ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _SliverTabBarDelegate(
                TabBar(
                  controller: _narrowTabCtrl,
                  tabs: [
                    Tab(text: '选集 (${_episodes.length})'),
                    const Tab(text: '简介与互动'),
                    Tab(text: '评论 (${_replies.length})'),
                  ],
                ),
                color: Theme.of(context).scaffoldBackgroundColor,
              ),
            ),
          ],
          body: TabBarView(
            controller: _narrowTabCtrl,
            children: [
              _buildEpisodesSidebar(cs),
              SingleChildScrollView(
                padding: const EdgeInsets.all(Style.safeSpace),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoSection(cs),
                    _buildDescSection(cs),
                    _buildTagsSection(cs),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
              _buildCommentsSidebar(cs),
            ],
          ),
        );
      },
    );
  }

  // ─────────────────────────── 选集 Sidebar ───────────────────────────

  Widget _buildEpisodesSidebar(ColorScheme cs) {
    final ordered = _episodesDescending ? _episodes.reversed.toList() : _episodes;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '选集 (${_episodes.length})',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() => _episodesDescending = !_episodesDescending);
                },
                icon: Icon(
                  _episodesDescending ? Icons.arrow_downward : Icons.arrow_upward,
                  size: 16,
                ),
                label: Text(_episodesDescending ? '倒序' : '正序'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            itemCount: ordered.length,
            itemBuilder: (context, index) {
              final ep = ordered[index];
              final isCurrent = ep.id == _currentEpisode.id;

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: isCurrent ? cs.primaryContainer.withValues(alpha: 0.5) : cs.surface,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Style.radiusSm),
                  side: BorderSide(
                    color: isCurrent ? cs.primary : cs.outlineVariant.withValues(alpha: 0.4),
                    width: isCurrent ? 1.5 : 1,
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(Style.radiusSm),
                  onTap: () => _switchEpisode(ep),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        // 16:9 封面缩略图
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: SizedBox(
                            width: 80,
                            height: 45,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                NetworkImgLayer(
                                  src: ep.cover ?? widget.detail.cover,
                                  width: 80,
                                  height: 45,
                                ),
                                if (ep.badge?.isNotEmpty == true)
                                  Positioned(
                                    right: 2,
                                    top: 2,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: ep.badge!.contains('会员') ? Colors.orange : Colors.pink,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                      child: Text(
                                        ep.badge!,
                                        style: const TextStyle(
                                          fontSize: 8,
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                if (isCurrent)
                                  Container(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    child: const Center(
                                      child: Icon(Icons.play_arrow, color: Colors.white, size: 24),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ep.displayTitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                  color: isCurrent ? cs.primary : cs.onSurface,
                                ),
                              ),
                              if (ep.duration != null && ep.duration! > 0) ...[
                                const SizedBox(height: 2),
                                Text(
                                  ep.formattedDuration,
                                  style: TextStyle(fontSize: 10.5, color: cs.outline),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ─────────────────────────── 评论 Sidebar ───────────────────────────

  // ─────────────────────────── 评论区（共享普通视频稿件样式） ───────────────────────────

  Widget _buildCommentsSidebar(ColorScheme cs) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Style.sm, Style.xs, Style.sm, 0),
          child: _buildCommentSortRow(cs),
        ),
        Expanded(child: _buildReplyListView(cs)),
        _buildCommentInputBar(cs),
      ],
    );
  }

  /// 评论排序行（对标普通视频稿件 CommentSortHeader）
  Widget _buildCommentSortRow(ColorScheme cs) {
    final theme = Theme.of(context);
    Widget sortBtn(String label, int mode) {
      final selected = _replyMode == mode;
      return TextButton(
        onPressed: () {
          if (_replyMode != mode) {
            setState(() => _replyMode = mode);
            _loadReplies(refresh: true);
          }
        },
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Row(
      children: [
        sortBtn('最热', 3),
        sortBtn('最新', 2),
        const Spacer(),
        Text(
          '共 ${_replies.length} 条',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  void _maybeLoadMoreReplies() {
    if (_loadingReplies || _replyEnd || _replyFailed) return;
    _loadReplies(refresh: false);
  }

  void _retryReplies() {
    setState(() {
      _replyFailed = false;
    });
    _loadReplies(refresh: true);
  }

  /// 评论列表（使用普通视频稿件设计）
  Widget _buildReplyListView(ColorScheme cs) {
    if (_replies.isEmpty && _loadingReplies) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        Style.cardSpace,
        Style.xs,
        Style.safeSpace,
        Style.md,
      ),
      itemCount: _replies.length + 1,
      itemBuilder: (context, index) {
        if (index == _replies.length) return _buildReplyTrailer(cs);
        if (index == _replies.length - 1) _maybeLoadMoreReplies();
        return _buildReplyTile(_replies[index]);
      },
    );
  }

  /// 普通视频稿件同款评论卡片
  Widget _buildReplyTile(ReplyItemModel reply) {
    final theme = Theme.of(context);
    final member = reply.member;
    final grayStyle = TextStyle(
      fontSize: 12,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final rpid = reply.rpid;
    final subReplies = rpid != null ? _subReplies[rpid] : null;
    final subLoading = rpid != null && (_subLoading[rpid] ?? false);
    final subEnd = rpid != null && (_subEnd[rpid] ?? false);

    return _card(
      margin: const EdgeInsets.only(top: Style.sm),
      padding: const EdgeInsets.all(Style.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 评论用户头像（点击跳转空间）
              GestureDetector(
                onTap: () => _gotoMemberSpace(reply.mid ?? member?.mid),
                child: ClipOval(
                  child: NetworkImgLayer(
                    src: member?.avatar,
                    width: 38,
                    height: 38,
                    type: 'avatar',
                  ),
                ),
              ),
              const SizedBox(width: Style.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: GestureDetector(
                            onTap: () =>
                                _gotoMemberSpace(reply.mid ?? member?.mid),
                            child: Text(
                              member?.uname ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: (member?.level != null &&
                                        member!.level! >= 6)
                                    ? biliPink
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                        if (member?.level case final lvl? when lvl > 0)
                          Container(
                            margin: const EdgeInsets.only(left: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              'LV$lvl',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurfaceVariant,
                                height: 1.1,
                              ),
                            ),
                          ),
                        const Spacer(),
                        Text(_formatDate(reply.ctime), style: grayStyle),
                      ],
                    ),
                    const SizedBox(height: Style.xs),
                    Text(
                      reply.content?.message ?? '',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 14.5,
                        height: 1.55,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: Style.sm),
                    // 操作行：点赞 + 回复 + 展开折叠
                    Row(
                      spacing: Style.lg,
                      children: [
                        GestureDetector(
                          onTap: () => _toggleLikeReply(reply),
                          child: Row(
                            spacing: 4,
                            children: [
                              Icon(
                                reply.isLiked
                                    ? Icons.thumb_up
                                    : Icons.thumb_up_outlined,
                                size: 15,
                                color: reply.isLiked
                                    ? biliPink
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                              Text(
                                NumUtils.formatNum(reply.like),
                                style: grayStyle.copyWith(
                                  fontSize: 12,
                                  color: reply.isLiked
                                      ? biliPink
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _setReplyTarget(reply),
                          child: Row(
                            spacing: 3,
                            children: [
                              Icon(
                                Icons.reply,
                                size: 15,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              Text(
                                '回复',
                                style: grayStyle.copyWith(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        if ((reply.rcount ?? 0) > 0)
                          GestureDetector(
                            onTap: () => _toggleSubReplies(reply),
                            child: Row(
                              spacing: 2,
                              children: [
                                Text(
                                  subReplies != null
                                      ? '收起 ${reply.rcount}条回复'
                                      : '展开 ${reply.rcount}条回复',
                                  style: grayStyle.copyWith(
                                    fontSize: 12,
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Icon(
                                  subReplies != null
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  size: 15,
                                  color: theme.colorScheme.primary,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          // 楼中楼回复列表（独立背景圆角容器包覆）
          if (subReplies != null && subReplies.isNotEmpty) ...[
            const SizedBox(height: Style.sm),
            Container(
              margin: const EdgeInsets.only(left: 46),
              padding: const EdgeInsets.symmetric(
                horizontal: Style.md,
                vertical: Style.sm,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(Style.radiusMd),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = 0; i < subReplies.length; i++) ...[
                    if (i > 0) ...[
                      const SizedBox(height: Style.xs),
                      Divider(
                        height: 1,
                        thickness: 0.5,
                        color: theme.colorScheme.outlineVariant
                            .withValues(alpha: 0.2),
                      ),
                      const SizedBox(height: Style.xs),
                    ],
                    _buildSubReplyTile(subReplies[i], reply),
                  ],
                  if (subLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: Style.sm),
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  if (!subEnd && !subLoading && subReplies.length >= 3)
                    Padding(
                      padding: const EdgeInsets.only(top: Style.xs),
                      child: TextButton.icon(
                        onPressed: () => _loadSubReplies(reply),
                        icon: const Icon(Icons.expand_more, size: 16),
                        label: Text(
                          '查看更多回复 ${reply.rcount != null ? "(${subReplies.length}/${reply.rcount})" : ""}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Style.sm,
                            vertical: Style.xs,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 楼中楼单条回复
  Widget _buildSubReplyTile(
    ReplyItemModel sub,
    ReplyItemModel root,
  ) {
    final theme = Theme.of(context);
    final subMember = sub.member;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第 1 行：头像 + 用户名 + 徽章 + 发布时间
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () => _gotoMemberSpace(sub.mid ?? subMember?.mid),
                child: ClipOval(
                  child: NetworkImgLayer(
                    src: subMember?.avatar,
                    width: 28,
                    height: 28,
                    type: 'avatar',
                  ),
                ),
              ),
              const SizedBox(width: Style.sm),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: GestureDetector(
                        onTap: () =>
                            _gotoMemberSpace(sub.mid ?? subMember?.mid),
                        child: Text(
                          subMember?.uname ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                    if (subMember?.level case final lvl? when lvl > 0)
                      Container(
                        margin: const EdgeInsets.only(left: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          'LV$lvl',
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.1,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                _formatDate(sub.ctime),
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          // 第 2 行：回复正文
          Padding(
            padding: const EdgeInsets.only(left: 36, top: 4, bottom: 4),
            child: Text(
              sub.content?.message ?? '',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 13.5,
                height: 1.5,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          // 第 3 行：操作栏（点赞 + 回复）
          Padding(
            padding: const EdgeInsets.only(left: 36, bottom: 2),
            child: Row(
              spacing: Style.md,
              children: [
                GestureDetector(
                  onTap: () => _toggleLikeSubReply(sub),
                  child: Row(
                    spacing: 3,
                    children: [
                      Icon(
                        sub.isLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
                        size: 13,
                        color: sub.isLiked
                            ? biliPink
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      Text(
                        NumUtils.formatNum(sub.like),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: sub.isLiked
                              ? biliPink
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => _setReplyTarget(
                    root,
                    targetName: subMember?.uname,
                  ),
                  child: Row(
                    spacing: 2,
                    children: [
                      Icon(
                        Icons.reply,
                        size: 13,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      Text(
                        '回复',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 评论列表尾部
  Widget _buildReplyTrailer(ColorScheme cs) {
    final theme = Theme.of(context);
    if (_loadingReplies) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: Style.lg),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_replyFailed) {
      return Center(
        child: TextButton(
          onPressed: _retryReplies,
          child: const Text('评论加载失败，点击重试'),
        ),
      );
    }
    if (_replies.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Style.lg),
        child: Center(
          child: Text(
            '还没有评论',
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    if (_replyEnd) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Style.lg),
        child: Center(
          child: Text(
            '没有更多评论了',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  /// 评论输入栏（普通视频稿件同款胶囊输入框与粉色发送按钮）
  Widget _buildCommentInputBar(ColorScheme cs) {
    final theme = Theme.of(context);
    final enabled = _currentEpisode.aid != null && _currentEpisode.aid! > 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        Style.safeSpace,
        Style.xs,
        Style.safeSpace,
        Style.safeSpace,
      ),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _commentCtrl,
                enabled: enabled && !_sendingComment,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: Style.lg,
                    vertical: Style.sm,
                  ),
                  hintText: enabled
                      ? (_replyHint ?? '发一条友善的评论吧~')
                      : '当前剧集暂不支持评论',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(100),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainer
                      .withValues(alpha: 0.5),
                  suffixIcon: _replyRoot != null
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: _clearReplyTarget,
                        )
                      : null,
                ),
                onSubmitted: (_) => _sendComment(),
              ),
            ),
            const SizedBox(width: Style.sm),
            FilledButton(
              onPressed: enabled && !_sendingComment ? _sendComment : null,
              style: FilledButton.styleFrom(
                backgroundColor: biliPink,
                padding: const EdgeInsets.symmetric(
                  horizontal: Style.lg,
                  vertical: Style.sm,
                ),
                minimumSize: const Size(0, 40),
              ),
              child: _sendingComment
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('发送'),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────── 交互与卡片组件 ───────────────────────────

  /// BiliPai/WinWin 风格圆角卡片容器（扁平、无阴影）
  Widget _card({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(Style.lg),
    EdgeInsetsGeometry margin = EdgeInsets.zero,
  }) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(Style.mdRadius),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: child,
    );
  }

  void _goToDetailPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BangumiDetailPage(
          seasonId: widget.detail.seasonId,
          detail: widget.detail,
        ),
      ),
    );
  }

  Future<void> _toggleFollow() async {
    if (!await LoginGuard.requireLogin(context)) return;
    if (_isFollowed) {
      _showFollowStatusDialog();
    } else {
      final res = await PgcHttp.followBangumi(seasonId: widget.detail.seasonId);
      if (!mounted) return;
      if (res case Success()) {
        setState(() {
          _isFollowed = true;
          _hasFav = true;
          _followStatus = 2;
        });
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('已追番')),
        );
      } else if (res case Error(:final errMsg)) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(errMsg ?? '追番失败')),
        );
      }
    }
  }

  String get _followStatusLabel {
    if (!_isFollowed) return '追番';
    return switch (_followStatus) {
      1 => '想看',
      2 => '在看',
      3 => '看过',
      _ => '正在追番',
    };
  }

  Widget _buildFollowButton(ColorScheme cs) {
    return GestureDetector(
      onSecondaryTap: _isFollowed ? _showFollowStatusDialog : null,
      child: FilledButton.tonal(
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        ),
        onPressed: _toggleFollow,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isFollowed ? Icons.favorite : Icons.favorite_border,
              size: 16,
              color: _isFollowed ? Colors.pink : null,
            ),
            const SizedBox(width: 4),
            Text(_followStatusLabel),
          ],
        ),
      ),
    );
  }

  /// 视频下方交互区（对标普通视频稿件 detail_page.dart 的 _buildInfoSection）
  Widget _buildInfoSection(ColorScheme cs) {
    final theme = Theme.of(context);
    final stat = widget.detail.stat;
    final grayStyle = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);
    final epStat = VideoStat(
      like: stat?.likes,
      coin: _coinNum,
      favorite: stat?.favorites,
      share: stat?.share,
    );

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 剧集标题
          Text(
            _currentEpisode.displayTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: Style.sm),
          // 数据行（播放量、弹幕、时长、开播时间）
          Row(
            children: [
              Icon(Icons.play_circle_outline, size: 15, color: cs.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(NumUtils.formatNum(stat?.views), style: grayStyle),
              const SizedBox(width: Style.md),
              Icon(Icons.subtitles_outlined, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(NumUtils.formatNum(stat?.danmakus), style: grayStyle),
              if (_currentEpisode.duration != null && _currentEpisode.duration! > 0) ...[
                const SizedBox(width: Style.md),
                Icon(Icons.schedule_outlined, size: 14, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(_currentEpisode.formattedDuration, style: grayStyle),
              ],
              if (_currentEpisode.pubTime != null || widget.detail.publish?.releaseDateShow != null) ...[
                const SizedBox(width: Style.md),
                Icon(Icons.calendar_today_outlined, size: 13, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  _currentEpisode.pubTime != null
                      ? _formatDate(_currentEpisode.pubTime)
                      : (widget.detail.publish?.releaseDateShow ?? ''),
                  style: grayStyle,
                ),
              ],
            ],
          ),
          const SizedBox(height: Style.md),
          // 番剧主体卡片行（对标普通视频 UP 主行）
          Row(
            children: [
              // 番剧海报微缩图（点击跳番剧详情页）
              GestureDetector(
                onTap: _goToDetailPage,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Style.radiusSm),
                  child: NetworkImgLayer(
                    src: widget.detail.cover,
                    width: 44,
                    height: 44,
                  ),
                ),
              ),
              const SizedBox(width: Style.md),
              // 番剧名、评分、全季追番量
              Expanded(
                child: GestureDetector(
                  onTap: _goToDetailPage,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.detail.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right, size: 16, color: cs.outline),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (widget.detail.rating != null && widget.detail.rating!.score > 0) ...[
                            const Icon(Icons.star_rounded, color: Colors.amber, size: 15),
                            const SizedBox(width: 2),
                            Text(
                              widget.detail.rating!.score.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            '${NumUtils.formatNum(stat?.favorites)} 追番',
                            style: grayStyle,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // 追番按钮
              _buildFollowButton(cs),
            ],
          ),
          const Divider(height: Style.xl),
          // 互动行（点赞/投币/收藏/点踩/分享/稍后再看 + 长按三连）
          VideoActionRow(
            stat: epStat,
            hasLike: _hasLike,
            hasDislike: false,
            coinNum: _coinNum,
            hasFav: _hasFav,
            inWatchLater: _inWatchLater,
            onLike: _actionLike,
            onTriple: _actionTriple,
            onCoin: _actionCoin,
            onDislike: () {},
            onFav: _actionFav,
            onShare: _actionShare,
            onWatchLater: _actionWatchLater,
          ),
        ],
      ),
    );
  }

  /// 番剧简介卡片（默认 3 行折叠，可展开/收起；展开后含声优与制作人员）
  Widget _buildDescSection(ColorScheme cs) {
    final desc = widget.detail.evaluate.trim();
    final hasActors = widget.detail.actors.isNotEmpty;
    final hasStaff = widget.detail.staff.isNotEmpty;
    final grayColor = cs.onSurfaceVariant;

    return _card(
      margin: const EdgeInsets.only(top: Style.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: desc.isEmpty ? null : () => setState(() => _descExpanded = !_descExpanded),
            borderRadius: BorderRadius.circular(Style.radiusSm),
            child: Text(
              desc.isEmpty ? '暂无简介' : desc,
              maxLines: _descExpanded ? null : 3,
              overflow: _descExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: grayColor,
              ),
            ),
          ),
          if (desc.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => _descExpanded = !_descExpanded),
                child: Text(_descExpanded ? '收起' : '展开'),
              ),
            ),
          // 展开状态下展示声优和制作人员
          if (_descExpanded && (hasActors || hasStaff)) ...[
            const Divider(height: Style.lg),
            if (hasActors) ...[
              const Text('声优 / 演员', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              SelectableText(
                widget.detail.actors,
                style: TextStyle(fontSize: 12, color: grayColor, height: 1.4),
              ),
              const SizedBox(height: Style.sm),
            ],
            if (hasStaff) ...[
              const Text('制作人员', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              SelectableText(
                widget.detail.staff,
                style: TextStyle(fontSize: 12, color: grayColor, height: 1.4),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// 风格标签行
  Widget _buildTagsSection(ColorScheme cs) {
    if (widget.detail.styles.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Style.md),
      child: Wrap(
        spacing: Style.sm,
        runSpacing: Style.sm,
        children: widget.detail.styles.map((tag) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(Style.radiusLg),
            ),
            child: Text(
              tag,
              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _actionLike() async {
    if (!await LoginGuard.requireLogin(context)) return;
    final aid = _currentEpisode.aid;
    if (aid != null && aid > 0) {
      final next = !_hasLike;
      final res = await VideoHttp.likeVideo(aid: aid, type: next);
      if (res case Success()) {
        setState(() => _hasLike = next);
      }
    }
  }

  Future<void> _actionCoin() async {
    if (!await LoginGuard.requireLogin(context)) return;
    final aid = _currentEpisode.aid;
    if (aid != null && aid > 0) {
      if (!mounted) return;
      await showCoinDialog(
        context,
        onPay: (count, withLike) async {
          final res = await VideoHttp.coinVideo(
            aid: aid,
            multiply: count,
            selectLike: withLike ? 1 : 0,
          );
          if (res case Success()) {
            setState(() {
              _coinNum += count;
              if (withLike) _hasLike = true;
            });
          }
        },
      );
    }
  }

  Future<void> _actionTriple() async {
    if (!await LoginGuard.requireLogin(context)) return;
    final res = await PgcHttp.pgcTriple(epId: _currentEpisode.id);
    if (!mounted) return;
    if (res case Success()) {
      setState(() {
        _hasLike = true;
        _coinNum = 2;
        _hasFav = true;
        _isFollowed = true;
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('一键三连成功！')),
      );
    }
  }

  Future<void> _actionFav() async {
    if (!await LoginGuard.requireLogin(context)) return;
    _showFollowStatusDialog();
  }

  void _actionShare() {
    final epId = _currentEpisode.id;
    final url = 'https://www.bilibili.com/bangumi/play/ep$epId';
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('播放链接已复制到剪贴板')),
    );
  }

  Future<void> _actionWatchLater() async {
    if (!await LoginGuard.requireLogin(context)) return;
    final aid = _currentEpisode.aid;
    if (aid == null || aid <= 0) return;
    final inList = _inWatchLater ?? false;
    final res = inList
        ? await ToviewHttp.delToview(aid.toString())
        : await ToviewHttp.addToview(aid: aid);
    if (!mounted) return;
    if (res case Success()) {
      setState(() => _inWatchLater = !inList);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(!inList ? '已添加到稍后再看' : '已从稍后再看移除')),
      );
    } else if (res case Error(:final errMsg)) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(errMsg ?? '操作失败')),
      );
    }
  }

  void _showFollowStatusDialog() {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('追番状态设置'),
        children: [
          SimpleDialogOption(
            onPressed: () async {
              Navigator.pop(ctx);
              await PgcHttp.updateFollowStatus(seasonId: widget.detail.seasonId, status: 1);
              if (mounted) {
                setState(() {
                  _isFollowed = true;
                  _followStatus = 1;
                  _hasFav = true;
                });
              }
            },
            child: const Text('想看'),
          ),
          SimpleDialogOption(
            onPressed: () async {
              Navigator.pop(ctx);
              await PgcHttp.updateFollowStatus(seasonId: widget.detail.seasonId, status: 2);
              if (mounted) {
                setState(() {
                  _isFollowed = true;
                  _followStatus = 2;
                  _hasFav = true;
                });
              }
            },
            child: const Text('在看'),
          ),
          SimpleDialogOption(
            onPressed: () async {
              Navigator.pop(ctx);
              await PgcHttp.updateFollowStatus(seasonId: widget.detail.seasonId, status: 3);
              if (mounted) {
                setState(() {
                  _isFollowed = true;
                  _followStatus = 3;
                  _hasFav = true;
                });
              }
            },
            child: const Text('看过'),
          ),
          const Divider(),
          SimpleDialogOption(
            onPressed: () async {
              Navigator.pop(ctx);
              await PgcHttp.unfollowBangumi(seasonId: widget.detail.seasonId);
              if (mounted) {
                setState(() {
                  _isFollowed = false;
                  _followStatus = 0;
                  _hasFav = false;
                });
              }
            },
            child: const Text('取消追番', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color color;

  _SliverTabBarDelegate(this.tabBar, {required this.color});

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(
      color: color,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return tabBar != oldDelegate.tabBar || color != oldDelegate.color;
  }
}

