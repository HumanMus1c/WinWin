import 'package:flutter/material.dart';

import 'package:winwin/common/skeleton/video_card_v.dart';
import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/common/widgets/p_badge.dart';
import 'package:winwin/common/widgets/refresh_indicator.dart';
import 'package:winwin/core/account/account_service.dart';
import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/http/dyn.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/pages/member/member_space_page.dart';
import 'package:winwin/pages/video/detail_page.dart';
import 'package:winwin/theme/app_shapes.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/utils/grid.dart';
import 'package:winwin/utils/num_utils.dart';

/// 推送动态页。
void showDynamicsPage(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const DynamicsPage()),
  );
}

/// 动态页（对齐 PiliPlus 与 BiliPai 响应式宫格排版）。
///
/// 顶部 TabBar 切换动态类型，主体为自适应多列宫格列表。
class DynamicsPage extends StatefulWidget {
  const DynamicsPage({super.key});

  @override
  State<DynamicsPage> createState() => _DynamicsPageState();
}

class _DynamicsPageState extends State<DynamicsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final List<_DynTabData> _tabs = const [
    _DynTabData(label: '全部', type: 'all'),
    _DynTabData(label: '视频', type: 'video'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('动态'),
        bottom: TabBar(
          controller: _tabController,
          tabs: _tabs.map((t) => Tab(text: t.label)).toList(),
          dividerHeight: 0,
          indicatorSize: TabBarIndicatorSize.label,
          labelPadding: const EdgeInsets.symmetric(horizontal: Style.md),
        ),
        shape: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabs
            .map((t) => _DynTabPage(type: t.type))
            .toList(),
      ),
    );
  }
}

class _DynTabData {
  final String label;
  final String type;
  const _DynTabData({required this.label, required this.type});
}

/// 单个动态 tab 页：下拉刷新 + 宫格式列表 + 分页加载。
class _DynTabPage extends StatefulWidget {
  const _DynTabPage({required this.type});

  final String type;

  @override
  State<_DynTabPage> createState() => _DynTabPageState();
}

