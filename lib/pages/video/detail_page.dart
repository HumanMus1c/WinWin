import 'dart:async';
import 'dart:ui';

import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

import 'package:winwin/common/skeleton/skeleton.dart';
import 'package:winwin/common/skeleton/video_card_h.dart';
import 'package:winwin/common/widgets/comment/emote_picker.dart';
import 'package:winwin/common/widgets/comment/reply_content_view.dart';
import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/common/widgets/sliver/video_header.dart';
import 'package:winwin/common/widgets/video_card/video_card_h.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/core/account/login_guard.dart';
import 'package:winwin/core/app_messenger.dart' as app_messenger;
import 'package:winwin/core/log/app_logger.dart';
import 'package:winwin/core/log/sync_trace.dart';
import 'package:winwin/common/widgets/demo_editable.dart';
import 'package:winwin/common/widgets/demo_mask.dart';
import 'package:winwin/core/demo/demo_overrides.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/http/follow.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/reply.dart';
import 'package:winwin/http/video.dart';
import 'package:winwin/main.dart';
import 'package:winwin/models/video/related_video.dart';
import 'package:winwin/models/video/reply_item.dart';
import 'package:winwin/models/video/video_detail.dart';
import 'package:winwin/models/video/video_tag.dart';
import 'package:winwin/pages/member/member_space_page.dart';
import 'package:winwin/pages/search/search_result_page.dart';
import 'package:winwin/core/window/desktop_fullscreen.dart';
import 'package:winwin/pages/video/desktop_pip.dart';
import 'package:winwin/pages/video/mixins/video_interaction_mixin.dart';
import 'package:winwin/pages/video/player_controller.dart';
import 'package:winwin/pages/video/player_panel.dart';
import 'package:winwin/pages/video/send_danmaku_panel.dart';
import 'package:winwin/pages/video/video_action_row.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/contrast_policy.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/app_empty_state.dart';
import 'package:winwin/ui/components/glass_contrast_widgets.dart';
import 'package:winwin/ui/components/immersive_title_bar.dart';
import 'package:winwin/utils/duration_utils.dart';
import 'package:winwin/utils/num_utils.dart';

/// 详情页窄屏断点：窗口宽度低于该值时切换单列布局
/// （对标 BiliPai Tablet/Phone 按宽度分发）。
const double kDetailNarrowBreakpoint = 900;

/// 视频详情页 — 桌面宽屏双栏布局（对标 BiliPai TabletVideoLayout）。
///
/// 左栏（flex 7）：播放器、弹幕发送栏、标题/数据/UP、简介、标签；
/// 右栏（flex 3）：评论 (N) / 相关推荐双 Tab。窄屏断点以下
/// 退化为单列（评论内联左栏，推荐追加尾部）。视觉沿用 BiliPai 的
/// iOS 风格（圆角卡片、safeSpace 边距、扁平无阴影）。
class VideoDetailPage extends StatefulWidget {
  const VideoDetailPage({
    super.key,
    required this.bvid,
    this.cover,
    this.heroTag,
  });

  final String bvid;
  final String? cover;
  final Object? heroTag;

  @override
  State<VideoDetailPage> createState() => _VideoDetailPageState();
}

