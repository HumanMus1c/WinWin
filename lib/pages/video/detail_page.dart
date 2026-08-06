import 'package:flutter/material.dart';

import 'package:winwin/common/skeleton/skeleton.dart';
import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/core/account/login_guard.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/video.dart';
import 'package:winwin/models/video/related_video.dart';
import 'package:winwin/models/video/reply_item.dart';
import 'package:winwin/models/video/video_detail.dart';
import 'package:winwin/pages/video/player_controller.dart';
import 'package:winwin/pages/video/player_panel.dart';
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

class _VideoDetailPageState extends State<VideoDetailPage> {
  final ScrollController scrollController = ScrollController();
  WinWinPlayerController? playerController;

  LoadingState<VideoDetailData> _detailState = LoadingState.loading();
  LoadingState<List<RelatedVideoItem>> _relatedState = LoadingState.loading();

  final List<ReplyItemModel> _replies = [];
  String? _nextOffset;
  bool _replyEnd = false;
  bool _loadingReplies = false;
  bool _replyFailed = false;

  bool _fullscreen = false;
  bool _descExpanded = false;

  /// 评论区之前的固定区块数量：播放器 / 信息 / 简介 / 评论头。
  static const int _fixedSections = 4;

  @override
  void initState() {
    super.initState();
    _loadDetail();
    _loadRelated();
  }

  @override
  void dispose() {
    playerController?.dispose();
    scrollController.dispose();
    super.dispose();
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
          playerController =
              WinWinPlayerController(bvid: widget.bvid, cid: cid)..load();
        }
        setState(() => _detailState = Success(response));
        final aid = response.aid;
        if (aid != null) {
          _loadReplies(oid: aid);
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
          : Row(
              children: [
                Expanded(flex: 7, child: _buildLeftColumn()),
                Expanded(flex: 3, child: _buildRightColumn()),
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
              NetworkImgLayer(
                src: owner?.face,
                width: 40,
                height: 40,
                type: 'avatar',
              ),
              const SizedBox(width: Style.md),
              Expanded(
                child: Text(
                  owner?.name ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
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
    return _card(
      margin: const EdgeInsets.only(top: Style.sm),
      padding: const EdgeInsets.all(Style.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NetworkImgLayer(
            src: member?.avatar,
            width: 40,
            height: 40,
            type: 'avatar',
          ),
          const SizedBox(width: Style.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        member?.uname ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
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
                Row(
                  spacing: Style.xs,
                  children: [
                    Icon(
                      Icons.thumb_up_outlined,
                      size: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    Text(NumUtils.formatNum(reply.like), style: grayStyle),
                  ],
                ),
              ],
            ),
          ),
        ],
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
