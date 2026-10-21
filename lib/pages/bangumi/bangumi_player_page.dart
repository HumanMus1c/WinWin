import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter_miuix/miuix.dart' show MiuixHorizontalDivider, MiuixIconButton, MiuixPressFeedbackType, MiuixPressable, MiuixVerticalDivider, MiuixTextButton, MiuixButton;
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'package:winwin/common/widgets/app_dialog_shell.dart';
import 'package:winwin/ui/components/app_selectable_text.dart';
import 'package:winwin/ui/components/app_tab_view.dart';
import 'package:winwin/theme/app_colors.dart';
import 'package:winwin/common/widgets/comment/comment_input_bar.dart';
import 'package:winwin/common/widgets/comment/reply_content_view.dart';
import 'package:winwin/common/skeleton/skeleton.dart';
import 'package:winwin/common/widgets/demo_mask.dart';
import 'package:winwin/common/widgets/demo_player_chrome.dart';
import 'package:winwin/common/widgets/miuix_frosted_surface.dart';
import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/common/widgets/sliver/video_header.dart';
import 'package:winwin/core/account/login_guard.dart';
import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/core/input/app_escape_scope.dart';
import 'package:winwin/core/input/escape_layer_registry.dart';
import 'package:winwin/core/log/app_logger.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/pgc.dart';
import 'package:winwin/http/reply.dart';
import 'package:winwin/http/toview.dart';
import 'package:winwin/http/video.dart';
import 'package:winwin/core/shell/global_back_button.dart';
import 'package:winwin/main.dart';
import 'package:winwin/models/bangumi/bangumi_detail.dart';
import 'package:winwin/models/video/reply_item.dart';
import 'package:winwin/models/video/video_detail.dart';
import 'package:winwin/pages/bangumi/bangumi_detail_page.dart';
import 'package:winwin/pages/member/member_space_page.dart';
import 'package:winwin/pages/video/coin_dialog.dart';
import 'package:winwin/core/window/desktop_fullscreen.dart';
import 'package:winwin/pages/video/desktop_pip.dart';
import 'package:winwin/pages/video/detail_page.dart' show kDetailNarrowBreakpoint;
import 'package:winwin/pages/video/player_controller.dart';
import 'package:winwin/pages/video/player_panel.dart';
import 'package:winwin/pages/video/send_danmaku_panel.dart';
import 'package:winwin/pages/video/video_action_row.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/contrast_policy.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/glass_contrast_widgets.dart';
import 'package:winwin/utils/num_utils.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/core/shell/app_routes.dart';
import 'package:winwin/core/shell/app_dialogs.dart';
import 'package:winwin/core/shell/app_scaffold.dart';
import 'package:winwin/ui/components/app_progress.dart';
import 'package:winwin/ui/components/app_tooltip.dart';

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
    with RouteAware, WindowListener {
  late BangumiEpisode _currentEpisode;
  late List<BangumiEpisode> _episodes;
  WinWinPlayerController? playerController;

  late final AppTabController _wideTabCtrl;
  late final AppTabController _narrowTabCtrl;
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _scrollRatio = ValueNotifier<double>(0.0);
  bool _autoPausedByCollapse = false;

  // 选集排序与状态
  late bool _episodesDescending;

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
  final FocusNode _commentFocus = FocusNode();
  bool _sendingComment = false;
  int? _replyRoot;
  String? _replyHint;

  bool _fullscreen = false;
  bool _inAppFullscreen = false;
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

  final FocusNode _keyboardFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _keyboardFocusNode.requestFocus();
    _currentEpisode = widget.initialEpisode;
    _episodes = widget.allEpisodes ?? widget.detail.episodes;
    _isFollowed = widget.detail.userStatus?.follow == 1;
    _followStatus = widget.detail.userStatus?.followStatus ?? (_isFollowed ? 2 : 0);
    _episodesDescending = Pref.bangumiEpisodesDescending.value;
    Pref.bangumiEpisodesDescending.addListener(_onGlobalOrderChanged);
    _wideTabCtrl = AppTabController(length: 2);
    _narrowTabCtrl = AppTabController(length: 3);
    windowManager.addListener(this);
    // 演示模式切换时重建（播放器隔离/灰占位即时生效）。
    Pref.demoModeNotifier.addListener(_onDemoChanged);

    _initPlayerForEpisode(_currentEpisode);
    _loadReplies();
    _loadEpisodeInteraction();
  }

  void _onGlobalOrderChanged() {
    if (!mounted) return;
    final newDesc = Pref.bangumiEpisodesDescending.value;
    if (_episodesDescending == newDesc) return;
    setState(() {
      _episodesDescending = newDesc;
    });
  }

  void _onDemoChanged() {
    if (!mounted) return;
    if (Pref.demoMode) {
      // 进入演示：暂停播放（与正常模式数据隔离）。
      playerController?.pause();
    } else if (playerController == null) {
      // 退出演示：恢复播放器初始化。
      _initPlayerForEpisode(_currentEpisode);
    }
    setState(() {});
  }

  /// 播放器折叠自动暂停（对标 BiliPai PlayerCollapseAutoPausePolicy 与 DetailPage）。
  void _handleCollapseAutoPause(double r) {
    if (_fullscreen || _inAppFullscreen) return;
    if (Pref.demoMode) return;
    final ctrl = playerController;
    if (ctrl == null || !Pref.collapseAutoPause) return;
    if (r >= 0.98) {
      if (ctrl.playing.value) {
        ctrl.pause();
        _autoPausedByCollapse = true;
      }
    } else if (r < 0.5 && _autoPausedByCollapse) {
      ctrl.play();
      _autoPausedByCollapse = false;
    }
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
    Pref.demoModeNotifier.removeListener(_onDemoChanged);
    Pref.bangumiEpisodesDescending.removeListener(_onGlobalOrderChanged);
    _scrollRatio.dispose();
    routeObserver.unsubscribe(this);
    windowManager.removeListener(this);
    _wideTabCtrl.dispose();
    _narrowTabCtrl.dispose();
    DesktopPipController.instance.exitPip();
    if (_fullscreen) {
      DesktopFullscreen.exit();
    }
    playerController?.dispose();
    _scrollController.dispose();
    _commentCtrl.dispose();
    _commentFocus.dispose();
    _keyboardFocusNode.dispose();
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
      if (!ctrl.ready.value) {
        unawaited(ctrl.load(start: _savedPosition, autoplay: _wasPlaying));
      } else if (_wasPlaying && !ctrl.completed.value) {
        ctrl.play();
      }
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
    // 演示模式：不创建播放器、不拉流（与正常模式完全隔离）。
    if (Pref.demoMode) return;
    final bvid = ep.bvid ?? '';
    final cid = ep.cid ?? 0;
    if (cid <= 0 && bvid.isEmpty) {
      AppLogger.w('BangumiPlayer', 'Episode has invalid bvid/cid: id=${ep.id}');
      return;
    }

    final oldCtrl = playerController;
    if (oldCtrl != null) {
      unawaited(oldCtrl.reportCurrentProgress());
      oldCtrl.dispose();
    }

    final ctrl = WinWinPlayerController(
      bvid: bvid,
      cid: cid,
      epId: ep.id,
      seasonId: widget.detail.seasonId,
      seasonType: widget.detail.seasonType,
    );
    ctrl.aid = ep.aid;
    playerController = ctrl;

    // 监听播放进度，触发 OP/ED 自动跳过（对标 BiliPai BangumiEpisodeSkipPolicy）
    ctrl.position.addListener(_checkOpEdSkip);

    // 播放结束监听，自动播放下一集（对标 BiliPai playbackEndListener → playNextEpisode）
    ctrl.completed.addListener(_checkEpisodeCompleted);

    // 并行拉取 playInfo（恢复进度与字幕）
    if (cid > 0 && bvid.isNotEmpty) {
      unawaited(_applyPlayInfo(ctrl, cid, bvid, aid: ep.aid, startPos: startPos));
    }

    // startPos 未知时挂「启动闸门」：续播点（playInfo）返回前不起播，
    // 杜绝先闪 0 位画面/声音（2026-09-29）；已知起点直载无需闸门。
    ctrl.load(start: startPos, gateForResume: startPos == null);
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
        } else {
          // 无续播点 / 已知起点直载：放闸起播（非闸门场景为 no-op）。
          ctrl.releaseStartupGate(reason: 'no-history');
        }
      } else {
        ctrl.releaseStartupGate(reason: 'info-error');
      }
    } catch (_) {
      ctrl.releaseStartupGate(reason: 'info-exception');
    }
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

    showToast(
      context,
      '正在播放：${ep.displayTitle}',
      duration: const Duration(seconds: 1),
    );
  }

  /// 检查并跳过 OP/ED（对标 BiliPai `resolveBangumiEpisodeSkipAction`）。
  ///
  /// 命中判定为「位置落在区间内」（`start <= pos < end`，区间结束点按播放器时长
  /// 收敛），跳跃目标是**区间结束点**：跳过的是片头/片尾本身，其后的内容继续
  /// 播放——下一集改由自然播完（[WinWinPlayerController.completed]）驱动。
  void _checkOpEdSkip() {
    final ctrl = playerController;
    if (ctrl == null) return;
    final skip = _currentEpisode.skip;
    if (skip == null) return;

    final posMs = ctrl.position.value.inMilliseconds;
    final durMs = ctrl.duration.value.inMilliseconds;
    final epId = _currentEpisode.id;

    // 片头跳过
    final op = skip.op;
    if (op != null && _lastOpSkippedEpId != epId) {
      final opEndMs = _clampSkipEndMs(op.end * 1000, durMs);
      if (opEndMs > op.start * 1000 &&
          posMs >= op.start * 1000 &&
          posMs < opEndMs) {
        _lastOpSkippedEpId = epId;
        unawaited(ctrl.resumeTo(Duration(milliseconds: opEndMs)));
        showToast(context, '已跳过片头', duration: const Duration(seconds: 1));
        return;
      }
    }

    // 片尾跳过：只跳到片尾结束点，片尾之后的内容（彩蛋/预告等）继续播放。
    // 历史缺陷（2026-09-26 定因）：此处曾写成「命中 ed.start 即切下一集」，
    // 把 ed.end 之后的整段内容一并吞掉（实证：凡人修仙传 193 集 ed={1084,1172}s
    // 而总长 1711s，跳到下一集使 1172~1711s 共 539s 内容被跳过）。
    final ed = skip.ed;
    if (ed != null && _lastEdSkippedEpId != epId) {
      final edEndMs = _clampSkipEndMs(ed.end * 1000, durMs);
      if (edEndMs > ed.start * 1000 &&
          posMs >= ed.start * 1000 &&
          posMs < edEndMs) {
        _lastEdSkippedEpId = epId;
        unawaited(ctrl.resumeTo(Duration(milliseconds: edEndMs)));
        showToast(context, '已跳过片尾', duration: const Duration(seconds: 1));
      }
    }
  }

  /// 跳过区间结束点：按播放器时长收敛（对标 BiliPai `end.coerceAtMost(durationMs)`）。
  static int _clampSkipEndMs(int endMs, int durationMs) =>
      durationMs > 0 && endMs > durationMs ? durationMs : endMs;

  /// 自动播放下一集
  void _playNextEpisode() {
    final all = _episodes;
    final currentIndex = all.indexWhere((e) => e.id == _currentEpisode.id);
    if (currentIndex >= 0 && currentIndex < all.length - 1) {
      final nextEp = all[currentIndex + 1];
      _switchEpisode(nextEp);
    }
  }

  /// 自然播完 → 自动播放下一集（对标 BiliPai playbackEndListener）。
  ///
  /// 历史缺陷（2026-09-26 定因）：此前挂在 `ctrl.duration` 上判断
  /// `pos >= dur - 800`，而 duration 只在媒体 buffered 时赋值一次（ValueNotifier
  /// 同值不再通知），回调实际仅加载时执行一次，自然播完从不触发换集。
  void _checkEpisodeCompleted() {
    final ctrl = playerController;
    if (ctrl == null || !ctrl.completed.value) return;
    _playNextEpisode();
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
    if (mounted) setState(() {});

    try {
      final res = await VideoHttp.replyMain(
        oid: oid,
        mode: _replyMode,
        nextOffset: _nextOffset,
      );

      if (!mounted) return;
      if (res case Success(:final response)) {
        final newItems = response.replies;
        _nextOffset = response.cursor?.nextOffset;
        if (newItems.isEmpty ||
            response.cursor?.isEnd == true ||
            (_nextOffset == null || _nextOffset!.isEmpty)) {
          _replyEnd = true;
        }
        if (newItems.isNotEmpty) {
          _replies.addAll(newItems);
        }
      } else {
        _replyFailed = true;
      }
    } catch (e) {
      AppLogger.w('BangumiPlayer', '_loadReplies error: $e');
      _replyFailed = true;
    } finally {
      _loadingReplies = false;
      if (mounted) setState(() {});
    }
  }

  void _gotoMemberSpace(int? mid) {
    if (mid == null || mid <= 0) return;
    Navigator.push(
      context,
      AppRoute(builder: (_) => MemberSpacePage(mid: mid)),
    );
  }

  void _updateReplyInState(
    int rpid,
    ReplyItemModel Function(ReplyItemModel) updater,
  ) {
    setState(() {
      final idx = _replies.indexWhere((r) => r.rpid == rpid);
      if (idx >= 0) {
        _replies[idx] = updater(_replies[idx]);
      }
      for (final entry in _subReplies.entries) {
        final subIdx = entry.value.indexWhere((r) => r.rpid == rpid);
        if (subIdx >= 0) {
          entry.value[subIdx] = updater(entry.value[subIdx]);
        }
      }
    });
  }

  Future<void> _toggleLikeReply(ReplyItemModel reply) async {
    final aid = _currentEpisode.aid;
    final rpid = reply.rpid;
    if (aid == null || aid <= 0 || rpid == null) return;
    if (!await LoginGuard.requireLogin(context)) return;
    if (!mounted) return;

    final wasLiked = reply.isLiked;
    final wasDisliked = reply.isDisliked;

    _updateReplyInState(
      rpid,
      (r) => r.copyWith(
        like: (r.like ?? 0) + (wasLiked ? -1 : 1),
        action: wasLiked ? 0 : 1,
      ),
    );

    final res = await VideoHttp.likeReply(
      oid: aid,
      rpid: rpid,
      action: wasLiked ? 0 : 1,
    );
    if (!mounted) return;
    if (res case Error(:final errMsg)) {
      _updateReplyInState(
        rpid,
        (r) => r.copyWith(
          like: (r.like ?? 0) + (wasLiked ? 1 : -1),
          action: wasLiked ? 1 : (wasDisliked ? 2 : 0),
        ),
      );
      showToast(context, errMsg ?? '操作失败');
    }
  }

  Future<void> _toggleDislikeReply(ReplyItemModel reply) async {
    final aid = _currentEpisode.aid;
    final rpid = reply.rpid;
    if (aid == null || aid <= 0 || rpid == null) return;
    if (!await LoginGuard.requireLogin(context)) return;
    if (!mounted) return;

    final wasDisliked = reply.isDisliked;
    final wasLiked = reply.isLiked;

    _updateReplyInState(
      rpid,
      (r) => r.copyWith(
        like: (r.like ?? 0) - (wasLiked ? 1 : 0),
        action: wasDisliked ? 0 : 2,
      ),
    );

    final res = await ReplyHttp.hateReply(
      type: 1,
      action: wasDisliked ? 0 : 1,
      oid: aid,
      rpid: rpid,
    );
    if (!mounted) return;
    if (res case Error(:final errMsg)) {
      _updateReplyInState(
        rpid,
        (r) => r.copyWith(
          like: (r.like ?? 0) + (wasLiked ? 1 : 0),
          action: wasDisliked ? 2 : (wasLiked ? 1 : 0),
        ),
      );
      showToast(context, errMsg ?? '操作失败');
    }
  }

  Future<void> _toggleLikeSubReply(ReplyItemModel sub) => _toggleLikeReply(sub);

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
        showToast(context, '加载回复失败');
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
      showToast(context, '评论发表成功');
      _loadReplies(refresh: true);
    } else if (res case Error(:final errMsg)) {
      showToast(context, errMsg ?? '发送失败');
    }
  }

  // ─────────────────────────── 快捷键与全屏 ───────────────────────────

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    // 输入框（评论框 / 弹幕框等）聚焦时不拦截快捷键；Esc 交由全局层“取消聚焦”。
    if (isTextInputFocused()) return;
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
        ctrl.setVolume(ctrl.volume.value + 5);
      case LogicalKeyboardKey.arrowDown:
        ctrl.setVolume(ctrl.volume.value - 5);
      case LogicalKeyboardKey.keyF:
        _toggleFullscreen();
      case LogicalKeyboardKey.keyW:
        _toggleInAppFullscreen();
      case LogicalKeyboardKey.escape:
        // 二级浮层（表情面板 / 弹幕样式…）优先关闭，本次 Esc 不再级联。
        if (EscapeLayerRegistry.instance.closeTopmost()) return;
        _handleEscape();
    }
  }

  Future<void> _toggleFullscreen() async {
    final next = !_fullscreen;
    setState(() => _fullscreen = next);
    if (next) {
      await DesktopFullscreen.enter();
    } else {
      await DesktopFullscreen.exit();
    }
  }

  void _toggleInAppFullscreen() {
    setState(() => _inAppFullscreen = !_inAppFullscreen);
  }

  void _handleEscape() {
    if (_fullscreen) {
      _toggleFullscreen();
    } else if (_inAppFullscreen) {
      _toggleInAppFullscreen();
    } else {
      Navigator.maybePop(context);
    }
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
    final cs = AppThemeHost.of(context).colors;

    final isFill = _fullscreen || _inAppFullscreen;
    // 返回按钮由壳层单实例承担（观感/副作用见 _backButtonSpec）：
    // 全屏时播放器控件自己承担 → 壳层按钮让位隐藏。
    return BackButtonOwner(
      controller: appBackButtonController,
      listenable: _scrollRatio,
      specBuilder: () => _backButtonSpec(context),
      child: isFill
          ? KeyboardListener(
              focusNode: _keyboardFocusNode,
              onKeyEvent: _handleKey,
              child: AppScaffold(
                backgroundColor: AppColors.black,
                body: _withDemoOverlay(
                  playerController != null
                      ? PlayerPanel(
                          controller: playerController!,
                          cover: _currentEpisode.cover ?? widget.detail.cover,
                          fullscreen: _fullscreen,
                          inAppFullscreen: _inAppFullscreen,
                          onToggleFullscreen: _toggleFullscreen,
                          onToggleInAppFullscreen: _toggleInAppFullscreen,
                          onEscape: _handleEscape,
                        )
                      : const Center(child: AppProgressIndicator()),
                ),
              ),
            )
          : KeyboardListener(
              focusNode: _keyboardFocusNode,
              onKeyEvent: _handleKey,
              child: AppScaffold(
                body: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide =
                        constraints.maxWidth >= kDetailNarrowBreakpoint;
                    return isWide
                        ? _buildWideLayout(cs)
                        : _buildNarrowLayout(cs);
                  },
                ),
              ),
            ),
    );
  }

  /// 全局返回按钮规格：本页返回键覆盖在播放器上（随滚动在白色/主题可读色间切换），
  /// 返回前暂停并解绑播放器；全屏 / 应用内全屏时由播放器控件承担 → 壳层让位隐藏。
  BackButtonSpec _backButtonSpec(BuildContext context) {
    if (_fullscreen || _inAppFullscreen) return BackButtonSpec.hidden;
    final tokens = AppThemeHost.of(context);
    final opacity = _topBarScrollOpacity();
    final overVideo = opacity < 0.5;
    final barContrast = resolveAccessibleContainerColors(
      containerColor: tokens.colors.background.withValues(alpha: opacity * 0.95),
      contentColor: tokens.colors.onSurface,
      backgroundColor: tokens.colors.background,
      fallbackContentColors: [
        tokens.colors.onInverseSurface,
        tokens.colors.scrim,
      ],
    );
    return BackButtonSpec(
      color: overVideo ? AppColors.white : barContrast.contentColor,
      background: AppColors.transparent,
      ringShadow: false,
      shadows: overVideo ? ContrastStyle.glyphShadows : null,
      iconSize: 24,
      tooltip: '返回',
      onBeforePop: () {
        playerController?.pause();
        playerController?.detachListeners();
      },
    );
  }

  Widget _buildPlayerContent() {
    return _withDemoOverlay(
      Container(
        color: AppColors.black,
        child: playerController != null
            ? PlayerPanel(
                controller: playerController!,
                cover: _currentEpisode.cover ?? widget.detail.cover,
                fullscreen: false,
                inAppFullscreen: false,
                onToggleFullscreen: _toggleFullscreen,
                onToggleInAppFullscreen: _toggleInAppFullscreen,
                onEscape: _handleEscape,
              )
            : const Center(child: AppProgressIndicator()),
      ),
    );
  }

  /// 演示模式：本地演示播放器（灰画面 + 全要素控制栏 + 本地播放状态；不加载媒体）。
  Widget _withDemoOverlay(Widget child) {
    return ValueListenableBuilder<bool>(
      valueListenable: Pref.demoModeNotifier,
      builder: (context, demo, _) => demo
          ? DemoPlayerChrome(
              seed: _currentEpisode.bvid?.hashCode ??
                  _currentEpisode.id.hashCode,
            )
          : child,
    );
  }

  /// 顶栏滚动吸收行程上下限（px）：随内容区实际可滚范围收敛，保证吸顶可达。
  static const double _kTopBarAbsorbMin = 24;
  static const double _kTopBarAbsorbMax = 56;

  /// 顶栏不透明度：由内容区滚动位移驱动。
  ///
  /// 与普通视频稿件（DetailPage）同源根因（2026-10-17 实机反馈）：
  /// 旧实现只由 `_scrollRatio`（播放器收缩进度）驱动，可滚余量不足时
  /// 0.5 翻色点与 0.95 吸顶阈值永不可达 → 「过渡中/吸顶」完全没有效果。
  /// 改为按滚动位移吸收（行程 = 一条工具栏高，不足时按实际可滚范围收敛）。
  double _topBarScrollOpacity() {
    if (!_scrollController.hasClients) return 0.0;
    final pos = _scrollController.position;
    final absorb = pos.maxScrollExtent.clamp(
      _kTopBarAbsorbMin,
      _kTopBarAbsorbMax,
    );
    return (pos.pixels / absorb).clamp(0.0, 1.0);
  }

  /// 渐变顶栏：滚动位移=0 透明（覆盖在播放器上），到位后不透明（显示标题）。
  /// 完全对齐普通视频稿件（DetailPage）规范。
  Widget _buildGradientTopBar(String? title, {bool forceOpaque = false}) {
    return AnimatedBuilder(
      animation: _scrollController,
      builder: (context, _) {
        final tokens = AppThemeHost.of(context);
        final opacity = forceOpaque ? 1.0 : _topBarScrollOpacity();
        final overVideo = opacity < 0.5;
        // 半透明容器对比度策略（ThemeContrastPolicy）：顶栏拍平到页面背景后，
        // 为标题/返回箭头选出达标可读色（覆盖在播放器上时仍用白色）。
        final barContrast = resolveAccessibleContainerColors(
          containerColor: tokens.colors.background
              .withValues(alpha: opacity * 0.95),
          contentColor: tokens.colors.onSurface,
          backgroundColor: tokens.colors.background,
          fallbackContentColors: [
            tokens.colors.onInverseSurface,
            tokens.colors.scrim,
          ],
        );

        final barContent = SizedBox(
          height: Style.toolbarHeight,
          child: Row(
            children: [
              // 返回键由壳层单实例承担（观感/副作用见 _backButtonSpec）；留出等宽
              // 槽位，避免标题顶到最左被固定的返回按钮遮挡。
              const SizedBox(width: 56),
              Expanded(
                child: opacity > 0.05
                    ? Opacity(
                        opacity: opacity,
                        child: Text(
                          title ?? '番剧详情',
                          overflow: TextOverflow.ellipsis,
                          style: tokens.text.titleMedium?.copyWith(
                            color: barContrast.contentColor,
                            shadows:
                                overVideo ? ContrastStyle.glyphShadows : null,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              MiuixIconButton(

                onPressed: () {
                  Navigator.push(
                    context,
                    AppRoute(
                      builder: (_) => BangumiDetailPage(
                        seasonId: widget.detail.seasonId,
                        detail: widget.detail,
                      ),
                    ),
                  );
                },

                child: AppTooltip(message: '查看番剧详情', child: AppIcon(AppIcons.info(),
                  color: overVideo ? AppColors.white : barContrast.contentColor,
                  shadows: overVideo ? ContrastStyle.glyphShadows : null,
                )),
              ),
              MiuixIconButton(

                onPressed: () => DesktopPipController.instance.enterPip(),

                child: AppTooltip(message: '画中画', child: AppIcon(
                  AppIcons.pip(),
                  color: overVideo ? AppColors.white : barContrast.contentColor,
                  shadows: overVideo ? ContrastStyle.glyphShadows : null,
                )),
              ),
              const SizedBox(width: 8),
            ],
          ),
        );

        // 完全吸顶态（opacity >= 0.95）：固态实色毛玻璃顶栏，防止正文穿透
        if (opacity >= 0.95) {
          return Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    height: Style.toolbarHeight,
                    decoration: BoxDecoration(
                      color: tokens.colors.background
                          .withValues(alpha: 0.95),
                      border: Border(
                        bottom: BorderSide(
                          color: tokens.colors.outlineVariant
                              .withValues(alpha: 0.3),
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: barContent,
                  ),
                ),
              ),
            ),
          );
        }

        // 浮动/过渡态（overVideo 或滚动渐变）：朝下的纯渐进式压暗阴影，轻盈通透且零 GPU 滤镜开销
        final topColor = overVideo
            ? AppColors.black.withValues(
                alpha: (0.45 * (1.0 - opacity) + 0.70 * opacity).clamp(0.0, 1.0))
            : tokens.colors.background
                .withValues(alpha: (opacity * 0.95).clamp(0.0, 1.0));

        return Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Container(
              height: Style.toolbarHeight,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.6, 1.0],
                  colors: [
                    topColor,
                    topColor.withValues(alpha: topColor.a * 0.4),
                    AppColors.transparent,
                  ],
                ),
              ),
              child: barContent,
            ),
          ),
        );
      },
    );
  }

  /// 桌面宽屏双栏布局（左 7: 播放器+互动+简介，右 3: 选集/评论 Tab）
  Widget _buildWideLayout(AppPalette cs) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左栏：播放器核心 + 视频下方交互控件与番剧简介（支持向上滚动挤压缩放）
        Expanded(
          flex: 7,
          child: Stack(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final maxExtent = constraints.maxWidth * 9 / 16;
                  final minExtent = (maxExtent * 0.56).clamp(180.0, 240.0);
                  return CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      VideoHeader(
                        maxExtent: maxExtent,
                        minExtent: minExtent,
                        onScrollRatioChange: (r) {
                          _handleCollapseAutoPause(r);
                          _scrollRatio.value = r;
                        },
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
              _buildGradientTopBar(
                Pref.demoMode ? '番剧详情' : '${widget.detail.title} · ${_currentEpisode.displayTitle}',
              ),
            ],
          ),
        ),
        // 分割线
        MiuixVerticalDivider(thickness: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),
        // 右栏：选集 / 评论
        Expanded(
          flex: 3,
          child: Column(
            children: [
              AppTabBar(
                controller: _wideTabCtrl,
                tabs: [
                  Pref.demoMode ? '选集' : '选集 (${_episodes.length})',
                  Pref.demoMode ? '评论' : '评论 (${_replies.length})',
                ],
              ),
              Expanded(
                child: AppTabBody(
                  controller: _wideTabCtrl,
                  children: [
                    DemoMask(
                      skeleton: _buildPanelSkeleton,
                      child: () => _buildEpisodesSidebar(cs),
                    ),
                    DemoMask(
                      skeleton: _buildPanelSkeleton,
                      child: () => _buildCommentsSidebar(cs),
                    ),
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
  Widget _buildNarrowLayout(AppPalette cs) {
    return Stack(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final maxExtent = constraints.maxWidth * 9 / 16;
            final minExtent = (maxExtent * 0.56).clamp(180.0, 240.0);
            return NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                VideoHeader(
                  maxExtent: maxExtent,
                  minExtent: minExtent,
                  onScrollRatioChange: (r) {
                    _handleCollapseAutoPause(r);
                    _scrollRatio.value = r;
                  },
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
                    // 吸顶背景改由通栏毛玻璃带承担（全宽档：无圆角、仅底部 1px
                    // 描边），滚动内容从栏后经过时可见模糊；标签条自身不再叠面板。
                    child: MiuixFrostedSurface(
                      borderRadius: 0,
                      child: AppTabBar(
                        controller: _narrowTabCtrl,
                        tabs: [
                          Pref.demoMode ? '选集' : '选集 (${_episodes.length})',
                          '简介与互动',
                          Pref.demoMode ? '评论' : '评论 (${_replies.length})',
                        ],
                        blurBackground: false,
                      ),
                    ),
                    extent: AppTabBar.defaultHeight,
                  ),
                ),
              ],
              body: AppTabBody(
                controller: _narrowTabCtrl,
                children: [
                  DemoMask(
                    skeleton: _buildPanelSkeleton,
                    child: () => _buildEpisodesSidebar(cs),
                  ),
                  DemoMask(
                    skeleton: _buildPanelSkeleton,
                    child: () => SingleChildScrollView(
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
                  DemoMask(
                    skeleton: _buildPanelSkeleton,
                    child: () => _buildCommentsSidebar(cs),
                  ),
                ],
              ),
            );
          },
        ),
        _buildGradientTopBar(
          Pref.demoMode ? '番剧详情' : '${widget.detail.title} · ${_currentEpisode.displayTitle}',
        ),
      ],
    );
  }

  /// 演示模式：右栏/内容区通用骨架。
  Widget _buildPanelSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.all(Style.md),
      itemCount: 8,
      itemBuilder: (context, index) => const Padding(
        padding: EdgeInsets.only(bottom: Style.sm),
        child: Skeleton(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 96, height: 56),
              SizedBox(width: Style.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonLine(width: double.infinity, height: 12),
                    SizedBox(height: 6),
                    SkeletonLine(width: 100, height: 10),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────── 选集 Sidebar ───────────────────────────

  Widget _buildEpisodesSidebar(AppPalette cs) {
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
              MiuixButton(onPressed: () {
                  Pref.setBangumiEpisodesDescending(!_episodesDescending);
                }, child: Row(mainAxisSize: MainAxisSize.min, children: [AppIcon(
                  _episodesDescending
                      ? AppIcons.chevronDown()
                      : AppIcons.chevronUp(),
                  size: 16,
                ), const SizedBox(width: 6), Text(_episodesDescending ? '倒序' : '正序')])),
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

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: ShapeDecoration(
                  color: isCurrent ? cs.primaryContainer.withValues(alpha: 0.5) : cs.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Style.radiusSm),
                    side: BorderSide(
                      color: isCurrent ? cs.primary : cs.outlineVariant.withValues(alpha: 0.4),
                      width: isCurrent ? 1.5 : 1,
                    ),
                  ),
                ),
                child: MiuixPressable(
                  feedbackType: MiuixPressFeedbackType.sink,
                  sinkAmount: 0.98,
                  borderRadius: BorderRadius.circular(Style.radiusSm),
                  onPressed: () => _switchEpisode(ep),
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
                                        color: ep.badge!.contains('会员') ? AppColors.orange : AppColors.pink,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                      child: Text(
                                        ep.badge!,
                                        style: const TextStyle(
                                          fontSize: 8,
                                          color: AppColors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                if (isCurrent)
                                  Container(
                                    color: AppColors.black.withValues(alpha: 0.45),
                                    child: Center(
                                      child: AppIcon(
                                        AppIcons.play(active: true),
                                        color: AppColors.white,
                                        size: 24,
                                      ),
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

  Widget _buildCommentsSidebar(AppPalette cs) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Style.sm, Style.xs, Style.sm, 0),
          child: _buildCommentSortRow(cs),
        ),
        Expanded(child: _buildReplyListView(cs)),
        _buildCommentInputBar(),
      ],
    );
  }

  /// 评论排序行（对标普通视频稿件 CommentSortHeader）
  Widget _buildCommentSortRow(AppPalette cs) {
    final tokens = AppThemeHost.of(context);
    Widget sortBtn(String label, int mode) {
      final selected = _replyMode == mode;
      return MiuixPressable(
        onPressed: () {
          if (_replyMode != mode) {
            setState(() => _replyMode = mode);
            _loadReplies(refresh: true);
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              color: selected
                  ? tokens.colors.onSurface
                  : tokens.colors.onSurfaceVariant,
            ),
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
            color: tokens.colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  void _maybeLoadMoreReplies() {
    if (_loadingReplies || _replyEnd || _replyFailed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _loadingReplies || _replyEnd || _replyFailed) return;
      _loadReplies(refresh: false);
    });
  }

  void _retryReplies() {
    setState(() {
      _replyFailed = false;
    });
    _loadReplies(refresh: true);
  }

  /// 评论列表（使用普通视频稿件设计）
  Widget _buildReplyListView(AppPalette cs) {
    if (_replies.isEmpty && _loadingReplies) {
      return const Center(child: AppProgressIndicator());
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
    final tokens = AppThemeHost.of(context);
    final member = reply.member;
    final grayStyle = TextStyle(
      fontSize: 12,
      color: tokens.colors.onSurfaceVariant,
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
                                    : tokens.colors.onSurface,
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
                              color: tokens.colors.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              'LV$lvl',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: tokens.colors.onSurfaceVariant,
                                height: 1.1,
                              ),
                            ),
                          ),
                        const Spacer(),
                        Text(_formatDate(reply.ctime), style: grayStyle),
                      ],
                    ),
                    const SizedBox(height: Style.xs),
                    ReplyContentView(
                      content: reply.content,
                      textStyle: tokens.text.bodyMedium?.copyWith(
                        fontSize: 14.5,
                        height: 1.55,
                        color: tokens.colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: Style.sm),
                    // 操作行：点赞 + 点踩 + UP主赞 + 回复 + 展开折叠
                    Row(
                      spacing: Style.lg,
                      children: [
                        GestureDetector(
                          onTap: () => _toggleLikeReply(reply),
                          child: Row(
                            spacing: 4,
                            children: [
                              AppIcon(
                                AppIcons.like(active: reply.isLiked),
                                size: 15,
                                color: reply.isLiked
                                    ? biliPink
                                    : tokens.colors.onSurfaceVariant,
                              ),
                              Text(
                                NumUtils.formatNum(reply.like),
                                style: grayStyle.copyWith(
                                  fontSize: 12,
                                  color: reply.isLiked
                                      ? biliPink
                                      : tokens.colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _toggleDislikeReply(reply),
                          child: AppIcon(
                            AppIcons.dislike(active: reply.isDisliked),
                            size: 15,
                            color: reply.isDisliked
                                ? biliPink
                                : tokens.colors.onSurfaceVariant,
                          ),
                        ),
                        if (reply.upAction?.like == true)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: biliPink.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text(
                              'UP主觉得很赞',
                              style: TextStyle(
                                fontSize: 10,
                                color: biliPink,
                                fontWeight: FontWeight.w500,
                                height: 1.1,
                              ),
                            ),
                          ),
                        GestureDetector(
                          onTap: () => _setReplyTarget(reply),
                          child: Row(
                            spacing: 3,
                            children: [
                              AppIcon(
                                AppIcons.reply(),
                                size: 15,
                                color: tokens.colors.onSurfaceVariant,
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
                                    color: tokens.colors.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                AppIcon(
                                  subReplies != null
                                      ? AppIcons.chevronUp()
                                      : AppIcons.expandMore(),
                                  size: 15,
                                  color: tokens.colors.primary,
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
                color: tokens.colors.surfaceContainerHighest
                    .withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(Style.radiusMd),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = 0; i < subReplies.length; i++) ...[
                    if (i > 0) ...[
                      const SizedBox(height: Style.xs),
                      MiuixHorizontalDivider(
                        thickness: 0.5,
                        color: tokens.colors.outlineVariant
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
                          child: AppProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  if (!subEnd && !subLoading && subReplies.length >= 3)
                    Padding(
                      padding: const EdgeInsets.only(top: Style.xs),
                      child: MiuixButton(onPressed: () => _loadSubReplies(reply), child: Row(mainAxisSize: MainAxisSize.min, children: [AppIcon(AppIcons.expandMore(), size: 16), const SizedBox(width: 6), Text(
                          '查看更多回复 ${reply.rcount != null ? "(${subReplies.length}/${reply.rcount})" : ""}',
                          style: const TextStyle(fontSize: 12),
                        )])),
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
    final tokens = AppThemeHost.of(context);
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
                            color: tokens.colors.primary,
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
                          color: tokens.colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          'LV$lvl',
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                            color: tokens.colors.onSurfaceVariant,
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
                  color: tokens.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          // 第 2 行：回复正文
          Padding(
            padding: const EdgeInsets.only(left: 36, top: 4, bottom: 4),
            child: ReplyContentView(
              content: sub.content,
              textStyle: tokens.text.bodyMedium?.copyWith(
                fontSize: 13.5,
                height: 1.5,
                color: tokens.colors.onSurface,
              ),
            ),
          ),
          // 第 3 行：操作栏（点赞 + 点踩 + UP主赞 + 回复）
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
                      AppIcon(
                        AppIcons.like(active: sub.isLiked),
                        size: 13,
                        color: sub.isLiked
                            ? biliPink
                            : tokens.colors.onSurfaceVariant,
                      ),
                      Text(
                        NumUtils.formatNum(sub.like),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: sub.isLiked
                              ? biliPink
                              : tokens.colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => _toggleDislikeReply(sub),
                  child: AppIcon(
                    AppIcons.dislike(active: sub.isDisliked),
                    size: 13,
                    color: sub.isDisliked
                        ? biliPink
                        : tokens.colors.onSurfaceVariant,
                  ),
                ),
                if (sub.upAction?.like == true)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 0.5,
                    ),
                    decoration: BoxDecoration(
                      color: biliPink.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: const Text(
                      'UP主觉得很赞',
                      style: TextStyle(
                        fontSize: 9.5,
                        color: biliPink,
                        fontWeight: FontWeight.w500,
                        height: 1.1,
                      ),
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
                      AppIcon(
                        AppIcons.reply(),
                        size: 13,
                        color: tokens.colors.onSurfaceVariant,
                      ),
                      Text(
                        '回复',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: tokens.colors.onSurfaceVariant,
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
  Widget _buildReplyTrailer(AppPalette cs) {
    final tokens = AppThemeHost.of(context);
    if (_loadingReplies) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: Style.lg),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: AppProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_replyFailed) {
      return Center(
        child: MiuixTextButton('评论加载失败，点击重试', onPressed: _retryReplies),
      );
    }
    if (_replies.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Style.lg),
        child: Center(
          child: Text(
            '还没有评论',
            style: TextStyle(
              color: tokens.colors.onSurfaceVariant,
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
            '没有更多评论',
            style: TextStyle(
              fontSize: 12,
              color: tokens.colors.outline,
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  /// 评论输入栏（普通视频稿件同款胶囊输入框与粉色发送按钮）
  Widget _buildCommentInputBar() {
    // B7-c4 输入条统一批：容器与骨架收敛到共享 CommentInputBar，此处仅做本页参数适配。
    final enabled = _currentEpisode.aid != null && _currentEpisode.aid! > 0;
    return CommentInputBar(
      controller: _commentCtrl,
      focusNode: _commentFocus,
      sending: _sendingComment,
      enabled: enabled && !_sendingComment,
      hintText: enabled ? (_replyHint ?? '发一条友善的评论吧~') : '当前剧集暂不支持评论',
      suffix: _replyRoot != null
          ? MiuixIconButton(
              onPressed: _clearReplyTarget,
              child: AppIcon(AppIcons.clear(), size: 16),
            )
          : null,
      onSend: () => _sendComment(),
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
        color: AppThemeHost.of(context).colors.surface,
        borderRadius: BorderRadius.circular(Style.mdRadius),
        border: Border.all(
          color: AppThemeHost.of(context).colors.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: child,
    );
  }

  void _goToDetailPage() {
    Navigator.push(
      context,
      AppRoute(
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
        showToast(context, '已追番');
      } else if (res case Error(:final errMsg)) {
        showToast(context, errMsg ?? '追番失败');
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

  Widget _buildFollowButton(AppPalette cs) {
    return GestureDetector(
      onSecondaryTap: _isFollowed ? _showFollowStatusDialog : null,
      child: MiuixButton(onPressed: _toggleFollow, child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              AppIcons.favorite(active: _isFollowed),
              size: 16,
              color: _isFollowed ? AppColors.pink : null,
            ),
            const SizedBox(width: 4),
            Text(_followStatusLabel),
          ],
        )),
    );
  }

  /// 视频下方交互区（对标普通视频稿件 detail_page.dart 的 _buildInfoSection）
  Widget _buildInfoSection(AppPalette cs) {
    final tokens = AppThemeHost.of(context);
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
            style: tokens.text.titleMedium?.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: Style.sm),
          // 数据行（播放量、弹幕、时长、开播时间）
          Row(
            children: [
              AppIcon(AppIcons.viewCount(), size: 15, color: cs.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(NumUtils.formatNum(stat?.views), style: grayStyle),
              const SizedBox(width: Style.md),
              AppIcon(AppIcons.danmakuCount(), size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(NumUtils.formatNum(stat?.danmakus), style: grayStyle),
              if (_currentEpisode.duration != null && _currentEpisode.duration! > 0) ...[
                const SizedBox(width: Style.md),
                AppIcon(AppIcons.duration(), size: 14, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(_currentEpisode.formattedDuration, style: grayStyle),
              ],
              if (_currentEpisode.pubTime != null || widget.detail.publish?.releaseDateShow != null) ...[
                const SizedBox(width: Style.md),
                AppIcon(AppIcons.calendar(), size: 13, color: cs.onSurfaceVariant),
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
                              style: tokens.text.titleSmall?.copyWith(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          AppIcon(AppIcons.chevronForward(), size: 16, color: cs.outline),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (widget.detail.rating != null && widget.detail.rating!.score > 0) ...[
                            AppIcon(AppIcons.favorite(active: true), color: AppColors.amber, size: 15),
                            const SizedBox(width: 2),
                            Text(
                              widget.detail.rating!.score.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.amber,
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
          const SizedBox(height: Style.xl, child: Center(child: MiuixHorizontalDivider())),
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
  Widget _buildDescSection(AppPalette cs) {
    final desc = widget.detail.evaluate.trim();
    final hasActors = widget.detail.actors.isNotEmpty;
    final hasStaff = widget.detail.staff.isNotEmpty;
    final grayColor = cs.onSurfaceVariant;

    return _card(
      margin: const EdgeInsets.only(top: Style.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MiuixPressable(
            feedbackType: MiuixPressFeedbackType.sink,
            sinkAmount: 0.98,
            onPressed: desc.isEmpty ? null : () => setState(() => _descExpanded = !_descExpanded),
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
              child: MiuixTextButton(
                _descExpanded ? '收起' : '展开',
                onPressed: () => setState(() => _descExpanded = !_descExpanded),
              ),
            ),
          // 展开状态下展示声优和制作人员
          if (_descExpanded && (hasActors || hasStaff)) ...[
            const SizedBox(height: Style.lg, child: Center(child: MiuixHorizontalDivider())),
            if (hasActors) ...[
              const Text('声优 / 演员', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              AppSelectableText(
                widget.detail.actors,
                style: TextStyle(fontSize: 12, color: grayColor, height: 1.4),
              ),
              const SizedBox(height: Style.sm),
            ],
            if (hasStaff) ...[
              const Text('制作人员', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              AppSelectableText(
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
  Widget _buildTagsSection(AppPalette cs) {
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
      final wasLiked = _hasLike;
      final res = await VideoHttp.likeVideo(aid: aid, type: wasLiked);
      if (res case Success()) {
        setState(() => _hasLike = !wasLiked);
      }
    }
  }

  Future<void> _actionCoin(BuildContext anchorContext) async {
    if (!await LoginGuard.requireLogin(context)) return;
    final aid = _currentEpisode.aid;
    if (aid != null && aid > 0) {
      if (!mounted) return;
      if (!anchorContext.mounted) return;
      await showCoinDialog(
        context,
        anchorContext: anchorContext,
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
      showToast(context, '一键三连成功！');
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
    showToast(context, '播放链接已复制到剪贴板');
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
      showToast(context, !inList ? '已添加到稍后再看' : '已从稍后再看移除');
    } else if (res case Error(:final errMsg)) {
      showToast(context, errMsg ?? '操作失败');
    }
  }

  void _showFollowStatusDialog() {
    showAppDialog(
      context: context,
      builder: (ctx) => AppSimpleDialog(
        title: const Text('追番状态设置'),
        children: [
          AppSimpleDialogOption(
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
          AppSimpleDialogOption(
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
          AppSimpleDialogOption(
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
          const SizedBox(height: 16, child: Center(child: MiuixHorizontalDivider())),
          AppSimpleDialogOption(
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
            child: const Text('取消追番', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
  }
}

/// 番剧窄屏分类标签条的吸顶委托：`minExtent == maxExtent == [extent]`。
///
/// 背景**不再包实色 `ColoredBox`**——那层实色会把吸顶处的毛玻璃垫死，滚动内容
/// 从栏后经过时看不到模糊（实机反馈）。改由 [child] 自带的通栏毛玻璃带承担。
class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverTabBarDelegate({required this.child, required this.extent});

  final Widget child;
  final double extent;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return child != oldDelegate.child || extent != oldDelegate.extent;
  }
}

