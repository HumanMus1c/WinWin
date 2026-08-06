import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/member.dart';
import 'package:winwin/pages/video/detail_page.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/utils/duration_utils.dart';
import 'package:winwin/utils/num_utils.dart';

/// 用户空间页 — 移植自 PiliPlus `lib/pages/member/view.dart`，精简。
///
/// 展示用户头像、名字、签名、粉丝/关注数，以及投稿视频网格。
/// 点击视频跳转到视频详情页。
class MemberSpacePage extends StatefulWidget {
  const MemberSpacePage({super.key, required this.mid});

  final int mid;

  @override
  State<MemberSpacePage> createState() => _MemberSpacePageState();
}

class _MemberSpacePageState extends State<MemberSpacePage> {
  LoadingState<MemberSpaceData> _spaceState = LoadingState.loading();
  final List<MemberVideoItem> _videos = [];
  bool _loadingVideos = false;
  bool _videoEnd = false;
  bool _videoFailed = false;

  @override
  void initState() {
    super.initState();
    _loadSpace();
  }

  Future<void> _loadSpace() async {
    setState(() => _spaceState = LoadingState.loading());
    final res = await MemberHttp.space(mid: widget.mid);
    if (!mounted) return;
    setState(() => _spaceState = res);
    // 首屏投稿视频已在 space 响应中，直接取用。
    if (res case Success(:final response)) {
      final archives = response.archives;
      if (archives != null && archives.list.isNotEmpty) {
        _videos.addAll(archives.list);
        _videoEnd = archives.isEnd ?? false;
        setState(() {});
      }
      // 加载更多投稿。
      _loadMoreVideos();
    }
  }

  Future<void> _loadMoreVideos() async {
    if (_loadingVideos || _videoEnd || _videoFailed) return;
    _loadingVideos = true;
    final res = await MemberHttp.spaceArchive(mid: widget.mid);
    if (!mounted) return;
    _loadingVideos = false;
    switch (res) {
      case Success(:final response):
        _videos.addAll(response.list);
        _videoEnd = response.isEnd ?? false;
        _videoFailed = false;
        setState(() {});
      case Error():
        _videoFailed = true;
        setState(() {});
      case Loading():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: switch (_spaceState) {
        Loading() => const Center(child: CircularProgressIndicator(color: biliPink)),
        Error(:final errMsg) => _buildError(errMsg, _loadSpace),
        Success(:final response) => CustomScrollView(
          slivers: [
            _buildUserHeader(context, response.card),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Style.safeSpace,
                  Style.md,
                  Style.safeSpace,
                  Style.sm,
                ),
                child: Text(
                  '投稿视频 ${_videos.length}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ),
            if (_videos.isEmpty && !_loadingVideos)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Style.xxl),
                  child: Center(
                    child: Text(
                      '暂无投稿',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  Style.safeSpace,
                  0,
                  Style.cardSpace,
                  Style.xxl * 2,
                ),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisSpacing: Style.md,
                    crossAxisSpacing: Style.sm,
                    childAspectRatio: 0.72,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (index >= _videos.length) return null;
                      // 到达底部触发加载更多。
                      if (index == _videos.length - 1) {
                        _loadMoreVideos();
                      }
                      return _buildVideoCard(_videos[index]);
                    },
                    childCount: _videos.length + (_videoEnd ? 0 : 1),
                  ),
                ),
              ),
            if (_loadingVideos)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: Style.lg),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              ),
            if (_videoFailed)
              SliverToBoxAdapter(
                child: Center(
                  child: TextButton(
                    onPressed: () {
                      setState(() => _videoFailed = false);
                      _loadMoreVideos();
                    },
                    child: const Text('加载失败，点击重试'),
                  ),
                ),
              ),
          ],
        ),
      },
    );
  }

  /// 用户信息头部（头像 + 名字 + 签名 + 粉丝/关注）。
  Widget _buildUserHeader(BuildContext context, MemberCard? card) {
    final theme = Theme.of(context);
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment(0, 0.6),
              colors: [
                biliPink.withOpacity(0.6),
                theme.scaffoldBackgroundColor,
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Style.xl,
                Style.lg,
                Style.xl,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.4),
                            width: 2,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: (card?.face?.isNotEmpty ?? false)
                            ? CachedNetworkImage(
                                imageUrl: card!.face!,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => const ColoredBox(
                                  color: Colors.grey,
                                  child: SizedBox.expand(),
                                ),
                                errorWidget: (_, __, ___) => const Center(
                                  child: Icon(Icons.person,
                                      color: Colors.white, size: 36),
                                ),
                              )
                            : const Icon(Icons.person,
                                color: Colors.white, size: 36),
                      ),
                      const SizedBox(width: Style.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              card?.name ?? '未知用户',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (card?.vip?.isVip ?? false)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: biliPink,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  '大会员',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Style.md),
                  // 签名
                  if ((card?.sign ?? '').isNotEmpty)
                    Text(
                      card!.sign!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: Style.md),
                  // 粉丝/关注
                  Row(
                    spacing: Style.xl,
                    children: [
                      _statColumn(
                        context,
                        '关注',
                        NumUtils.formatNum(card?.following),
                      ),
                      _statColumn(
                        context,
                        '粉丝',
                        NumUtils.formatNum(card?.fans),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statColumn(BuildContext context, String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildVideoCard(MemberVideoItem item) {
    final theme = Theme.of(context);
    final bvid = item.bvid;
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(Style.radiusSm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: bvid == null
            ? null
            : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        VideoDetailPage(bvid: bvid, cover: item.pic),
                  ),
                ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 10,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NetworkImgLayer(
                    src: item.pic,
                    width: double.infinity,
                    height: double.infinity,
                    borderRadius: BorderRadius.zero,
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
            Padding(
              padding: const EdgeInsets.all(Style.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      height: 1.3,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    spacing: Style.xs,
                    children: [
                      Icon(
                        Icons.play_circle_outline,
                        size: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      Text(
                        NumUtils.formatNum(item.play),
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
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
          Icon(Icons.cloud_off_outlined,
              size: 48, color: theme.colorScheme.onSurfaceVariant),
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
          FilledButton.tonal(onPressed: onRetry, child: const Text('点击重试')),
        ],
      ),
    );
  }
}
