import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'package:winwin/common/widgets/image/network_img_layer.dart';
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
import 'package:winwin/pages/video/coin_dialog.dart';
import 'package:winwin/pages/video/desktop_pip.dart';
import 'package:winwin/pages/video/detail_page.dart' show kDetailNarrowBreakpoint;
import 'package:winwin/pages/video/player_controller.dart';
import 'package:winwin/pages/video/player_panel.dart';
import 'package:winwin/pages/video/send_danmaku_panel.dart';
import 'package:winwin/pages/video/video_action_row.dart';
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

  Future<void> _loadSubReplies(int rootRpid) async {
    final oid = _currentEpisode.aid;
    if (oid == null || oid <= 0) return;
    if (_subLoading[rootRpid] == true) return;
    _subLoading[rootRpid] = true;
    setState(() {});

    final res = await VideoHttp.replyReplyList(
      oid: oid,
      root: rootRpid,
      nextOffset: _subNextOffset[rootRpid],
    );

    if (!mounted) return;
    if (res case Success(:final response)) {
      final list = response.replies;
      final current = _subReplies[rootRpid] ?? [];
      current.addAll(list);
      _subReplies[rootRpid] = current;
      _subNextOffset[rootRpid] = response.cursor?.nextOffset;
      if (response.cursor?.isEnd == true || list.isEmpty) {
        _subEnd[rootRpid] = true;
      }
    }
    _subLoading[rootRpid] = false;
    setState(() {});
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

  /// 桌面宽屏双栏布局（左 7: 播放器+互动+简介，右 3: 选集/评论 Tab）
  Widget _buildWideLayout(ColorScheme cs) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左栏：播放器核心 + 视频下方交互控件与番剧简介
        Expanded(
          flex: 7,
          child: Column(
            children: [
              // 播放器视口
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  color: Colors.black,
                  child: playerController != null
                      ? PlayerPanel(
                          controller: playerController!,
                          cover: _currentEpisode.cover ?? widget.detail.cover,
                          fullscreen: false,
                          onToggleFullscreen: _toggleFullscreen,
                        )
                      : const Center(child: CircularProgressIndicator()),
                ),
              ),
              // 弹幕发送栏（宽度与视频一致）
              if (playerController != null)
                SendDanmakuPanel(controller: playerController!, inline: true),
              // 视频下方交互控件与简介区
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
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
              ),
            ],
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

  /// 窄屏单列布局（视频 + 弹幕 + 选集/简介/评论 Tab）
  Widget _buildNarrowLayout(ColorScheme cs) {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            color: Colors.black,
            child: playerController != null
                ? PlayerPanel(
                    controller: playerController!,
                    cover: _currentEpisode.cover ?? widget.detail.cover,
                    fullscreen: false,
                    onToggleFullscreen: _toggleFullscreen,
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
        ),
        if (playerController != null)
          SendDanmakuPanel(controller: playerController!, inline: true),
        TabBar(
          controller: _narrowTabCtrl,
          tabs: [
            Tab(text: '选集 (${_episodes.length})'),
            const Tab(text: '简介与互动'),
            Tab(text: '评论 (${_replies.length})'),
          ],
        ),
        Expanded(
          child: TabBarView(
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
        ),
      ],
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

  Widget _buildCommentsSidebar(ColorScheme cs) {
    return Column(
      children: [
        // 排序栏
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '全部回复 (${_replies.length})',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  _buildSortBtn('最热', 3, cs),
                  const SizedBox(width: 8),
                  _buildSortBtn('最新', 2, cs),
                ],
              ),
            ],
          ),
        ),
        // 评论列表
        Expanded(
          child: _replies.isEmpty && _loadingReplies
              ? const Center(child: CircularProgressIndicator())
              : _replies.isEmpty
                  ? Center(
                      child: Text(
                        _replyFailed ? '加载评论失败' : '暂无评论',
                        style: TextStyle(color: cs.outline),
                      ),
                    )
                  : NotificationListener<ScrollNotification>(
                      onNotification: (n) {
                        if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200) {
                          _loadReplies(refresh: false);
                        }
                        return false;
                      },
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _replies.length + 1,
                        itemBuilder: (context, i) {
                          if (i == _replies.length) {
                            return Padding(
                              padding: const EdgeInsets.all(12),
                              child: Center(
                                child: Text(
                                  _replyEnd ? '没有更多评论了' : '加载中...',
                                  style: TextStyle(fontSize: 11, color: cs.outline),
                                ),
                              ),
                            );
                          }
                          final r = _replies[i];
                          return _buildCommentItem(r, cs);
                        },
                      ),
                    ),
        ),
        // 评论输入栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
            border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3))),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentCtrl,
                  style: const TextStyle(fontSize: 12.5),
                  decoration: InputDecoration(
                    hintText: _replyHint ?? '发一条友善的评论...',
                    hintStyle: TextStyle(fontSize: 12, color: cs.outline),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: cs.outlineVariant),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _sendingComment ? null : _sendComment,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                child: _sendingComment
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('发送', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSortBtn(String label, int mode, ColorScheme cs) {
    final active = _replyMode == mode;
    return InkWell(
      onTap: () {
        if (_replyMode != mode) {
          setState(() => _replyMode = mode);
          _loadReplies(refresh: true);
        }
      },
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: active ? FontWeight.bold : FontWeight.normal,
          color: active ? cs.primary : cs.outline,
        ),
      ),
    );
  }

  Widget _buildCommentItem(ReplyItemModel r, ColorScheme cs) {
    final member = r.member;
    final rpid = r.rpid ?? 0;
    final subs = _subReplies[rpid];
    final subCount = r.rcount ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipOval(
            child: NetworkImgLayer(
              src: member?.avatar,
              width: 32,
              height: 32,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      member?.uname ?? '',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: member?.level != null && member!.level! >= 6
                            ? Colors.pink
                            : cs.onSurface,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _formatDate(r.ctime),
                      style: TextStyle(fontSize: 10, color: cs.outline),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                SelectableText(
                  r.content?.message ?? '',
                  style: const TextStyle(fontSize: 12.5, height: 1.4),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    InkWell(
                      onTap: () {
                        setState(() {
                          _replyRoot = rpid;
                          _replyHint = '回复 @${member?.uname}:';
                        });
                      },
                      child: Text('回复', style: TextStyle(fontSize: 11, color: cs.primary)),
                    ),
                    const SizedBox(width: 16),
                    Text('👍 ${NumUtils.formatNum(r.like)}', style: TextStyle(fontSize: 11, color: cs.outline)),
                  ],
                ),
                // 楼中楼
                if (subCount > 0 && subs == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: InkWell(
                      onTap: () => _loadSubReplies(rpid),
                      child: Text(
                        '查看 $subCount 条回复 >',
                        style: TextStyle(fontSize: 11, color: cs.primary),
                      ),
                    ),
                  ),
                if (subs != null && subs.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...subs.map((sub) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: RichText(
                                text: TextSpan(
                                  style: TextStyle(fontSize: 11.5, color: cs.onSurface, height: 1.3),
                                  children: [
                                    TextSpan(
                                      text: '${sub.member?.uname}: ',
                                      style: TextStyle(fontWeight: FontWeight.w600, color: cs.primary),
                                    ),
                                    TextSpan(text: sub.content?.message ?? ''),
                                  ],
                                ),
                              ),
                            )),
                        if (_subEnd[rpid] != true)
                          InkWell(
                            onTap: () => _loadSubReplies(rpid),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                _subLoading[rpid] == true ? '加载中...' : '加载更多回复...',
                                style: TextStyle(fontSize: 11, color: cs.primary),
                              ),
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