class _DynTabPageState extends State<_DynTabPage>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  LoadingState<DynFeedData> _state = LoadingState.loading();
  final List<DynItemModel> _items = [];
  String? _offset;
  bool _hasMore = true;
  bool _loading = false;

  bool get _isVideoTab => widget.type == 'video';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    AccountService().addListener(_onAccountChanged);
    _load(refresh: true);
  }

  @override
  void dispose() {
    AccountService().removeListener(_onAccountChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onAccountChanged() {
    if (!mounted) return;
    if (AccountService().isLogin) {
      _load(refresh: true);
    } else {
      setState(() {
        _items.clear();
        _offset = null;
        _hasMore = true;
        _state = const Error('请先登录');
      });
    }
  }

  Future<void> _load({required bool refresh}) async {
    if (_loading) return;
    if (!refresh && !_hasMore) return;
    _loading = true;
    if (refresh) {
      _offset = null;
      _items.clear();
      setState(() => _state = LoadingState.loading());
    }
    await ensureBootstrap();
    final res = await DynHttp.followDynamic(
      offset: refresh ? null : _offset,
      type: widget.type,
    );
    if (!mounted) return;
    switch (res) {
      case Success(:final response):
        _items.addAll(response.items);
        _offset = response.hasMore ? response.offset : null;
        _hasMore = response.hasMore;
        setState(() => _state = Success(response));
      case Error():
        setState(() => _state = res);
      case Loading():
        break;
    }
    _loading = false;
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      _load(refresh: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollEndNotification) _onScroll();
        return false;
      },
      child: AppRefreshIndicator(
        onRefresh: () => _load(refresh: true),
        child: switch (_state) {
          Loading() => _buildSkeleton(),
          Error(:final errMsg) => _buildError(errMsg),
          Success() => _items.isEmpty
              ? _buildEmpty()
              : CustomScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        Style.safeSpace,
                        Style.sm,
                        Style.safeSpace,
                        Style.xxl * 2,
                      ),
                      sliver: _isVideoTab
                          ? _buildVideoGrid()
                          : _buildAllDynGrid(),
                    ),
                    SliverToBoxAdapter(
                      child: _buildTrailer(),
                    ),
                  ],
                ),
        },
      ),
    );
  }

  /// 视频 Tab 宫格排版（与推荐/热门/关注流对齐的纵向卡片网格）。
  Widget _buildVideoGrid() {
    final gridDelegate = Grid.videoCardVDelegate(
      mainAxisExtent: MediaQuery.textScalerOf(context).scale(90),
    );
    return SliverGrid.builder(
      gridDelegate: gridDelegate,
      itemCount: _items.length,
      itemBuilder: (context, index) {
        if (index == _items.length - 1) {
          _onScroll();
        }
        return _DynVideoCard(item: _items[index]);
      },
    );
  }

  /// 全部 Tab 宫格排版（自适应 1~3 列动态全卡片网格）。
  Widget _buildAllDynGrid() {
    final gridDelegate = Grid.dynCardDelegate(
      maxCrossAxisExtent: 520.0,
    );
    return SliverGrid.builder(
      gridDelegate: gridDelegate,
      itemCount: _items.length,
      itemBuilder: (context, index) {
        if (index == _items.length - 1) {
          _onScroll();
        }
        return _DynCard(item: _items[index]);
      },
    );
  }

  Widget _buildSkeleton() {
    return CustomScrollView(
      physics: const NeverScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            Style.safeSpace,
            Style.sm,
            Style.safeSpace,
            Style.xxl * 2,
          ),
          sliver: SliverGrid.builder(
            gridDelegate: Grid.videoCardVDelegate(),
            itemBuilder: (context, index) => const VideoCardVSkeleton(),
            itemCount: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildError(String? msg) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(msg ?? '加载失败'),
            const SizedBox(height: Style.md),
            FilledButton.tonal(
              onPressed: () => _load(refresh: true),
              child: const Text('重试'),
            ),
          ],
        ),
      );

  Widget _buildEmpty() => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: Text('暂无动态')),
        ],
      );

  Widget _buildTrailer() {
    if (_loading) {
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
    if (!_hasMore && _items.isNotEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: Style.lg),
        child: Center(
          child: Text(
            '没有更多了',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// 视频 Tab 专属纵向视频卡片（对齐 VideoCardV 视觉规范）。
class _DynVideoCard extends StatelessWidget {
  const _DynVideoCard({required this.item});

  final DynItemModel item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shapes = theme.extension<AppShapes>() ?? AppShapes.ios;
    final radius = shapes.medium;
    final archive = item.archive;
    final author = item.author;
    final bvid = archive?.bvid;
    final cover = archive?.cover;
    final title = archive?.title ?? item.text ?? '';
    final durationText = archive?.durationText;
    final play = archive?.play;
    final danmaku = archive?.danmaku;

    return Card(
      child: InkWell(
        onTap: () {
          if (bvid == null || bvid.isEmpty) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VideoDetailPage(bvid: bvid, cover: cover),
            ),
          );
        },
        borderRadius: BorderRadius.all(radius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面区（16:10）
            AspectRatio(
              aspectRatio: 16 / 10,
              child: LayoutBuilder(
                builder: (context, boxConstraints) {
                  final double maxWidth = boxConstraints.maxWidth;
                  final double maxHeight = boxConstraints.maxHeight;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      NetworkImgLayer(
                        src: cover,
                        width: maxWidth,
                        height: maxHeight,
                        borderRadius: BorderRadius.vertical(
                          top: radius,
                        ),
                        heroTag: bvid != null ? 'cover_$bvid' : null,
                      ),
                      if (durationText != null && durationText.isNotEmpty)
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: PBadge(
                            text: durationText,
                            type: PBadgeType.duration,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            // 内容区
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(height: 1.35),
                      ),
                    ),
                    // 播放与弹幕数统计
                    Row(
                      spacing: 3,
                      children: [
                        Icon(
                          Icons.play_circle_outlined,
                          size: 13,
                          color: theme.colorScheme.outline.withValues(alpha: 0.8),
                        ),
                        Text(
                          NumUtils.formatNum(play),
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.outline.withValues(alpha: 0.8),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.subtitles_outlined,
                          size: 13,
                          color: theme.colorScheme.outline.withValues(alpha: 0.8),
                        ),
                        Text(
                          NumUtils.formatNum(danmaku),
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.outline.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // UP 主药丸标
                    if (author?.name != null && author!.name!.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          final mid = author.mid;
                          if (mid != null && mid > 0) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MemberSpacePage(mid: mid),
                              ),
                            );
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondaryContainer
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            author.name!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              height: 1.4,
                              fontSize: theme.textTheme.labelMedium?.fontSize,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 全部 Tab 综合动态卡片：作者 + 正文 + 内嵌视频/媒体卡片。
class _DynCard extends StatelessWidget {
  const _DynCard({required this.item});

  final DynItemModel item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final author = item.author;
    final archive = item.archive;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Style.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 作者行
            Row(
              children: [
                GestureDetector(
                  onTap: () => _gotoMember(context, author?.mid),
                  child: NetworkImgLayer(
                    src: author?.face,
                    width: 38,
                    height: 38,
                    type: 'avatar',
                  ),
                ),
                const SizedBox(width: Style.sm),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _gotoMember(context, author?.mid),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          author?.name ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (item.pubTs != null)
                          Text(
                            _formatTime(item.pubTs!),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.outline,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // 正文
            if (item.text != null && item.text!.isNotEmpty) ...[
              const SizedBox(height: Style.sm),
              Text(
                item.text!,
                style: theme.textTheme.bodyMedium,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            // 视频稿件预览
            if (item.isVideo && archive != null && archive.bvid != null) ...[
              const SizedBox(height: Style.sm),
              _buildVideoPreview(context, archive),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPreview(BuildContext context, DynArchive archive) {
    return GestureDetector(
      onTap: () {
        final bvid = archive.bvid;
        if (bvid == null) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VideoDetailPage(bvid: bvid, cover: archive.cover),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Style.radiusSm),
        child: Stack(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: NetworkImgLayer(
                src: archive.cover,
                width: double.infinity,
                height: double.infinity,
                borderRadius: BorderRadius.circular(Style.radiusSm),
                heroTag: archive.bvid != null ? 'cover_${archive.bvid}' : null,
              ),
            ),
            Positioned.fill(
              child: Container(
                alignment: Alignment.bottomLeft,
                padding: const EdgeInsets.all(Style.sm),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.65),
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      archive.title ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (archive.durationText != null ||
                        archive.play != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (archive.durationText != null)
                            PBadge(
                              text: archive.durationText,
                              type: PBadgeType.duration,
                            ),
                          if (archive.play != null) ...[
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.play_circle_outlined,
                              size: 12,
                              color: Colors.white70,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              NumUtils.formatNum(archive.play),
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                          if (archive.danmaku != null) ...[
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.subtitles_outlined,
                              size: 12,
                              color: Colors.white70,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              NumUtils.formatNum(archive.danmaku),
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _gotoMember(BuildContext context, int? mid) {
    if (mid == null || mid <= 0) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MemberSpacePage(mid: mid)),
    );
  }

  static String _formatTime(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 30) return '${diff.inDays}天前';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
