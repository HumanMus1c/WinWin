import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'package:winwin/common/skeleton/skeleton.dart';
import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/core/account/login_guard.dart';
import 'package:winwin/core/log/app_logger.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/video.dart';
import 'package:winwin/main.dart';
import 'package:winwin/models/video/play_info.dart';
import 'package:winwin/models/video/related_video.dart';
import 'package:winwin/models/video/reply_item.dart';
import 'package:winwin/models/video/video_detail.dart';
import 'package:winwin/pages/member/member_space_page.dart';
import 'package:winwin/pages/video/desktop_pip.dart';
import 'package:winwin/pages/video/player_controller.dart';
import 'package:winwin/pages/video/player_panel.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/utils/duration_utils.dart';
import 'package:winwin/utils/num_utils.dart';

/// 视频详情页 — 桌面宽屏双栏布局。
///
/// 左栏（flex 7）：播放器、标题/数据/UP、简介、评论列表；
/// 右栏（flex 3）：相关视频。视觉沿用 BiliPai 的 iOS 风格
/// （圆角卡片、safeSpace 边距、扁平无阴影）。
class VideoDetailPage extends StatefulWidget {
  const VideoDetailPage({super.key, required this.bvid, this.cover});

  final String bvid;
  final String? cover;

  @override
  State<VideoDetailPage> createState() => _VideoDetailPageState();
}