class _VideoDetailPageState extends State<VideoDetailPage>
    with
        RouteAware,
        WindowListener,
        SingleTickerProviderStateMixin,
        VideoInteractionMixin<VideoDetailPage> {
  final ScrollController scrollController = ScrollController();
  WinWinPlayerController? playerController;

  LoadingState<VideoDetailData> _detailState = LoadingState.loading();
  LoadingState<List<RelatedVideoItem>> _relatedState = LoadingState.loading();

  final List<ReplyItemModel> _replies = [];
  String? _nextOffset;
  bool _replyEnd = false;
  bool _loadingReplies = false;
  bool _replyFailed = false;

  /// 评论排序模式（对标 BiliPai CommentSortHeader 最热/最新切换）：
  /// 3=最热（默认），2=最新。切换时清空列表重新加载。
  int _replyMode = 3;

  /// 宽屏右栏 Tab 控制器（对标 BiliPai TabletSecondaryContent：
  /// 评论 (N) / 相关推荐 双 Tab）。窄屏单列布局不使用。
  late final TabController _rightTabCtrl;

  /// 楼中楼展开状态：key = 根评论 rpid，value = 二级回复列表。
  final Map<int, List<ReplyItemModel>> _subReplies = {};
  final Map<int, String?> _subNextOffset = {};
  final Map<int, bool> _subEnd = {};
  final Map<int, bool> _subLoading = {};

  /// 评论输入框。
  final TextEditingController _commentCtrl = TextEditingController();
  final FocusNode _commentFocus = FocusNode();
  bool _sendingComment = false;
  /// 回复目标（null=发表一级评论，否则为根评论 rpid + 被回复用户名）。
  int? _replyRoot;
  String? _replyHint;

  bool _fullscreen = false;
  bool _inAppFullscreen = false;
  bool _descExpanded = false;

  @override
  int? get interactionAid => _detailState.dataOrNull?.aid;

  @override
  String get interactionBvid => widget.bvid;

  @override
  int? get interactionOwnerMid => _detailState.dataOrNull?.owner?.mid;

  @override
  Future<bool> requireLoginAndSync() => _requireLoginAndSync();

  @override
  void adjustStat(void Function(VideoStat stat) fn) => _adjustStat(fn);

  @override
  void showToast(String msg) => _toast(msg);

  /// Phase 7.6.3：VideoHeader 收缩比例（0.0=展开，1.0=pin），用于顶栏渐变。
  final ValueNotifier<double> _scrollRatio = ValueNotifier<double>(0.0);

  /// 折叠自动暂停：本次是否由折叠触发暂停（展开时仅恢复该情形，不覆盖手动暂停）。
  bool _autoPausedByCollapse = false;

  /// 页面被新路由覆盖前的播放状态，用于返回时决定是否自动播放。
  bool _wasPlaying = false;
  /// 页面被覆盖前记录的播放位置，用于返回时恢复进度。
  Duration _savedPosition = Duration.zero;

  /// 稿件标签（对标 BiliPai videoTags，`/x/tag/archive/tags`）。
  List<VideoTag> _tags = const [];

  @override
  void initState() {
    super.initState();
    _rightTabCtrl = TabController(length: 2, vsync: this);
    windowManager.addListener(this);
    initInteractionEventBus();
    _loadDetail();
    _loadRelated();
    _loadTags();
    // 演示模式切换时重建（播放器遮罩与分区骨架即时生效）。
    Pref.demoModeNotifier.addListener(_onDemoChanged);
  }

  void _onDemoChanged() {
    if (!mounted) return;
    if (Pref.demoMode) {
      // 进入演示：暂停播放（与正常模式数据隔离）。
      playerController?.pause();
    } else if (_detailState is Loading) {
      // 退出演示且尚未加载：恢复正常模式的云端加载。
      _loadDetail();
      _loadRelated();
      _loadTags();
    }
    setState(() {});
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
    _scrollRatio.dispose();
    SyncTrace.log('DetailPage', 'dispose enter');
    routeObserver.unsubscribe(this);
    // 沉浸标题条：回收本页推送的背景覆写（覆盖 pushReplacement 等未走 didPop 的路径）。
    WidgetsBinding.instance
        .addPostFrameCallback((_) => clearTitleBarBackdrop(this));
    windowManager.removeListener(this);
    _rightTabCtrl.dispose();
    // 退出时如果处于 PiP 模式，恢复窗口。
    DesktopPipController.instance.exitPip();
    if (_fullscreen) {
      DesktopFullscreen.exit();
    }
    SyncTrace.log('DetailPage', 'dispose before playerController.dispose');
    playerController?.dispose();
    SyncTrace.log('DetailPage', 'dispose after playerController.dispose');
    scrollController.dispose();
    _commentCtrl.dispose();
    _commentFocus.dispose();
    disposeInteractionEventBus();
    super.dispose();
    SyncTrace.log('DetailPage', 'dispose done');
  }

  /// 播放器折叠自动暂停（对标 BiliPai PlayerCollapseAutoPausePolicy）。
  ///
  /// 折叠到 pin 态（ratio≈1）且正在播放时自动暂停并置位 [_autoPausedByCollapse]；
  /// 展开回落（ratio<0.5）且本次确系折叠自动暂停时恢复播放并复位。
  /// 全屏态与手动暂停均不触发，避免覆盖用户意图。
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

  // ─────────────────────────── RouteAware ───────────────────────────

  /// 新页面 push 到本页之上时：暂停共享播放器并移除本页的事件监听
  /// （参照 PiliPlus didPushNext: pause + removeStatusLister +
  /// removePositionListener）。这样新页面在共享 player 上切换 media 时，
  /// 旧 media 卸载产生的事件不会污染本页 controller 的状态。
  @override
  void didPushNext() {
    clearTitleBarBackdrop(this);
    final ctrl = playerController;
    if (ctrl != null) {
      _wasPlaying = ctrl.playing.value;
      _savedPosition = ctrl.position.value;
      // Phase 4.2：页面被覆盖时上报最终进度（best-effort，不阻塞）。
      ctrl.reportCurrentProgress();
      ctrl.pause();
      ctrl.detachListeners();
    }
  }

  @override
  void didPop() {
    clearTitleBarBackdrop(this);
  }

  /// 上一个页面 pop 回到本页时：重新挂载事件监听。
  /// 若播放器仍保持就绪态（未被其他页面释放或换源），直接复用现有已缓冲媒体与解码器，
  /// 彻底杜绝从作者空间等页面返回时的重新拉流与重复加载（对标 PiliPlus didPopNext）。
  @override
  void didPopNext() {
    _syncTitleBarBackdrop();
    final ctrl = playerController;
    if (ctrl != null) {
      ctrl.attachListeners();
      if (!ctrl.ready.value) {
        AppLogger.i(
          'VideoDetailPage',
          'didPopNext: re-init player from ${_savedPosition.inSeconds}s, autoplay=$_wasPlaying',
        );
        ctrl.load(start: _savedPosition, autoplay: _wasPlaying);
      } else {
        AppLogger.i(
          'VideoDetailPage',
          'didPopNext: resume existing player session, wasPlaying=$_wasPlaying, completed=${ctrl.completed.value}',
        );
        if (_wasPlaying && !ctrl.completed.value && !Pref.demoMode) {
          ctrl.play();
        }
      }
      // 重建弹幕：PlayerPanel 始终挂载，WinWinDanmaku 不会随路由重建，
      // 需显式触发 dm 重建 + 引擎 clear（参照 PiliPlus didPopNext 重建 PlDanmaku）。
      ctrl.reloadDanmaku();
      _wasPlaying = false;
      _savedPosition = Duration.zero;
    }
  }

  // ─────────────────────────── 沉浸标题条配色 ───────────────────────────

  /// 全屏/网页全屏时标题条转纯黑（与播放器底色一致）；其余沿用主题背景。
  void _syncTitleBarBackdrop() {
    if (_fullscreen || _inAppFullscreen) {
      pushTitleBarBackdrop(this, Colors.black);
    } else {
      clearTitleBarBackdrop(this);
    }
  }

  // ─────────────────────────── WindowListener（Phase 4.6 自动 PiP）──

  /// 窗口失焦时，如果启用了 autoPiP 且正在播放，自动进入画中画。
  @override
  void onWindowBlur() {
    if (!autoPipEnabled) return;
    final ctrl = playerController;
    if (ctrl == null || !ctrl.playing.value) return;
    DesktopPipController.instance.enterPip();
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted && !_fullscreen) {
      setState(() => _fullscreen = true);
    }
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted && _fullscreen) {
      setState(() => _fullscreen = false);
    }
  }

  // ─────────────────────────── 数据加载 ───────────────────────────

  Future<void> _loadDetail() async {
    // 演示模式：不拉取云端数据（与正常模式完全隔离）。
    if (Pref.demoMode) return;
    setState(() => _detailState = LoadingState.loading());
    final res = await VideoHttp.videoIntro(bvid: widget.bvid);
    if (!mounted) return;
    switch (res) {
      case Success(:final response):
        final pages = response.pages ?? const <VideoPage>[];
        final int? cid =
            pages.isNotEmpty && pages.first.cid != null
                ? pages.first.cid
                : response.cid;
        if (cid != null) {
          final aid = response.aid;
          // 稿件总时长（秒），用于判定上次进度是否已接近播完。
          final detailDurSec = response.duration ?? 0;
          final ctrl = WinWinPlayerController(bvid: widget.bvid, cid: cid);
          ctrl.aid = aid;
          playerController = ctrl;
          // Phase 4.2 优化：playInfo（续播进度/字幕/章节）与播放器加载并行，
          // 不再串行等待 —— 首帧关键路径少一次 HTTP 往返。
          // playInfo 返回后通过 resumeTo 恢复进度（race-free，见控制器）。
          unawaited(_applyPlayInfo(ctrl, cid, detailDurSec, aid: aid));
          // 挂「启动闸门」：续播点（playInfo）返回前不起播，杜绝先闪 0 位画面/声音。
          ctrl.load(gateForResume: true);
        }
        // 互动初始态（来自 req_user 或并发拉取云端 videoRelation 真实姿态）。
        hasLike = response.reqUser?.like ?? false;
        coinNum = response.reqUser?.coin ?? 0;
        hasFav = response.reqUser?.favorite ?? false;
        hasDislike = false;
        isFollowed = response.reqUser?.follow == 1;
        _loadWatchLaterStatus(response.aid);
        if (Accounts.main.isLogin) {
          unawaited(_syncVideoRelation(aid: response.aid));
        }
        if (response.owner?.mid != null) {
          unawaited(_checkFollowStatus(response.owner!.mid!));
        }
        setState(() => _detailState = Success(response));
        if (response.aid != null) {
          _loadReplies(oid: response.aid!);
        }
      case Error():
        setState(() => _detailState = res);
      case Loading():
        break;
    }
  }

  /// 拉取 playInfo 并应用到控制器（与 ctrl.load 并行执行，Phase 4.2/4.4/4.5）。
  ///
  /// 提供：上次播放进度（last_play_time，经 [WinWinPlayerController.resumeTo]
  /// 恢复）、字幕列表、章节标记。失败静默，不阻断播放。
  Future<void> _applyPlayInfo(
    WinWinPlayerController ctrl,
    int cid,
    int detailDurSec, {
    int? aid,
  }) async {
    try {
      final infoRes = await VideoHttp.playInfo(
        aid: aid,
        bvid: widget.bvid,
        cid: cid,
      );
      if (!mounted) return;
      if (infoRes case Success(:final response)) {
        // Phase 4.4：传入可用字幕列表，SubtitleController 自动按 AI 偏好选择。
        final subtitles = response.subtitle?.subtitles ?? const [];
        if (subtitles.isNotEmpty) {
          ctrl.setSubtitleList(subtitles);
        }
        // Phase 4.5：传入章节标记（view_points），供进度条渲染章节标记。
        final viewPoints = response.viewPoints;
        if (viewPoints.isNotEmpty) {
          ctrl.setViewPoints(viewPoints);
        }
        // last_play_time 单位为毫秒（参照 PiliPlus
        // Duration(milliseconds: data.lastPlayTime)）；
        // 已接近播完（距结尾 ≤10s）时不续播，从头开始。
        if (response.lastPlayTime > 0) {
          final lastSec = response.lastPlayTime ~/ 1000;
          if (detailDurSec <= 0 || lastSec < detailDurSec - 10) {
            ctrl.resumeTo(Duration(milliseconds: response.lastPlayTime));
          } else {
            // 已接近播完：不续播——放闸从 0 起播（与既有行为一致）。
            ctrl.releaseStartupGate(reason: 'near-end');
          }
        } else {
          // 无续播点：放闸从 0 起播。
          ctrl.releaseStartupGate(reason: 'no-history');
        }
      } else if (infoRes case Error(:final errMsg)) {
        ctrl.releaseStartupGate(reason: 'info-error');
        AppLogger.w('VideoDetailPage', '_applyPlayInfo failed: $errMsg (bvid=${widget.bvid}, cid=$cid)');
      }
    } catch (e, s) {
      ctrl.releaseStartupGate(reason: 'info-exception');
      AppLogger.e('VideoDetailPage', '_applyPlayInfo exception: $e (bvid=${widget.bvid}, cid=$cid)', error: e, stackTrace: s);
    }
  }

  Future<void> _loadRelated() async {
    if (Pref.demoMode) return;
    setState(() => _relatedState = LoadingState.loading());
    final res = await VideoHttp.relatedVideoList(bvid: widget.bvid);
    if (!mounted) return;
    switch (res) {
      case Success(:final response):
        setState(() => _relatedState = Success(response));
      case Error():
        setState(() => _relatedState = res);
      case Loading():
        break;
    }
  }

  /// 拉取稿件标签（对标 BiliPai loadVideoTags，失败静默降级不展示）。
  Future<void> _loadTags() async {
    if (Pref.demoMode) return;
    final res = await VideoHttp.videoTags(bvid: widget.bvid);
    if (!mounted) return;
    if (res case Success(:final response)) {
      if (response.isNotEmpty) setState(() => _tags = response);
    }
  }

  Future<void> _loadReplies({
    required int oid,
    String? nextOffset,
    bool refresh = false,
  }) async {
    if (Pref.demoMode) return;
    if (_loadingReplies) return;
    if (refresh) {
      _replies.clear();
      _nextOffset = null;
      _replyEnd = false;
      _replyFailed = false;
      _subReplies.clear();
    }
    _loadingReplies = true;
    if (mounted) setState(() {});
    try {
      final res = await VideoHttp.replyMain(
        oid: oid,
        nextOffset: nextOffset,
        mode: _replyMode,
      );
      if (!mounted) return;
      switch (res) {
        case Success(:final response):
          final cursor = response.cursor;
          _nextOffset = cursor?.nextOffset;
          _replyEnd = (cursor?.isEnd == true) ||
              response.replies.isEmpty ||
              (_nextOffset == null || _nextOffset!.isEmpty);
          _replyFailed = false;
          _replies.addAll(response.replies);
        case Error():
          _replyFailed = true;
        case Loading():
          break;
      }
    } catch (e) {
      AppLogger.w('Detail', '_loadReplies error: $e');
      _replyFailed = true;
    } finally {
      _loadingReplies = false;
      if (mounted) setState(() {});
    }
  }

  /// 滚动到列表尾部时触发（通过 addPostFrameCallback 避免 build 阶段重入）。
  void _maybeLoadMoreReplies() {
    final aid = _detailState.dataOrNull?.aid;
    if (aid == null || _loadingReplies || _replyEnd || _replyFailed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _loadingReplies || _replyEnd || _replyFailed) return;
      _loadReplies(oid: aid, nextOffset: _nextOffset);
    });
  }

  void _retryReplies() {
    final aid = _detailState.dataOrNull?.aid;
    if (aid == null) return;
    setState(() => _replyFailed = false);
    _loadReplies(oid: aid, nextOffset: _nextOffset);
  }

  /// 切换评论排序（最热/最新，对标 BiliPai setSortMode）：
  /// 清空已加载列表与分页状态后重新拉取首页。
  void _switchReplyMode(int mode) {
    if (mode == _replyMode || _loadingReplies) return;
    final aid = _detailState.dataOrNull?.aid;
    if (aid == null) return;
    setState(() {
      _replyMode = mode;
      _replies.clear();
      _nextOffset = null;
      _replyEnd = false;
      _replyFailed = false;
    });
    _loadReplies(oid: aid);
  }

  // ─────────────────── 稿件互动（委托至 VideoInteractionMixin）───

  /// 查询当前稿件是否在稍后再看列表。
  Future<void> _loadWatchLaterStatus(int? aid) => loadWatchLaterStatus(aid);

  /// 云端同步稿件互动状态（点赞/投币/收藏/点踩/关注，/x/web-interface/archive/relation）。
  Future<void> _syncVideoRelation({int? aid}) => syncVideoRelation(aid: aid);

  /// 校验登录态并在发生新登录时立即全量拉取云端互动与刷新评论。
  Future<bool> _requireLoginAndSync() async {
    final wasLogin = Accounts.main.isLogin;
    if (!await LoginGuard.requireLogin(context)) return false;
    if (!wasLogin && mounted) {
      final aid = _detailState.dataOrNull?.aid;
      unawaited(_syncVideoRelation(aid: aid));
      _loadWatchLaterStatus(aid);
      if (aid != null) _loadReplies(oid: aid, refresh: true);
    }
    return true;
  }

  /// 更新稿件 stat 计数（乐观更新/回滚共用，[fn] 内直接改写字段）。
  void _adjustStat(void Function(VideoStat stat) fn) {
    final stat = _detailState.dataOrNull?.stat;
    if (stat == null) return;
    setState(() => fn(stat));
  }

  /// （取消）点赞；点赞与点踩互斥，点赞时自动清除点踩态。
  Future<void> _actionLike() => actionLikeVideo();

  /// 长按点赞一键三连：点赞 + 投币×2 + 收藏默认收藏夹。
  Future<void> _actionTriple() => actionTripleVideo();

  /// 投币入口：弹对话框选择数量与是否同时点赞。
  Future<void> _actionCoin() => actionCoinVideo();

  /// （取消）点踩；点踩时自动取消点赞（B 站语义二者互斥）。
  Future<void> _actionDislike() => actionDislikeVideo();

  /// 收藏：弹出收藏夹选择面板。
  Future<void> _actionFav() => actionFavVideo();

  /// 分享：复制视频链接到剪贴板 + 尽力而为上报分享计数。
  Future<void> _actionShare() => actionShareVideo();

  /// 切换稍后再看（对标 BiliPai toggleWatchLater）。
  Future<void> _actionWatchLater() => actionWatchLaterVideo();

  // ─────────────────────────── 作者关注 ───────────────────────────

  /// 查询与稿件作者的关系（/x/relation）。
  Future<void> _checkFollowStatus(int mid) async {
    if (!Accounts.main.isLogin) return;
    final res = await FollowHttp.relation(fid: mid);
    if (!mounted) return;
    if (res case Success(:final response)) {
      final attr = (response['attribute'] as num?)?.toInt() ?? 0;
      // 0: 未关注, 1: 悄悄关注, 2: 已关注, 6: 互相关注
      final followed = attr == 1 || attr == 2 || attr == 6;
      if (isFollowed != followed) {
        setState(() => isFollowed = followed);
      }
    }
  }

  /// 切换作者关注状态。
  Future<void> _toggleFollow() => toggleFollowOwner();

  // ─────────────────────────── 评论点赞与点踩 ───────────────────────────

  /// 统一在主评论与楼中楼缓存中按 rpid 更新评论条目。
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

  /// 切换评论点赞状态（点赞与点踩互斥）。
  Future<void> _toggleLikeReply(ReplyItemModel reply) async {
    final aid = _detailState.dataOrNull?.aid;
    final rpid = reply.rpid;
    if (aid == null || rpid == null) return;
    if (!await _requireLoginAndSync()) return;
    if (!mounted) return;

    final wasLiked = reply.isLiked;
    final wasDisliked = reply.isDisliked;

    // 乐观更新：若已赞则取消（action=0, like-1）；若未赞则点赞（action=1, like+1）。
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
      // 回滚乐观更新。
      _updateReplyInState(
        rpid,
        (r) => r.copyWith(
          like: (r.like ?? 0) + (wasLiked ? 1 : -1),
          action: wasLiked ? 1 : (wasDisliked ? 2 : 0),
        ),
      );
      _toast(errMsg ?? '操作失败');
    }
  }

  /// 切换评论点踩状态（点踩与点赞互斥）。
  Future<void> _toggleDislikeReply(ReplyItemModel reply) async {
    final aid = _detailState.dataOrNull?.aid;
    final rpid = reply.rpid;
    if (aid == null || rpid == null) return;
    if (!await _requireLoginAndSync()) return;
    if (!mounted) return;

    final wasDisliked = reply.isDisliked;
    final wasLiked = reply.isLiked;

    // 乐观更新：若已踩则取消踩（action=0）；若未踩则点踩（action=2），若之前点赞过则赞数-1。
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
      // 回滚乐观更新。
      _updateReplyInState(
        rpid,
        (r) => r.copyWith(
          like: (r.like ?? 0) + (wasLiked ? 1 : 0),
          action: wasDisliked ? 2 : (wasLiked ? 1 : 0),
        ),
      );
      _toast(errMsg ?? '操作失败');
    }
  }

  // ─────────────────────────── 楼中楼 ───────────────────────────

  /// 展开/收起楼中楼回复。
  Future<void> _toggleSubReplies(ReplyItemModel reply) async {
    final rpid = reply.rpid;
    if (rpid == null) return;
    if (_subReplies.containsKey(rpid)) {
      // 已展开 → 收起。
      setState(() {
        _subReplies.remove(rpid);
        _subNextOffset.remove(rpid);
        _subEnd.remove(rpid);
        _subLoading.remove(rpid);
      });
      return;
    }
    // 未展开 → 加载。
    setState(() {
      _subReplies[rpid] = <ReplyItemModel>[];
      _subLoading[rpid] = true;
    });
    await _loadSubReplies(reply);
  }

  Future<void> _loadSubReplies(ReplyItemModel reply) async {
    final aid = _detailState.dataOrNull?.aid;
    final rpid = reply.rpid;
    if (aid == null || rpid == null) return;
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
        _toast('加载回复失败');
      case Loading():
        break;
    }
  }

  // ─────────────────────────── 评论发送 ───────────────────────────

  /// 设置回复目标（点击评论的"回复"按钮时调用）。
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

  /// 清除回复目标（点击输入框旁的取消按钮）。
  void _clearReplyTarget() {
    setState(() {
      _replyRoot = null;
      _replyHint = null;
    });
    _commentCtrl.clear();
  }

  /// 发送评论。
  Future<void> _sendComment() async {
    final message = _commentCtrl.text.trim();
    if (message.isEmpty) return;
    final aid = _detailState.dataOrNull?.aid;
    if (aid == null) return;
    if (!await LoginGuard.requireLogin(context)) return;
    if (!mounted) return;

    setState(() => _sendingComment = true);
    final res = await VideoHttp.replyAdd(
      oid: aid,
      message: message,
      root: _replyRoot,
      parent: _replyRoot,
    );
    if (!mounted) return;
    setState(() => _sendingComment = false);
    switch (res) {
      case Success(:final response):
        if (_replyRoot != null) {
          // 二级回复：插入到楼中楼列表。
          setState(() {
            _subReplies[_replyRoot!]?.add(response);
          });
        } else {
          // 一级评论：插入到列表顶部。
          setState(() {
            _replies.insert(0, response);
          });
        }
        _clearReplyTarget();
        _toast('发送成功');
      case Error(:final errMsg):
        _toast(errMsg ?? '发送失败');
      case Loading():
        break;
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    // 注意：本类另有实例方法 showToast(String)（VideoInteractionMixin 接口），
    // 类内非限定调用会被实例成员遮蔽，故此处必须用库前缀调用顶层 showToast。
    app_messenger.showToast(context, msg, duration: const Duration(seconds: 2));
  }

  // ─────────────────────────── 用户空间跳转 ───────────────────────────

  void _gotoMemberSpace(int? mid) {
    if (mid == null || mid <= 0) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MemberSpacePage(mid: mid),
      ),
    );
  }

  Future<void> _toggleFullscreen() async {
    if (playerController == null) return;
    final next = !_fullscreen;
    setState(() => _fullscreen = next);
    _syncTitleBarBackdrop();
    if (next) {
      await DesktopFullscreen.enter();
    } else {
      await DesktopFullscreen.exit();
    }
  }

  void _toggleInAppFullscreen() {
    if (playerController == null) return;
    setState(() => _inAppFullscreen = !_inAppFullscreen);
    _syncTitleBarBackdrop();
  }

  /// Esc 键固定语义：返回上一级。
  /// 优先退出显示器全屏；其次退出网页全屏；默认布局退出详情页。
  void _handleEscape() {
    SyncTrace.log('DetailPage',
        'escape pressed, fullscreen=$_fullscreen, inAppFullscreen=$_inAppFullscreen');
    if (_fullscreen) {
      setState(() => _fullscreen = false);
      _syncTitleBarBackdrop();
      DesktopFullscreen.exit();
    } else if (_inAppFullscreen) {
      setState(() => _inAppFullscreen = false);
      _syncTitleBarBackdrop();
    } else {
      playerController?.pause();
      playerController?.detachListeners();
      Navigator.pop(context);
    }
  }

  // ─────────────────────────── 布局 ───────────────────────────

  @override
  Widget build(BuildContext context) {
    final String? upName = _detailState.dataOrNull?.owner?.name;
    final isFillWindow = _fullscreen || _inAppFullscreen;
    return Scaffold(
      backgroundColor: isFillWindow ? Colors.black : null,
      body: isFillWindow
          ? Stack(
              children: [
                Positioned.fill(
                  child: PlayerPanel(
                    controller: playerController!,
                    fullscreen: _fullscreen,
                    inAppFullscreen: _inAppFullscreen,
                    onToggleFullscreen: _toggleFullscreen,
                    onToggleInAppFullscreen: _toggleInAppFullscreen,
                    onEscape: _handleEscape,
                  ),
                ),
              ],
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                // 窄屏断点适配：窄于 [kDetailNarrowBreakpoint] 时单列布局，
                // 相关推荐追加到左栏滚动视图尾部（复用 _relatedState）。
                if (constraints.maxWidth < kDetailNarrowBreakpoint) {
                  return _buildLeftColumn(upName, appendRelated: true);
                }
                return Row(
                  children: [
                    Expanded(flex: 65, child: _buildLeftColumn(upName)),
                    Expanded(flex: 35, child: _buildRightColumn()),
                  ],
                );
              },
            ),
    );
  }

  // ─────────────────────────── 左栏 ───────────────────────────

  /// 左栏：CustomScrollView + VideoHeader(pin 播放器) + slivers(信息/简介/评论)。
  /// 顶部叠加渐变工具栏（基于 _scrollRatio 显隐）。
  /// [appendRelated] 为 true（窄屏单列布局）时尾部追加相关推荐 slivers。
  ///
  /// 静态与动态分层控制（DeepSeek 规范）：
  /// 播放器外壳（优先承接封面转场）、弹幕输入条、点赞/投币操作行及 Tab 导航结构
  /// 均为编译期静态控件，始终以最终样式常驻渲染；
  /// 仅在未就绪时对标题行、UP主资料及未到达的评论数据展示局部 Shimmer 骨架占位。
  Widget _buildLeftColumn(String? upName, {bool appendRelated = false}) {
    if (_detailState case Error(:final errMsg, :final code)) {
      return _buildErrorLayout(upName, code, errMsg, narrow: appendRelated);
    }

    final response = _detailState.dataOrNull;
    // 演示模式：分区一律以骨架（加载态）显示。
    final isLoading = _detailState is Loading || Pref.demoMode;

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final maxExtent = constraints.maxWidth * 9 / 16;
                  final minExtent = (maxExtent * 0.56).clamp(180.0, 240.0);
                  return CustomScrollView(
                    controller: scrollController,
                    slivers: [
                      VideoHeader(
                        maxExtent: maxExtent,
                        minExtent: minExtent,
                        onScrollRatioChange: (r) {
                          _handleCollapseAutoPause(r);
                          _scrollRatio.value = r;
                        },
                        child: _buildPlayerContent(response),
                      ),
                      // 弹幕发送栏：紧贴视频下方，宽度与视频一致
                      //（Sliver 横向撑满左栏 = 播放器宽度）。
                      if (playerController != null)
                        SliverToBoxAdapter(
                          child: SendDanmakuPanel(
                            controller: playerController!,
                            inline: true,
                          ),
                        ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(
                          Style.safeSpace,
                          Style.sm,
                          Style.cardSpace,
                          Style.xxl * 2,
                        ),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              // 演示模式：本地演示分区（灰条占位 + 随机互动数据）。
                              if (Pref.demoMode) {
                                if (index == 0) return _buildInfoSectionDemo();
                                if (index == 1) return _buildDescSectionDemo();
                                if (index == 2) return _buildTagsSectionDemo();
                                return _buildReplyTileDemo(index - 3);
                              }
                              if (isLoading) {
                                if (index == 0) {
                                  return _buildInfoSectionSkeleton();
                                }
                                if (index == 1) {
                                  return _buildDescSectionSkeleton();
                                }
                                if (!appendRelated) {
                                  return const SizedBox.shrink();
                                }
                                if (index == 2) {
                                  return _buildReplyHeaderSkeleton();
                                }
                                return _buildReplyTileSkeleton();
                              }
                              // 0: 信息, 1: 简介, 2: 标签(可选)。
                              // 宽屏（对标 BiliPai TabletVideoLayout）评论区
                              // 迁入右栏 Tab，仅窄屏单列布局在左栏内联：
                              // 其后追加 评论头 + 评论列表 + 尾部。
                              final hasTags = _tags.isNotEmpty;
                              final baseCount = hasTags ? 3 : 2;
                              if (index == 0) {
                                return _buildInfoSection(response!);
                              }
                              if (index == 1) {
                                return _buildDescSection(response!);
                              }
                              if (hasTags && index == 2) {
                                return _buildTagsSection();
                              }
                              if (!appendRelated) {
                                return const SizedBox.shrink();
                              }
                              final replyHeaderIndex = baseCount;
                              if (index == replyHeaderIndex) {
                                return _buildReplyHeader(response!);
                              }
                              final replyIndex =
                                  index - replyHeaderIndex - 1;
                              if (replyIndex < _replies.length) {
                                if (replyIndex == _replies.length - 1) {
                                  _maybeLoadMoreReplies();
                                }
                                return _buildReplyTile(_replies[replyIndex]);
                              }
                              return _buildReplyTrailer();
                            },
                            childCount: Pref.demoMode
                                ? (appendRelated ? 11 : 3)
                                : isLoading
                                    ? (appendRelated ? 6 : 2)
                                    : (appendRelated
                                        ? (_tags.isNotEmpty ? 3 : 2) +
                                            _replies.length +
                                            1
                                        : (_tags.isNotEmpty ? 3 : 2)),
                          ),
                        ),
                      ),
                      // 窄屏单列布局：相关推荐追加在尾部。
                      if (appendRelated) ..._buildRelatedSlivers(),
                    ],
                  );
                },
              ),
              _buildGradientTopBar(upName),
            ],
          ),
        ),
        // 评论输入栏：窄屏单列布局固定在左栏底部；
        // 宽屏布局评论区在右栏 Tab，输入栏随之迁入右栏
        //（见 _buildRightColumn）。
        if (appendRelated)
          _buildCommentInputBar(
            enabled: !isLoading,
            disabledHint: isLoading
                ? (Pref.demoMode ? '演示模式' : '正在加载视频...')
                : null,
          ),
      ],
    );
  }

  /// 稿件信息错误态的左栏布局（参照 BiliPai VideoDetailScreenStateHolder：
  /// 错误仅占据播放区域，下方保留简介占位卡片，顶栏返回与右栏推荐不受影响）。
  Widget _buildErrorLayout(
    String? upName,
    int? code,
    String? errMsg, {
    bool narrow = false,
  }) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final maxExtent = constraints.maxWidth * 9 / 16;
                  final minExtent = (maxExtent * 0.56).clamp(180.0, 240.0);
                  return CustomScrollView(
                    controller: scrollController,
                    slivers: [
                      VideoHeader(
                        maxExtent: maxExtent,
                        minExtent: minExtent,
                        onScrollRatioChange: (r) {
                          _handleCollapseAutoPause(r);
                          _scrollRatio.value = r;
                        },
                        child: _buildPlayerError(code, errMsg),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(
                          Style.safeSpace,
                          Style.sm,
                          Style.cardSpace,
                          Style.xxl * 2,
                        ),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            _buildDetailErrorCard(code, errMsg),
                          ]),
                        ),
                      ),
                    ],
                  );
                },
              ),
              _buildGradientTopBar(upName),
            ],
          ),
        ),
        // 错误态无 aid：评论发送不可用，输入栏置灰展示。
        // 宽屏布局评论区在右栏，错误态右栏不展示输入栏（见 _buildRightColumn）。
        if (narrow) _buildCommentInputBar(enabled: false),
      ],
    );
  }

  /// 播放区域错误 UI（参照 BiliPai `VideoPlaybackUiState.Error` 的播放器内
  /// 错误展示：图标 + 友好文案 + 重试按钮，仅占据视频区域）。
  Widget _buildPlayerError(int? code, String? errMsg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Style.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.videocam_off_outlined,
              size: 44,
              color: Colors.white54,
            ),
            const SizedBox(height: Style.md),
            Text(
              _friendlyVideoError(code, errMsg),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.white70),
            ),
            const SizedBox(height: Style.lg),
            FilledButton.tonal(
              onPressed: _loadDetail,
              child: const Text('点击重试'),
            ),
          ],
        ),
      ),
    );
  }

  /// 错误态的简介占位卡片：展示 bvid 与错误原因，说明评论区不可用。
  Widget _buildDetailErrorCard(int? code, String? errMsg) {
    final theme = Theme.of(context);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.bvid,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: Style.sm),
          Text(
            _friendlyVideoError(code, errMsg),
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Style.sm),
          Text(
            '稿件信息加载失败，评论与互动暂不可用',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  /// 参照 BiliPai 的视频错误分类（VideoLoadError.fromApiCode / classifyPlayUrlError）：
  /// 已知错误码映射为用户友好文案，其余展示接口原始 message。
  static String _friendlyVideoError(int? code, String? errMsg) {
    return switch (code) {
      -404 => '视频不存在或已被删除',
      62002 => '稿件不可见',
      62004 => '稿件审核中，暂不可播放',
      62012 => '该稿件仅UP主自己可见',
      _ => errMsg ?? '视频信息加载失败',
    };
  }

  /// 渐变顶栏：_scrollRatio=0 透明（覆盖在播放器上），=1 不透明（显示标题）。
  Widget _buildGradientTopBar(String? upName, {bool forceOpaque = false}) {
    return ValueListenableBuilder<double>(
      valueListenable: _scrollRatio,
      builder: (context, scrollRatio, _) {
        final theme = Theme.of(context);
        final opacity = forceOpaque ? 1.0 : scrollRatio.clamp(0.0, 1.0);
        final overVideo = opacity < 0.5;
        // 半透明容器对比度策略（ThemeContrastPolicy）：顶栏拍平到页面背景后，
        // 为标题/返回箭头选出达标可读色（覆盖在播放器上时仍用白色）。
        final barContrast = resolveAccessibleContainerColors(
          containerColor: theme.scaffoldBackgroundColor
              .withValues(alpha: opacity * 0.95),
          contentColor: theme.colorScheme.onSurface,
          backgroundColor: theme.scaffoldBackgroundColor,
          fallbackContentColors: [
            theme.colorScheme.onInverseSurface,
            theme.colorScheme.scrim,
          ],
        );

        final barContent = SizedBox(
          height: kToolbarHeight,
          child: Row(
            children: [
              AppBackButton(
                color: overVideo ? Colors.white : barContrast.contentColor,
                shadows: overVideo ? ContrastStyle.glyphShadows : null,
                size: 24,
                onBeforePop: () {
                  SyncTrace.log('DetailPage', 'back button pressed');
                  playerController?.pause();
                  playerController?.detachListeners();
                },
              ),
              Expanded(
                child: opacity > 0.05
                    ? Opacity(
                        opacity: opacity,
                        child: Text(
                          (Pref.demoMode || !(upName?.isNotEmpty ?? false))
                              ? '视频详情'
                              : upName!,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: barContrast.contentColor,
                            shadows:
                                overVideo ? ContrastStyle.glyphShadows : null,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
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
                    height: kToolbarHeight,
                    decoration: BoxDecoration(
                      color: theme.scaffoldBackgroundColor
                          .withValues(alpha: 0.95),
                      border: Border(
                        bottom: BorderSide(
                          color: theme.colorScheme.outlineVariant
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
            ? Colors.black.withValues(
                alpha: (0.45 * (1.0 - opacity) + 0.70 * opacity).clamp(0.0, 1.0))
            : theme.scaffoldBackgroundColor
                .withValues(alpha: (opacity * 0.95).clamp(0.0, 1.0));

        return Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Container(
              height: kToolbarHeight,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.6, 1.0],
                  colors: [
                    topColor,
                    topColor.withValues(alpha: topColor.a * 0.4),
                    Colors.transparent,
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

  /// 播放器内容（Phase 7.6.4：封面加 Hero 共享元素转场）。
  /// VideoHeader 负责裁切/圆角/尺寸，此处只返回原始内容。
  Widget _buildPlayerContent(VideoDetailData? data) {
    return _buildPlayerContentInner(data);
  }

  Widget _buildPlayerContentInner(VideoDetailData? data) {
    // 演示模式：灰色静态画面 + 播放控制栏（布局对齐正常模式；不加载视频）。
    if (Pref.demoMode) {
      return _buildDemoPlayerChrome();
    }
    final controller = playerController;
    if (controller == null) {
      final coverWidget = NetworkImgLayer(
        src: widget.cover ?? data?.pic,
        width: double.infinity,
        height: double.infinity,
        borderRadius: BorderRadius.zero,
      );
      if (widget.heroTag != null) {
        return Hero(
          tag: widget.heroTag!,
          child: coverWidget,
        );
      }
      return coverWidget;
    }
    return PlayerPanel(
      controller: controller,
      cover: widget.cover ?? data?.pic,
      fullscreen: _fullscreen,
      inAppFullscreen: _inAppFullscreen,
      onToggleFullscreen: _toggleFullscreen,
      onToggleInAppFullscreen: _toggleInAppFullscreen,
      onEscape: _handleEscape,
    );
  }

  /// 标题 + 数据行 + UP 行。
  Widget _buildInfoSection(VideoDetailData data) {
    final theme = Theme.of(context);
    final stat = data.stat;
    final owner = data.owner;
    final grayStyle = TextStyle(
      fontSize: 12,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.title ?? widget.bvid,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: Style.sm),
          Row(
            spacing: Style.md,
            children: [
              Icon(
                AppIcons.viewCount(),
                size: 15,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              Text(NumUtils.formatNum(stat?.view), style: grayStyle),
              Icon(
                AppIcons.danmakuCount(),
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              Text(NumUtils.formatNum(stat?.danmaku), style: grayStyle),
              Icon(
                AppIcons.duration(),
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              Text(
                DurationUtils.formatDuration(data.duration),
                style: grayStyle,
              ),
              if (data.pubdate != null)
                Text(_formatDate(data.pubdate), style: grayStyle),
            ],
          ),
          const SizedBox(height: Style.md),
          Row(
            children: [
              GestureDetector(
                onTap: () => _gotoMemberSpace(owner?.mid),
                child: ClipOval(
                  child: NetworkImgLayer(
                    src: owner?.face,
                    width: 40,
                    height: 40,
                    type: 'avatar',
                  ),
                ),
              ),
              const SizedBox(width: Style.md),
              Expanded(
                child: GestureDetector(
                  onTap: () => _gotoMemberSpace(owner?.mid),
                  child: Text(
                    owner?.name ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              // 关注按钮：未登录/未关注/已关注，支持 Hover 状态切换与取关
              if (owner?.mid != null &&
                  !(Accounts.main.isLogin &&
                      Accounts.main.mid == owner!.mid))
                _AuthorFollowButton(
                  isFollowed: isFollowed,
                  isLoading: isFollowUpdating,
                  onPressed: _toggleFollow,
                ),
            ],
          ),
          const Divider(height: Style.xl),
          // 互动行：点赞/投币/收藏/点踩/分享/稍后再看
          //（对标 BiliPai ActionButtonsRow）。
          VideoActionRow(
            stat: stat,
            hasLike: hasLike,
            hasDislike: hasDislike,
            coinNum: coinNum,
            hasFav: hasFav,
            inWatchLater: inWatchLater,
            onLike: _actionLike,
            onTriple: _actionTriple,
            onCoin: _actionCoin,
            onDislike: _actionDislike,
            onFav: _actionFav,
            onShare: _actionShare,
            onWatchLater: _actionWatchLater,
          ),
        ],
      ),
    );
  }

  /// 简介卡片：默认 3 行，可展开/收起。
  Widget _buildDescSection(VideoDetailData data) {
    final theme = Theme.of(context);
    final desc = (data.desc ?? '').trim();
    return _card(
      margin: const EdgeInsets.only(top: Style.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: desc.isEmpty
                ? null
                : () => setState(() => _descExpanded = !_descExpanded),
            borderRadius: BorderRadius.circular(Style.radiusSm),
            child: Text(
              desc.isEmpty ? '简介为空' : desc,
              maxLines: _descExpanded ? null : 3,
              overflow: _descExpanded
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (desc.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () =>
                    setState(() => _descExpanded = !_descExpanded),
                child: Text(_descExpanded ? '收起' : '展开'),
              ),
            ),
        ],
      ),
    );
  }

  /// 稿件标签行（对标 BiliPai VideoTagsRow：最多取 10 个，
  /// 14dp 圆角 chip + surfaceVariant 底色，点击按标签名搜索）。
  Widget _buildTagsSection() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Style.md),
      child: Wrap(
        spacing: Style.sm,
        runSpacing: Style.sm,
        children: [
          for (final tag in _tags.take(10))
            Material(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.8,
              ),
              borderRadius: BorderRadius.circular(Style.radiusLg),
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        SearchResultPage(keyword: tag.tagName ?? ''),
                  ),
                ),
                borderRadius: BorderRadius.circular(Style.radiusLg),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Text(
                    tag.tagName ?? '',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReplyHeader(VideoDetailData data) {
    final count = data.stat?.reply;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Style.xs,
        Style.lg,
        Style.xs,
        Style.sm,
      ),
      child: Row(
        children: [
          Text(
            count != null ? '评论 ${NumUtils.formatNum(count)}' : '评论',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          // 窄屏内联评论区同样支持 最热/最新排序切换。
          _buildCommentSortRow(),
        ],
      ),
    );
  }

  Widget _buildReplyTile(ReplyItemModel reply) {
    final theme = Theme.of(context);
    final member = reply.member;
    final upMid = _detailState.dataOrNull?.owner?.mid;
    final isUp = upMid != null && (reply.mid == upMid || member?.mid == upMid);
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
                                color: isUp
                                    ? biliPink
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                        if (isUp)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: biliPink.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: biliPink.withValues(alpha: 0.35),
                                width: 0.6,
                              ),
                            ),
                            child: const Text(
                              'UP',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: biliPink,
                                height: 1.1,
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
                    ReplyContentView(
                      content: reply.content,
                      textStyle: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 14.5,
                        height: 1.55,
                        color: theme.colorScheme.onSurface,
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
                              Icon(
                                AppIcons.like(active: reply.isLiked),
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
                          onTap: () => _toggleDislikeReply(reply),
                          child: Icon(
                            AppIcons.dislike(active: reply.isDisliked),
                            size: 15,
                            color: reply.isDisliked
                                ? biliPink
                                : theme.colorScheme.onSurfaceVariant,
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
                              Icon(
                                AppIcons.reply(),
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
                                      ? AppIcons.chevronUp()
                                      : AppIcons.expandMore(),
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
                    _buildSubReplyTile(subReplies[i], reply, upMid: upMid),
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
                        icon: AppIcon(AppIcons.expandMore(), size: 16),
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

  /// 楼中楼单条回复（两行独立展示：第1行头像/名称/身份/时间，第2行独立正文，第3行操作）。
  Widget _buildSubReplyTile(
    ReplyItemModel sub,
    ReplyItemModel root, {
    int? upMid,
  }) {
    final theme = Theme.of(context);
    final isSubUp =
        upMid != null && (sub.mid == upMid || sub.member?.mid == upMid);
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
                            color:
                                isSubUp ? biliPink : theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                    if (isSubUp)
                      Container(
                        margin: const EdgeInsets.only(left: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: biliPink.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: biliPink.withValues(alpha: 0.4),
                            width: 0.5,
                          ),
                        ),
                        child: const Text(
                          'UP',
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w600,
                            color: biliPink,
                            height: 1.1,
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
          // 第 2 行：回复正文（独立行展示，字体加大更清晰，行高宽松舒适）
          Padding(
            padding: const EdgeInsets.only(left: 36, top: 4, bottom: 4),
            child: ReplyContentView(
              content: sub.content,
              textStyle: theme.textTheme.bodyMedium?.copyWith(
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
                  onTap: () => _toggleLikeReply(sub),
                  child: Row(
                    spacing: 3,
                    children: [
                      Icon(
                        AppIcons.like(active: sub.isLiked),
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
                  onTap: () => _toggleDislikeReply(sub),
                  child: Icon(
                    AppIcons.dislike(active: sub.isDisliked),
                    size: 13,
                    color: sub.isDisliked
                        ? biliPink
                        : theme.colorScheme.onSurfaceVariant,
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
                      Icon(
                        AppIcons.reply(),
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

  /// 评论输入栏（固定在左栏底部，默认给当前稿件发布一级评论；
  /// 水平内边距与评论区 SliverPadding 一致，宽度对齐评论区容器）。
  /// [enabled]=false 时置灰（稿件信息加载中或失败态，无 aid 不可发评论）。
  Widget _buildCommentInputBar({bool enabled = true, String? disabledHint}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        Style.safeSpace,
        Style.xs,
        Style.cardSpace,
        Style.xs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
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
            // 官方表情面板按钮（输入框左侧，直播互动条同款）
            OfficialEmotePickerButton(
              controller: _commentCtrl,
              focusNode: _commentFocus,
              enabled: enabled,
            ),
            const SizedBox(width: Style.sm),
            Expanded(
              child: TextField(
                controller: _commentCtrl,
                focusNode: _commentFocus,
                enabled: enabled,
                onTap: () async {
                  // 点击输入框时检查登录态。
                  if (!await LoginGuard.requireLogin(context)) return;
                },
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: Style.md,
                    vertical: Style.sm,
                  ),
                  hintText: enabled
                      ? (_replyHint ?? '发一条友善的评论吧~')
                      : (disabledHint ?? '稿件不可用，暂无法评论'),
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
                          icon: AppIcon(AppIcons.clear(), size: 16),
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

  /// 评论列表尾部：加载中 spinner / 失败重试 / 没有更多。
  Widget _buildReplyTrailer() {
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
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    if (_replyEnd) {
      final theme = Theme.of(context);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Style.lg),
        child: Center(
          child: Text(
            '没有更多评论',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.outline,
            ),
          ),
        ),
      );
    }
    _maybeLoadMoreReplies();
    return const SizedBox.shrink();
  }

  // ─────────────────────────── 右栏（相关视频） ───────────────────────────

  /// 右栏（对标 BiliPai TabletSecondaryContent）：评论 (N) / 相关推荐双 Tab。
  /// 评论 Tab 含 最热/最新排序行 + 评论列表 + 底部输入栏；
  /// 稿件信息未就绪（Loading/Error）时评论 Tab 展示占位/不可用提示。
  Widget _buildRightColumn() {
    final theme = Theme.of(context);
    final replyCount = _detailState.dataOrNull?.stat?.reply;
    return Column(
      children: [
        TabBar(
          controller: _rightTabCtrl,
          labelColor: theme.colorScheme.onSurface,
          unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
          indicatorColor: theme.colorScheme.primary,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: theme.colorScheme.outlineVariant.withValues(
            alpha: 0.3,
          ),
          tabs: [
            Tab(
              text: (Pref.demoMode || replyCount == null)
                  ? '评论'
                  : '评论 ${NumUtils.formatNum(replyCount)}',
            ),
            const Tab(text: '相关推荐'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _rightTabCtrl,
            children: [_buildCommentTab(), _buildRelatedTab()],
          ),
        ),
      ],
    );
  }

  /// 评论 Tab（对标 BiliPai 平板评论页）：
  /// 最热/最新排序行 + 评论列表 + 底部输入栏。
  /// 稿件信息未就绪（无 aid）时评论不可用，展示占位提示。
  Widget _buildCommentTab() {
    if (_detailState.dataOrNull == null || Pref.demoMode) {
      if (Pref.demoMode || _detailState is Loading) {
        return Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(Style.sm, Style.xs, Style.sm, 0),
              child: _buildCommentSortRow(),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(
                  Style.cardSpace,
                  Style.xs,
                  Style.safeSpace,
                  Style.md,
                ),
                itemCount: 4,
                itemBuilder: (_, _) => _buildReplyTileSkeleton(),
              ),
            ),
            _buildCommentInputBar(
              enabled: false,
              disabledHint: Pref.demoMode ? '演示模式' : '正在加载评论...',
            ),
          ],
        );
      }
      return const AppEmptyState(
        title: '评论区不可用',
        subtitle: '稿件信息加载失败',
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Style.sm, Style.xs, Style.sm, 0),
          child: _buildCommentSortRow(),
        ),
        Expanded(child: _buildReplyListView()),
        _buildCommentInputBar(),
      ],
    );
  }

  /// 评论排序行（对标 BiliPai CommentSortHeader）：
  /// 最热(3) / 最新(2) 文本切换，选中项加粗强调。
  Widget _buildCommentSortRow() {
    final theme = Theme.of(context);
    Widget sortBtn(String label, int mode) {
      final selected = _replyMode == mode;
      return TextButton(
        onPressed: () => _switchReplyMode(mode),
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
    return Row(children: [sortBtn('最热', 3), sortBtn('最新', 2)]);
  }

  /// 评论列表（宽屏右栏 Tab 用；窄屏单列布局用 sliver 版）。
  /// 尾部统一交给 [_buildReplyTrailer]（spinner/重试/空态/到底）。
  Widget _buildReplyListView() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        Style.cardSpace,
        Style.xs,
        Style.safeSpace,
        Style.md,
      ),
      itemCount: _replies.length + 1,
      itemBuilder: (context, index) {
        if (index == _replies.length) return _buildReplyTrailer();
        if (index == _replies.length - 1) _maybeLoadMoreReplies();
        return _buildReplyTile(_replies[index]);
      },
    );
  }

  /// 相关推荐 Tab（原右栏列表，Phase 7.6.5 的 [VideoCardH] 卡片不变）。
  Widget _buildRelatedTab() {
    return Padding(
      padding: const EdgeInsets.only(top: Style.sm),
      child: _buildRelatedBody(),
    );
  }

  /// 相关推荐列表主体（宽栏 Tab 与降级右栏共用）。
  Widget _buildRelatedBody() {
    // 演示模式：本地生成的横版占位卡片（可点击进入演示详情）。
    if (Pref.demoMode) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          Style.cardSpace,
          0,
          Style.safeSpace,
          Style.xxl * 2,
        ),
        itemCount: 6,
        separatorBuilder: (_, _) => const SizedBox(height: Style.sm),
        itemBuilder: (context, index) => DemoVideoCardH(
          seed: index,
          onTap: () => _openDemoVideo(context, index),
        ),
      );
    }
    return switch (_relatedState) {
      Loading() => _buildRightSkeleton(),
      Error(:final errMsg) => _buildError(errMsg, _loadRelated),
      Success(:final response) => response.isEmpty
          ? const AppEmptyState(
              title: '暂无相关推荐',
              subtitle: '换个视频看看吧',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                Style.cardSpace,
                0,
                Style.safeSpace,
                Style.xxl * 2,
              ),
              itemCount: response.length,
              separatorBuilder: (_, _) => const SizedBox(height: Style.sm),
              itemBuilder: (context, index) =>
                  _buildRelatedTile(response[index]),
            ),
    };
  }

  /// 相关推荐卡片（宽栏列表与窄屏 sliver 段落共用）。
  Widget _buildRelatedTile(RelatedVideoItem item) {
    final bvid = item.bvid;
    final heroTag = bvid != null ? 'related_$bvid' : null;
    return VideoCardH(
      videoItem: item,
      heroTag: heroTag,
      coverWidth: 150,
      showStat: false,
      onTap: bvid == null
          ? null
          : () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VideoDetailPage(
                    bvid: bvid,
                    cover: item.pic,
                    heroTag: heroTag,
                  ),
                ),
              );
            },
    );
  }

  /// 相关推荐 sliver 段落（窄屏单列布局追加在左栏滚动视图尾部，
  /// 数据复用 [_relatedState]，不重新请求）。
  List<Widget> _buildRelatedSlivers() {
    final theme = Theme.of(context);
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          Style.safeSpace,
          Style.lg,
          Style.safeSpace,
          Style.sm,
        ),
        sliver: SliverToBoxAdapter(
          child: Text(
            '相关推荐',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      switch (_relatedState) {
        Loading() => SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: Style.safeSpace),
            sliver: SliverList.separated(
              itemCount: 6,
              separatorBuilder: (_, _) => const SizedBox(height: Style.sm),
              itemBuilder: (context, index) => _buildRelatedSkeletonItem(),
            ),
          ),
        Error(:final errMsg) => SliverToBoxAdapter(
            child: SizedBox(
              height: 240,
              child: _buildError(errMsg, _loadRelated),
            ),
          ),
        Success(:final response) => response.isEmpty
            ? const SliverToBoxAdapter(
                child: AppEmptyState(
                  title: '暂无相关推荐',
                  subtitle: '换个视频看看吧',
                ),
              )
            : SliverPadding(
                padding:
                    const EdgeInsets.symmetric(horizontal: Style.safeSpace),
                sliver: SliverList.separated(
                  itemCount: response.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Style.sm),
                  itemBuilder: (context, index) =>
                      _buildRelatedTile(response[index]),
                ),
              ),
      },
      // 尾部留白，与左栏原有底部间距对齐。
      const SliverToBoxAdapter(child: SizedBox(height: Style.xxl * 2)),
    ];
  }

  /// 相关推荐骨架单项（宽栏 [_buildRightSkeleton] 与窄屏 sliver 共用）。
  Widget _buildRelatedSkeletonItem() {
    return const VideoCardHSkeleton(
      coverWidth: 150,
      inCard: true,
    );
  }

  // ─────────────────────────── 局部骨架屏 / 错误态 ───────────────────────────

  /// 演示模式：灰色静态画面 + 播放控制栏（对齐正常模式播放器布局）。
  Widget _buildDemoPlayerChrome() {
    const glyphShadow = ContrastStyle.glyphShadows;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        // 中央播放按钮（对齐暂停态）。
        Center(
          child: Icon(
            AppIcons.play(active: true),
            size: 56,
            color: Colors.white,
            shadows: glyphShadow,
          ),
        ),
        // 底部控制栏（渐变 + 进度条 + 按钮行，对齐正常模式）。
        Align(
          alignment: Alignment.bottomCenter,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                stops: [0.0, 0.55, 1.0],
                colors: [
                  Color(0x73000000),
                  Color(0x28000000),
                  Colors.transparent,
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: 14.0, bottom: Style.xs),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 第一行：进度条（静止于起点）。
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Style.sm),
                    child: Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Divider(
                            height: 3,
                            thickness: 3,
                            color: Color(0x47FFFFFF),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ),
                  ),
                  // 第二行：控制按钮（对齐正常模式左右分区）。
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Style.sm),
                    child: Row(
                      children: [
                        Icon(
                          AppIcons.play(active: true),
                          size: 20,
                          color: Colors.white,
                          shadows: glyphShadow,
                        ),
                        const SizedBox(width: Style.sm),
                        const Text(
                          '00:00 / 00:00',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            shadows: glyphShadow,
                          ),
                        ),
                        const SizedBox(width: Style.md),
                        Icon(
                          AppIcons.danmaku(active: true),
                          size: 18,
                          color: Colors.white,
                          shadows: glyphShadow,
                        ),
                        const Spacer(),
                        for (final icon in [
                          AppIcons.volumeDown(),
                          AppIcons.lockOutline(),
                          AppIcons.pip(),
                          AppIcons.fullscreen(),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(left: Style.md),
                            child: Icon(
                              icon,
                              size: 18,
                              color: Colors.white,
                              shadows: glyphShadow,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 演示模式：打开本地演示视频详情（不拉取云端数据）。
  void _openDemoVideo(BuildContext context, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoDetailPage(bvid: 'BV1demo$index'),
      ),
    );
  }

  /// 演示模式：信息区 —— 标题/UP 灰色占位，互动行使用随机数据（可双击编辑）。
  Widget _buildInfoSectionDemo() {
    final bvid = widget.bvid;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonLine(width: double.infinity, height: 18),
          const SizedBox(height: 6),
          const SkeletonLine(width: 220, height: 18),
          const SizedBox(height: Style.sm),
          Row(
            children: [
              const SkeletonCircle(size: 40),
              const SizedBox(width: Style.md),
              Expanded(
                child: Row(
                  children: [
                    AppIcon(
                      AppIcons.profile(),
                      size: 16,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      kDemoDisplayName,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Style.radiusSm),
                  ),
                ),
                onPressed: () {},
                icon: Icon(AppIcons.add(), size: 16),
                label: Text(
                  DemoOverrides.count('demo.followbtn.$bvid', min: 0, max: 1) ==
                          1
                      ? '已关注'
                      : '关注',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            ],
          ),
          const Divider(height: Style.xl),
          VideoActionRow(
            stat: null,
            hasLike:
                DemoOverrides.count('demo.like.$bvid', min: 0, max: 1) == 1,
            hasDislike: false,
            coinNum: DemoOverrides.count('demo.coin.$bvid', min: 0, max: 3),
            hasFav: DemoOverrides.count('demo.fav.$bvid', min: 0, max: 1) == 1,
            inWatchLater: false,
            onLike: () {},
            onTriple: () {},
            onCoin: () {},
            onDislike: () {},
            onFav: () {},
            onShare: () {},
            onWatchLater: () {},
          ),
        ],
      ),
    );
  }

  /// 演示模式：简介区 —— 灰色静态占位。
  Widget _buildDescSectionDemo() {
    return _card(
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonLine(width: 80, height: 14),
          SizedBox(height: Style.sm),
          SkeletonLine(width: double.infinity, height: 12),
          SizedBox(height: 6),
          SkeletonLine(width: double.infinity, height: 12),
          SizedBox(height: 6),
          SkeletonLine(width: 240, height: 12),
        ],
      ),
    );
  }

  /// 演示模式：标签区 —— 灰色胶囊占位。
  Widget _buildTagsSectionDemo() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Style.sm),
      child: Wrap(
        spacing: Style.sm,
        runSpacing: Style.sm,
        children: List.generate(
          4,
          (i) => const SkeletonBox(
            width: 64,
            height: 24,
            borderRadius: BorderRadius.all(Radius.circular(100)),
          ),
        ),
      ),
    );
  }

  /// 演示模式：评论条目 —— 文本灰色占位，点赞数随机（双击可编辑），保留互动按钮。
  Widget _buildReplyTileDemo(int index) {
    final bvid = widget.bvid;
    final outline = Theme.of(context).colorScheme.outline;
    return _card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonCircle(size: 38),
          const SizedBox(width: Style.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonLine(width: 90, height: 13),
                const SizedBox(height: 8),
                const SkeletonLine(width: double.infinity, height: 12),
                const SizedBox(height: 6),
                const SkeletonLine(width: 200, height: 12),
                const SizedBox(height: 8),
                Row(
                  children: [
                    InkWell(
                      onTap: () {},
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: AppIcon(
                          AppIcons.like(),
                          size: 14,
                          color: outline,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    DemoInlineEditNumber(
                      overrideKey: 'demo.reply.$bvid.$index.like',
                      value: DemoOverrides.count(
                        'demo.reply.$bvid.$index.like',
                        min: 10,
                        max: 99999,
                      ),
                      builder: (context, v) => Text(
                        NumUtils.formatNum(v?.toInt()),
                        style: TextStyle(fontSize: 11, color: outline),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Padding(
                      padding: const EdgeInsets.all(2),
                      child: AppIcon(
                        AppIcons.reply(),
                        size: 14,
                        color: outline,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '回复',
                      style: TextStyle(fontSize: 11, color: outline),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 视频信息区局部骨架：卡片外壳、关注按钮与六键互动行以最终静态样式常驻，
  /// 仅标题文本、数据行与 UP 资料展示 Shimmer 占位。
  Widget _buildInfoSectionSkeleton() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Skeleton(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLine(width: double.infinity, height: 18),
                SizedBox(height: 6),
                SkeletonLine(width: 220, height: 18),
              ],
            ),
          ),
          const SizedBox(height: Style.sm),
          const Skeleton(
            child: Row(
              children: [
                SkeletonLine(width: 44, height: 12),
                SizedBox(width: Style.md),
                SkeletonLine(width: 44, height: 12),
                SizedBox(width: Style.md),
                SkeletonLine(width: 44, height: 12),
              ],
            ),
          ),
          const SizedBox(height: Style.md),
          Row(
            children: [
              const Skeleton(child: SkeletonCircle(size: 40)),
              const SizedBox(width: Style.md),
              const Expanded(
                child: Skeleton(
                  child: SkeletonLine(width: 100, height: 14),
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Style.radiusSm),
                  ),
                ),
                onPressed: null,
                icon: Icon(AppIcons.add(), size: 16),
                label: const Text('关注', style: TextStyle(fontSize: 12.5)),
              ),
            ],
          ),
          const Divider(height: Style.xl),
          VideoActionRow(
            stat: null,
            hasLike: false,
            hasDislike: false,
            coinNum: 0,
            hasFav: false,
            inWatchLater: null,
            onLike: () {},
            onTriple: () {},
            onCoin: () {},
            onDislike: () {},
            onFav: () {},
            onShare: () {},
            onWatchLater: () {},
          ),
        ],
      ),
    );
  }

  /// 简介区局部骨架：卡片容器常驻，仅内部文本呈现 3 行骨架占位。
  Widget _buildDescSectionSkeleton() {
    return _card(
      margin: const EdgeInsets.only(top: Style.md),
      child: const Skeleton(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonLine(width: double.infinity, height: 13),
            SizedBox(height: 6),
            SkeletonLine(width: 260, height: 13),
            SizedBox(height: 6),
            SkeletonLine(width: 180, height: 13),
          ],
        ),
      ),
    );
  }

  /// 评论区分组标题骨架：常驻评论标题与最热/最新排序切换按钮。
  Widget _buildReplyHeaderSkeleton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Style.xs,
        Style.lg,
        Style.xs,
        Style.sm,
      ),
      child: Row(
        children: [
          Text(
            '评论',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          _buildCommentSortRow(),
        ],
      ),
    );
  }

  /// 单项评论局部骨架：卡片容器常驻，仅头像与评论文本行显示 Shimmer 动画。
  Widget _buildReplyTileSkeleton() {
    return _card(
      margin: const EdgeInsets.only(top: Style.sm),
      padding: const EdgeInsets.all(Style.md),
      child: const Skeleton(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonCircle(size: 38),
            SizedBox(width: Style.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonLine(width: 90, height: 14),
                  SizedBox(height: 8),
                  SkeletonLine(width: double.infinity, height: 13),
                  SizedBox(height: 6),
                  SkeletonLine(width: 180, height: 13),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRightSkeleton() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        Style.cardSpace,
        0,
        Style.safeSpace,
        Style.xxl * 2,
      ),
      itemCount: 6,
      separatorBuilder: (_, _) => const SizedBox(height: Style.sm),
      itemBuilder: (context, index) => _buildRelatedSkeletonItem(),
    );
  }

  Widget _buildError(String? errMsg, VoidCallback onRetry) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: Style.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Style.xl),
            child: Text(
              errMsg ?? '加载失败',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: Style.xl),
          FilledButton.tonal(
            onPressed: onRetry,
            child: const Text('点击重试'),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── 工具 ───────────────────────────

  /// BiliPai 风格圆角卡片容器（扁平、无阴影）。
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
      ),
      child: child,
    );
  }

  /// unix 秒 → 'YYYY-MM-DD HH:mm'。
  static String _formatDate(int? seconds) {
    if (seconds == null || seconds <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    String pad(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${pad(dt.month)}-${pad(dt.day)} '
        '${pad(dt.hour)}:${pad(dt.minute)}';
  }
}

/// 稿件作者关注按钮：
/// - 未关注状态：默认显示“关注”，鼠标悬浮显示“开始关注”。
/// - 已关注状态：默认显示“已关注”，鼠标悬浮显示“取消关注”，点击取消关注。
class _AuthorFollowButton extends StatefulWidget {
  final bool isFollowed;
  final bool isLoading;
  final VoidCallback onPressed;

  const _AuthorFollowButton({
    required this.isFollowed,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  State<_AuthorFollowButton> createState() => _AuthorFollowButtonState();
}

class _AuthorFollowButtonState extends State<_AuthorFollowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final String label;
    final IconData icon;
    final Color? color;

    if (!widget.isFollowed) {
      label = _isHovered ? '开始关注' : '关注';
      icon = AppIcons.add();
      color = _isHovered ? cs.primary : null;
    } else {
      if (_isHovered) {
        label = '取消关注';
        icon = AppIcons.clear();
        color = Colors.red;
      } else {
        label = '已关注';
        icon = AppIcons.check();
        color = cs.outline;
      }
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Tooltip(
        message: widget.isFollowed ? '点击取消关注' : '点击关注',
        child: OutlinedButton.icon(
          onPressed: widget.isLoading ? null : widget.onPressed,
          icon: widget.isLoading
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color ?? cs.primary,
                  ),
                )
              : Icon(icon, size: 16, color: color),
          label: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: color,
              fontWeight:
                  widget.isFollowed ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            side: color != null
                ? BorderSide(color: color.withValues(alpha: 0.6))
                : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Style.radiusSm),
            ),
          ),
        ),
      ),
    );
  }
}