class _VideoDetailPageState extends State<VideoDetailPage>
    with RouteAware, WindowListener {
  final ScrollController scrollController = ScrollController();
  WinWinPlayerController? playerController;

  LoadingState<VideoDetailData> _detailState = LoadingState.loading();
  LoadingState<List<RelatedVideoItem>> _relatedState = LoadingState.loading();

  final List<ReplyItemModel> _replies = [];
  String? _nextOffset;
  bool _replyEnd = false;
  bool _loadingReplies = false;
  bool _replyFailed = false;

  /// 楼中楼展开状态：key = 根评论 rpid，value = 二级回复列表。
  final Map<int, List<ReplyItemModel>> _subReplies = {};
  final Map<int, String?> _subNextOffset = {};
  final Map<int, bool> _subEnd = {};
  final Map<int, bool> _subLoading = {};

  /// 评论输入框。
  final TextEditingController _commentCtrl = TextEditingController();
  bool _sendingComment = false;
  /// 回复目标（null=发表一级评论，否则为根评论 rpid + 被回复用户名）。
  int? _replyRoot;
  String? _replyHint;

  bool _fullscreen = false;
  bool _descExpanded = false;

  /// 页面被新路由覆盖前的播放状态，用于返回时决定是否自动播放。
  bool _wasPlaying = false;
  /// 页面被覆盖前记录的播放位置，用于返回时恢复进度。
  Duration _savedPosition = Duration.zero;

  /// playInfo 接口返回的数据（Phase 4.2 历史进度 / 4.4 字幕 / 4.5 章节）。
  /// 由 [_loadDetail] 拉取后缓存，供后续 Phase 使用。
  PlayInfoModel? _playInfo;

  /// 评论区之前的固定区块数量：播放器 / 信息 / 简介 / 评论头。
  static const int _fixedSections = 4;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _loadDetail();
    _loadRelated();
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
    // 退出时如果处于 PiP 模式，恢复窗口。
    DesktopPipController.instance.exitPip();
    playerController?.dispose();
    scrollController.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────── RouteAware ───────────────────────────

  /// 新页面 push 到本页之上时：暂停共享播放器并移除本页的事件监听
  /// （参照 PiliPlus didPushNext: pause + removeStatusLister +
  /// removePositionListener）。这样新页面在共享 player 上切换 media 时，
  /// 旧 media 卸载产生的事件不会污染本页 controller 的状态。
  @override
  void didPushNext() {
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

  /// 上一个页面 pop 回到本页时：重新挂载事件监听，然后在共享播放器上
  /// 重新加载本页视频，从记忆的进度恢复（参照 PiliPlus didPopNext:
  /// addStatusLister + addPositionListener + playerInit）。
  @override
  void didPopNext() {
    final ctrl = playerController;
    if (ctrl != null) {
      AppLogger.i('VideoDetailPage', 'didPopNext: reload from ${_savedPosition.inSeconds}s, autoplay=$_wasPlaying');
      ctrl.attachListeners();
      ctrl.load(start: _savedPosition, autoplay: _wasPlaying);
      // 重建弹幕：PlayerPanel 始终挂载，WinWinDanmaku 不会随路由重建，
      // 需显式触发 dm 重建 + 引擎 clear（参照 PiliPlus didPopNext 重建 PlDanmaku）。
      ctrl.reloadDanmaku();
      _wasPlaying = false;
      _savedPosition = Duration.zero;
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

  // ─────────────────────────── 数据加载 ───────────────────────────

  Future<void> _loadDetail() async {
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
          // Phase 4.2：拉取 playInfo 获取上次播放进度（last_play_time），
          // 同时缓存字幕列表 / 章节标记供 Phase 4.4 / 4.5 使用。
          Duration? startProgress;
          final aid = response.aid;
          try {
            final infoRes =
                await VideoHttp.playInfo(bvid: widget.bvid, cid: cid);
            if (!mounted) return;
            if (infoRes case Success(:final response)) {
              _playInfo = response;
              if (response.lastPlayTime > 0) {
                startProgress = Duration(seconds: response.lastPlayTime);
              }
            }
          } catch (_) {
            // playInfo 失败不阻断播放。
          }
          if (!mounted) return;
          final ctrl = WinWinPlayerController(bvid: widget.bvid, cid: cid);
          ctrl.aid = aid;
          playerController = ctrl;
          // Phase 4.4：传入可用字幕列表，SubtitleController 自动按 AI 偏好选择。
          final subtitles = _playInfo?.subtitle?.subtitles ?? const [];
          if (subtitles.isNotEmpty) {
            ctrl.setSubtitleList(subtitles);
          }
          // Phase 4.5：传入章节标记（view_points），供进度条渲染章节标记。
          final viewPoints = _playInfo?.viewPoints ?? const [];
          if (viewPoints.isNotEmpty) {
            ctrl.setViewPoints(viewPoints);
          }
          ctrl.load(start: startProgress);
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

  Future<void> _loadRelated() async {
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

  Future<void> _loadReplies({required int oid, String? nextOffset}) async {
    if (_loadingReplies) return;
    _loadingReplies = true;
    if (_replies.isNotEmpty) {
      setState(() {}); // 让尾部 spinner 立即出现
    }
    final res = await VideoHttp.replyMain(oid: oid, nextOffset: nextOffset);
    if (!mounted) return;
    _loadingReplies = false;
    switch (res) {
      case Success(:final response):
        final cursor = response.cursor;
        _nextOffset = cursor?.nextOffset;
        _replyEnd = cursor?.isEnd ?? response.replies.isEmpty;
        _replyFailed = false;
        setState(() => _replies.addAll(response.replies));
      case Error():
        _replyFailed = true;
        setState(() {});
      case Loading():
        break;
    }
  }

  /// 滚动到列表尾部时触发（在 itemBuilder 中调用，
  /// 参考 RcmdPage 的 onLoadMore 模式）。
  void _maybeLoadMoreReplies() {
    final aid = _detailState.dataOrNull?.aid;
    if (aid == null || _loadingReplies || _replyEnd || _replyFailed) return;
    _loadReplies(oid: aid, nextOffset: _nextOffset);
  }

  void _retryReplies() {
    final aid = _detailState.dataOrNull?.aid;
    if (aid == null) return;
    setState(() => _replyFailed = false);
    _loadReplies(oid: aid, nextOffset: _nextOffset);
  }

  // ─────────────────────────── 评论点赞 ───────────────────────────

  /// 切换评论点赞状态。
  Future<void> _toggleLikeReply(ReplyItemModel reply) async {
    final aid = _detailState.dataOrNull?.aid;
    final rpid = reply.rpid;
    if (aid == null || rpid == null) return;
    if (!await LoginGuard.requireLogin(context)) return;
    if (!mounted) return;

    final wasLiked = reply.isLiked;
    // 乐观更新：先切换 UI 状态。
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
      // 回滚乐观更新。
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
  void _setReplyTarget(ReplyItemModel reply) async {
    if (!await LoginGuard.requireLogin(context)) return;
    if (!mounted) return;
    setState(() {
      _replyRoot = reply.rpid;
      _replyHint = '回复 @${reply.member?.uname ?? ''}';
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
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
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

  void _toggleFullscreen() {
    if (playerController == null) return;
    setState(() => _fullscreen = !_fullscreen);
  }

  // ─────────────────────────── 布局 ───────────────────────────

  @override
  Widget build(BuildContext context) {
    final String? upName = _detailState.dataOrNull?.owner?.name;
    return Scaffold(
      backgroundColor: _fullscreen ? Colors.black : null,
      appBar: _fullscreen
          ? null
          : AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(
                (upName?.isNotEmpty ?? false) ? upName! : '视频详情',
                overflow: TextOverflow.ellipsis,
              ),
            ),
      body: _fullscreen
          ? Stack(
              children: [
                Positioned.fill(
                  child: PlayerPanel(
                    controller: playerController!,
                    fullscreen: true,
                    onToggleFullscreen: _toggleFullscreen,
                  ),
                ),
              ],
            )
          : Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Expanded(flex: 7, child: _buildLeftColumn()),
                      Expanded(flex: 3, child: _buildRightColumn()),
                    ],
                  ),
                ),
                _buildCommentInputBar(),
              ],
            ),
    );
  }

  // ─────────────────────────── 左栏 ───────────────────────────

  Widget _buildLeftColumn() {
    return switch (_detailState) {
      Loading() => _buildLeftSkeleton(),
      Error(:final errMsg) => _buildError(errMsg, _loadDetail),
      Success(:final response) => ListView.builder(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(
          Style.safeSpace,
          Style.sm,
          Style.cardSpace,
          Style.xxl * 2,
        ),
        itemCount: _fixedSections + _replies.length + 1,
        itemBuilder: (context, index) => _buildSection(index, response),
      ),
    };
  }

  Widget _buildSection(int index, VideoDetailData data) {
    if (index == 0) {
      return Padding(
        padding: const EdgeInsets.only(bottom: Style.md),
        child: _buildPlayerSection(data),
      );
    }
    if (index == 1) return _buildInfoSection(data);
    if (index == 2) return _buildDescSection(data);
    if (index == 3) return _buildReplyHeader(data);
    final replyIndex = index - _fixedSections;
    if (replyIndex < _replies.length) {
      if (replyIndex == _replies.length - 1) {
        _maybeLoadMoreReplies();
      }
      return _buildReplyTile(_replies[replyIndex]);
    }
    return _buildReplyTrailer();
  }

  /// 播放器区域：16:9、圆角 12 裁切。
  /// 详情加载完成前用封面占位，避免向 PlayerPanel 传空 controller。
  Widget _buildPlayerSection(VideoDetailData data) {
    final controller = playerController;
    final Widget child = controller == null
        ? NetworkImgLayer(
            src: widget.cover ?? data.pic,
            width: double.infinity,
            height: double.infinity,
            borderRadius: BorderRadius.zero,
          )
        : PlayerPanel(
            controller: controller,
            fullscreen: _fullscreen,
            onToggleFullscreen: _toggleFullscreen,
          );
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Style.mdRadius),
        child: ColoredBox(color: Colors.black, child: child),
      ),
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
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: Style.sm),
          Row(
            spacing: Style.md,
            children: [
              Icon(
                Icons.play_circle_outline,
                size: 15,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              Text(NumUtils.formatNum(stat?.view), style: grayStyle),
              Icon(
                Icons.subtitles_outlined,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              Text(NumUtils.formatNum(stat?.danmaku), style: grayStyle),
              Icon(
                Icons.schedule_outlined,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              Text(
                DurationUtils.formatDuration(data.duration),
                style: grayStyle,
              ),
              if (data.pubdate != null) Text(_formatDate(data.pubdate), style: grayStyle),
            ],
          ),
          const SizedBox(height: Style.md),
          Row(
            children: [
              GestureDetector(
                onTap: () => _gotoMemberSpace(owner?.mid),
                child: NetworkImgLayer(
                  src: owner?.face,
                  width: 40,
                  height: 40,
                  type: 'avatar',
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
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              // 关注按钮：未登录→登录页；已登录→TODO 接入关注接口
              FilledButton.tonal(
                onPressed: () async {
                  if (!await LoginGuard.requireLogin(context)) return;
                  // TODO: 接入关注/取关接口（需 FollowHttp）
                  if (!mounted) return;
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    const SnackBar(
                      content: Text('关注接口待接入'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                child: const Text('关注'),
              ),
            ],
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

  Widget _buildReplyHeader(VideoDetailData data) {
    final count = data.stat?.reply;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Style.xs,
        Style.lg,
        Style.xs,
        Style.sm,
      ),
      child: Text(
        count != null ? '评论 ${NumUtils.formatNum(count)}' : '评论',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

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
                child: NetworkImgLayer(
                  src: member?.avatar,
                  width: 40,
                  height: 40,
                  type: 'avatar',
                ),
              ),
              const SizedBox(width: Style.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () =>
                                _gotoMemberSpace(reply.mid ?? member?.mid),
                            child: Text(
                              member?.uname ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        Text(_formatDate(reply.ctime), style: grayStyle),
                      ],
                    ),
                    const SizedBox(height: Style.xs),
                    Text(
                      reply.content?.message ?? '',
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                    ),
                    const SizedBox(height: Style.xs),
                    // 操作行：点赞 + 回复
                    Row(
                      spacing: Style.lg,
                      children: [
                        GestureDetector(
                          onTap: () => _toggleLikeReply(reply),
                          child: Row(
                            spacing: Style.xs,
                            children: [
                              Icon(
                                reply.isLiked
                                    ? Icons.thumb_up
                                    : Icons.thumb_up_outlined,
                                size: 14,
                                color: reply.isLiked
                                    ? biliPink
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                              Text(
                                NumUtils.formatNum(reply.like),
                                style: grayStyle.copyWith(
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
                            spacing: Style.xs,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 13,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              Text(
                                '回复',
                                style: grayStyle,
                              ),
                            ],
                          ),
                        ),
                        if ((reply.rcount ?? 0) > 0)
                          GestureDetector(
                            onTap: () => _toggleSubReplies(reply),
                            child: Row(
                              spacing: Style.xs,
                              children: [
                                Text(
                                  subReplies != null
                                      ? '收起 ${reply.rcount}条回复'
                                      : '展开 ${reply.rcount}条回复',
                                  style: grayStyle.copyWith(
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                                Icon(
                                  subReplies != null
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  size: 14,
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
          // 楼中楼回复列表
          if (subReplies != null) ...[
            const SizedBox(height: Style.sm),
            Container(
              padding: const EdgeInsets.only(left: Style.md + Style.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final sub in subReplies) _buildSubReplyTile(sub, reply),
                  if (subLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: Style.xs),
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  if (!subEnd && !subLoading && subReplies.length >= 3)
                    TextButton(
                      onPressed: () => _loadSubReplies(reply),
                      child: const Text('查看更多回复'),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 楼中楼单条回复。
  Widget _buildSubReplyTile(ReplyItemModel sub, ReplyItemModel root) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Style.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _gotoMemberSpace(sub.mid ?? sub.member?.mid),
            child: NetworkImgLayer(
              src: sub.member?.avatar,
              width: 28,
              height: 28,
              type: 'avatar',
            ),
          ),
          const SizedBox(width: Style.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                    children: [
                      TextSpan(
                        text: '${sub.member?.uname ?? ''}：',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      TextSpan(
                        text: sub.content?.message ?? '',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  spacing: Style.md,
                  children: [
                    Text(_formatDate(sub.ctime),
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        )),
                    GestureDetector(
                      onTap: () => _toggleLikeSubReply(sub),
                      child: Row(
                        spacing: Style.xs,
                        children: [
                          Icon(
                            sub.isLiked
                                ? Icons.thumb_up
                                : Icons.thumb_up_outlined,
                            size: 12,
                            color: sub.isLiked
                                ? biliPink
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          Text(
                            NumUtils.formatNum(sub.like),
                            style: TextStyle(
                              fontSize: 11,
                              color: sub.isLiked
                                  ? biliPink
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _setReplyTarget(root),
                      child: Text(
                        '回复',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
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

  /// 楼中楼点赞（乐观更新）。
  Future<void> _toggleLikeSubReply(ReplyItemModel sub) async {
    final aid = _detailState.dataOrNull?.aid;
    final rpid = sub.rpid;
    if (aid == null || rpid == null) return;
    if (!await LoginGuard.requireLogin(context)) return;
    if (!mounted) return;

    final wasLiked = sub.isLiked;
    // 乐观更新。
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
      // 回滚。
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
      _toast(errMsg ?? '操作失败');
    }
  }

  /// 底部评论输入栏。
  Widget _buildCommentInputBar() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        Style.safeSpace,
        Style.xs,
        Style.safeSpace,
        Style.xs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withOpacity(0.3),
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
                  hintText: _replyHint ?? '发一条友善的弹幕吧~',
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
                      .withOpacity(0.5),
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
              onPressed: _sendingComment ? null : _sendComment,
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
      // 首页评论为空时也尝试触发一次加载（首次加载由 _loadDetail 发起，
      // 这里兜底处理 aid 晚到的情况）。
      _maybeLoadMoreReplies();
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
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Style.lg),
        child: Center(
          child: Text(
            '没有更多评论了',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    // 尚未到底且未在加载：兜底触发下一页。
    _maybeLoadMoreReplies();
    return const SizedBox.shrink();
  }

  // ─────────────────────────── 右栏（相关视频） ───────────────────────────

  Widget _buildRightColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Style.cardSpace,
            Style.lg,
            Style.safeSpace,
            Style.sm,
          ),
          child: Text(
            '相关推荐',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: switch (_relatedState) {
            Loading() => _buildRightSkeleton(),
            Error(:final errMsg) => _buildError(errMsg, _loadRelated),
            Success(:final response) => response.isEmpty
                ? Center(
                    child: Text(
                      '暂无相关推荐',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      Style.cardSpace,
                      0,
                      Style.safeSpace,
                      Style.xxl * 2,
                    ),
                    itemCount: response.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: Style.sm),
                    itemBuilder: (context, index) =>
                        _buildRelatedItem(response[index]),
                  ),
          },
        ),
      ],
    );
  }

  Widget _buildRelatedItem(RelatedVideoItem item) {
    final theme = Theme.of(context);
    const double coverWidth = 150;
    const double coverHeight = coverWidth * 10 / 16;
    final bvid = item.bvid;
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(Style.radiusSm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: bvid == null
            ? null
            : () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        VideoDetailPage(bvid: bvid, cover: item.pic),
                  ),
                );
              },
        child: Padding(
          padding: const EdgeInsets.all(Style.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: coverWidth,
                height: coverHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    NetworkImgLayer(
                      src: item.pic,
                      width: coverWidth,
                      height: coverHeight,
                      borderRadius: BorderRadius.circular(Style.radiusSm),
                    ),
                    if ((item.duration ?? 0) > 0)
                      Positioned(
                        right: 5,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(Style.radiusXs),
                          ),
                          child: Text(
                            DurationUtils.formatDuration(item.duration),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: Style.md),
              Expanded(
                child: SizedBox(
                  height: coverHeight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          height: 1.3,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        spacing: Style.xs,
                        children: [
                          Icon(
                            Icons.person_outline,
                            size: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          Expanded(
                            child: Text(
                              item.owner?.name ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────── 骨架屏 / 错误态 ───────────────────────────

  Widget _buildLeftSkeleton() {
    final color = ColorScheme.of(context).onInverseSurface;
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(
        Style.safeSpace,
        Style.sm,
        Style.cardSpace,
        Style.xxl * 2,
      ),
      children: [
        Skeleton(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(Style.mdRadius),
                  ),
                ),
              ),
              const SizedBox(height: Style.lg),
              Container(width: 360, height: 22, color: color),
              const SizedBox(height: Style.sm),
              Container(width: 220, height: 13, color: color),
              const SizedBox(height: Style.md),
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: Style.md),
                  Container(width: 120, height: 14, color: color),
                ],
              ),
              const SizedBox(height: Style.lg),
              Container(width: double.infinity, height: 60, color: color),
              const SizedBox(height: Style.lg),
              Container(width: 100, height: 16, color: color),
              for (int i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.only(top: Style.md),
                  child: Container(
                    width: double.infinity,
                    height: 68,
                    color: color,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRightSkeleton() {
    final color = ColorScheme.of(context).onInverseSurface;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        Style.cardSpace,
        0,
        Style.safeSpace,
        Style.xxl * 2,
      ),
      itemCount: 6,
      separatorBuilder: (_, _) => const SizedBox(height: Style.sm),
      itemBuilder: (context, index) => Skeleton(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 150,
              height: 150 * 10 / 16,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(Style.radiusSm),
              ),
            ),
            const SizedBox(width: Style.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(width: double.infinity, height: 13, color: color),
                  const SizedBox(height: Style.xs),
                  Container(width: 120, height: 13, color: color),
                  const SizedBox(height: Style.md),
                  Container(width: 80, height: 11, color: color),
                ],
              ),
            ),
          ],
        ),
      ),
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
