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
import 'package:winwin/utils/bilibili_url_parser.dart';
import 'package:winwin/utils/grid.dart';
import 'package:winwin/utils/id_utils.dart';
import 'package:winwin/utils/num_utils.dart';

/// 推送动态页。
void showDynamicsPage(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const DynamicsPage()),
  );
}

/// 动态页（对齐 PiliPlus 与 BiliPai 响应式排版）。
///
/// 顶部 TabBar 切换动态类型，全部 Tab 为弹性单列流，视频 Tab 为自适应多列宫格。
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

/// 单个动态 tab 页：下拉刷新 + 列表/宫格 + 分页加载。
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
    _scrollController.addListener(_onScroll);
    _load(refresh: true);
  }

  @override
  void dispose() {
    AccountService().removeListener(_onAccountChanged);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _checkAutoLoad() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_hasMore || _loading) return;
      if (_scrollController.hasClients) {
        final pos = _scrollController.position;
        if (pos.maxScrollExtent <= 0) {
          _load(refresh: false);
        }
      }
    });
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
        _checkAutoLoad();
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
        if (n is ScrollUpdateNotification || n is ScrollEndNotification) {
          _onScroll();
        }
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
                          : _buildAllDynList(),
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

  /// 全部 Tab 弹性列表排版（居中限制宽度，适配图文/转发等弹性高度卡片）。
  Widget _buildAllDynList() {
    return SliverList.separated(
      itemCount: _items.length,
      separatorBuilder: (_, _) => const SizedBox(height: Style.md),
      itemBuilder: (context, index) {
        if (index == _items.length - 1) {
          _onScroll();
        }
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _DynCard(item: _items[index]),
          ),
        );
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

/// 全部 Tab 综合动态卡片：作者 + 正文/富文本 + 视频/图文/Opus/专栏/转发/直播/商品 + 互动统计。
class _DynCard extends StatelessWidget {
  const _DynCard({required this.item});

  final DynItemModel item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final author = item.author;

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
                    width: 40,
                    height: 40,
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
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                author?.name ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (author?.pubAction != null && author!.pubAction!.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Text(
                                author.pubAction!,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.outline,
                                ),
                              ),
                            ],
                          ],
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
            // 正文（富文本解析）
            if (item.text != null && item.text!.isNotEmpty) ...[
              const SizedBox(height: Style.sm),
              if (item.richTextNodes.isNotEmpty)
                Text.rich(
                  TextSpan(
                    children: _buildRichSpans(context, item.richTextNodes, cs.primary),
                  ),
                  style: theme.textTheme.bodyMedium,
                )
              else
                Text(
                  item.text!,
                  style: theme.textTheme.bodyMedium,
                ),
            ],
            // 动态主体内容（按类型分发）
            if (item.isForward && item.orig != null) ...[
              const SizedBox(height: Style.sm),
              _buildForwardContent(context, item.orig!),
            ] else if (item.isVideo && item.archive != null && item.archive!.bvid != null) ...[
              const SizedBox(height: Style.sm),
              _buildVideoPreview(context, item.archive!),
            ] else if (item.draw != null && item.draw!.items.isNotEmpty) ...[
              const SizedBox(height: Style.sm),
              _buildDrawGrid(context, item.draw!.items),
            ] else if (item.opus != null) ...[
              const SizedBox(height: Style.sm),
              _buildOpusCard(context, item.opus!),
            ] else if (item.article != null) ...[
              const SizedBox(height: Style.sm),
              _buildArticleCard(context, item.article!),
            ] else if (item.liveRcmd != null) ...[
              const SizedBox(height: Style.sm),
              _buildLiveCard(context, item.liveRcmd!),
            ],
            // 附加商品卡模块
            if (item.additional != null && item.additional!.goodsItems.isNotEmpty) ...[
              const SizedBox(height: Style.sm),
              _buildGoodsCard(context, item.additional!),
            ],
            // 底部互动行
            if (item.stat != null) ...[
              const SizedBox(height: Style.sm),
              const Divider(height: 1, thickness: 0.5),
              const SizedBox(height: Style.xs),
              _buildStatRow(context, item.stat!),
            ],
          ],
        ),
      ),
    );
  }

  /// 转发动态内容渲染（嵌套原动态卡片，递归深度 ≤ 1）。
  Widget _buildForwardContent(BuildContext context, DynItemModel orig) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final origAuthor = orig.author;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Style.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(Style.radiusMd),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (origAuthor != null && origAuthor.name != null)
            GestureDetector(
              onTap: () => _gotoMember(context, origAuthor.mid),
              child: Text(
                '@${origAuthor.name}',
                style: TextStyle(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          if (orig.text != null && orig.text!.isNotEmpty) ...[
            const SizedBox(height: 4),
            if (orig.richTextNodes.isNotEmpty)
              Text.rich(
                TextSpan(
                  children: _buildRichSpans(context, orig.richTextNodes, cs.primary),
                ),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              )
            else
              Text(
                orig.text!,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
          ],
          if (orig.isVideo && orig.archive != null && orig.archive?.bvid != null) ...[
            const SizedBox(height: Style.sm),
            _buildVideoPreview(context, orig.archive!),
          ] else if (orig.draw != null && orig.draw!.items.isNotEmpty) ...[
            const SizedBox(height: Style.sm),
            _buildDrawGrid(context, orig.draw!.items),
          ] else if (orig.opus != null) ...[
            const SizedBox(height: Style.sm),
            _buildOpusCard(context, orig.opus!),
          ] else if (orig.article != null) ...[
            const SizedBox(height: Style.sm),
            _buildArticleCard(context, orig.article!),
          ] else if (orig.liveRcmd != null) ...[
            const SizedBox(height: Style.sm),
            _buildLiveCard(context, orig.liveRcmd!),
          ],
        ],
      ),
    );
  }

  /// 图文九宫格图片渲染（1 图自然比例/单大图，2-4 图 2x2，5-9 图 3x3）。
  Widget _buildDrawGrid(BuildContext context, List<DynDrawItem> pics) {
    if (pics.isEmpty) return const SizedBox.shrink();
    if (pics.length == 1) {
      final item = pics.first;
      final w = item.width ?? 16;
      final h = item.height ?? 9;
      final aspect = (w > 0 && h > 0) ? (w / h).clamp(0.6, 2.2) : 16 / 9;
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 320),
        child: AspectRatio(
          aspectRatio: aspect,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Style.radiusSm),
            child: NetworkImgLayer(
              src: item.src,
              width: double.infinity,
              height: double.infinity,
              borderRadius: BorderRadius.circular(Style.radiusSm),
            ),
          ),
        ),
      );
    }

    final crossAxisCount = pics.length == 4 ? 2 : (pics.length >= 3 ? 3 : 2);
    final displayPics = pics.take(9).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : 480.0;
        const spacing = 6.0;
        final rawItemWidth = (totalWidth - spacing * (crossAxisCount - 1)) / crossAxisCount;
        final itemWidth = rawItemWidth.clamp(60.0, 160.0);

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: displayPics.map((pic) {
            return SizedBox(
              width: itemWidth,
              height: itemWidth,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Style.radiusSm),
                child: NetworkImgLayer(
                  src: pic.src,
                  width: double.infinity,
                  height: double.infinity,
                  borderRadius: BorderRadius.circular(Style.radiusSm),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  /// Opus 新版图文/文章卡片渲染。
  Widget _buildOpusCard(BuildContext context, DynOpus opus) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (opus.title != null && opus.title!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              opus.title!,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (opus.summaryText != null && opus.summaryText!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              opus.summaryText!,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        if (opus.pics.isNotEmpty)
          _buildDrawGrid(context, opus.pics),
        if (opus.video != null && opus.video!.bvid != null) ...[
          const SizedBox(height: Style.sm),
          _buildVideoPreview(context, opus.video!),
        ],
      ],
    );
  }

  /// 专栏卡片渲染。
  Widget _buildArticleCard(BuildContext context, DynArticle article) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cover = article.covers.isNotEmpty ? article.covers.first : null;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Style.radiusMd),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Style.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (cover != null && cover.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(Style.radiusSm),
                child: SizedBox(
                  width: 110,
                  height: 75,
                  child: NetworkImgLayer(
                    src: cover,
                    width: 110,
                    height: 75,
                    borderRadius: BorderRadius.circular(Style.radiusSm),
                  ),
                ),
              ),
              const SizedBox(width: Style.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (article.label != null && article.label!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: PBadge(text: article.label!, type: PBadgeType.badge),
                    ),
                  Text(
                    article.title ?? '专栏文章',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (article.desc != null && article.desc!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      article.desc!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.outline,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 直播推荐卡片渲染。
  Widget _buildLiveCard(BuildContext context, DynLiveRcmd live) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Style.radiusMd),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Style.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (live.cover != null && live.cover!.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(Style.radiusSm),
                child: Stack(
                  children: [
                    SizedBox(
                      width: 120,
                      height: 75,
                      child: NetworkImgLayer(
                        src: live.cover,
                        width: 120,
                        height: 75,
                        borderRadius: BorderRadius.circular(Style.radiusSm),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.sensors, color: Colors.white, size: 10),
                            SizedBox(width: 2),
                            Text(
                              'LIVE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Style.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    live.title ?? '直播推荐',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (live.uname != null && live.uname!.isNotEmpty)
                        Text(
                          live.uname!,
                          style: theme.textTheme.labelSmall?.copyWith(color: cs.outline),
                        ),
                      if (live.watchedShow != null && live.watchedShow!.isNotEmpty) ...[
                        const Spacer(),
                        Icon(Icons.remove_red_eye_outlined, size: 12, color: cs.outline),
                        const SizedBox(width: 3),
                        Text(
                          live.watchedShow!,
                          style: theme.textTheme.labelSmall?.copyWith(color: cs.outline),
                        ),
                      ],
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

  /// 附加商品卡模块渲染。
  Widget _buildGoodsCard(BuildContext context, DynAdditional additional) {
    if (additional.goodsItems.isEmpty) return const SizedBox.shrink();
    final item = additional.goodsItems.first;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return InkWell(
      onTap: () {
        if (item.jumpUrl != null && item.jumpUrl!.isNotEmpty) {
          _handleJumpUrl(context, item.jumpUrl!);
        }
      },
      borderRadius: BorderRadius.circular(Style.radiusSm),
      child: Container(
        padding: const EdgeInsets.all(Style.sm),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(Style.radiusSm),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            if (item.cover != null && item.cover!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(Style.radiusXs),
                child: NetworkImgLayer(
                  src: item.cover,
                  width: 36,
                  height: 36,
                  borderRadius: BorderRadius.circular(Style.radiusXs),
                ),
              ),
            const SizedBox(width: Style.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name ?? '商品推荐',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                  ),
                  if (item.price != null && item.price!.isNotEmpty)
                    Text(
                      item.price!,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.shopping_bag_outlined, size: 16, color: cs.primary),
          ],
        ),
      ),
    );
  }

  /// 视频预览卡片。
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

  /// 底部互动统计行（转发/评论/点赞）。
  Widget _buildStatRow(BuildContext context, DynStat stat) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildStatItem(Icons.reply_outlined, stat.repost ?? 0, cs.outline),
        _buildStatItem(Icons.chat_bubble_outline, stat.comment ?? 0, cs.outline),
        _buildStatItem(Icons.thumb_up_outlined, stat.like ?? 0, cs.outline),
      ],
    );
  }

  Widget _buildStatItem(IconData icon, int count, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          count > 0 ? NumUtils.formatNum(count) : '0',
          style: TextStyle(fontSize: 12, color: color),
        ),
      ],
    );
  }

  /// 富文本节点解析渲染。
  List<InlineSpan> _buildRichSpans(
    BuildContext context,
    List<DynRichTextNode> nodes,
    Color primaryColor,
  ) {
    final spans = <InlineSpan>[];
    for (final node in nodes) {
      final type = node.type ?? '';
      final text = node.text ?? node.origText ?? '';
      if (text.isEmpty) continue;

      if (node.emojiUrl != null && node.emojiUrl!.isNotEmpty) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Image.network(
              node.emojiUrl!,
              width: 20,
              height: 20,
              errorBuilder: (_, _, _) => Text(text),
            ),
          ),
        ));
      } else if (type.contains('BV') || (node.rid != null && node.rid!.startsWith('BV'))) {
        final bvid = node.rid ?? (text.startsWith('BV') ? text : null);
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: InkWell(
            onTap: () {
              if (bvid != null && bvid.isNotEmpty) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => VideoDetailPage(bvid: bvid)),
                );
              }
            },
            child: Text(
              text,
              style: TextStyle(color: primaryColor, fontWeight: FontWeight.w500),
            ),
          ),
        ));
      } else if (type.contains('AT') || text.startsWith('@')) {
        final mid = int.tryParse(node.rid ?? '');
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: InkWell(
            onTap: () {
              if (mid != null && mid > 0) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => MemberSpacePage(mid: mid)),
                );
              }
            },
            child: Text(
              text,
              style: TextStyle(color: primaryColor, fontWeight: FontWeight.w500),
            ),
          ),
        ));
      } else if (node.jumpUrl != null && node.jumpUrl!.isNotEmpty) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: InkWell(
            onTap: () => _handleJumpUrl(context, node.jumpUrl!),
            child: Text(
              text,
              style: TextStyle(color: primaryColor, decoration: TextDecoration.underline),
            ),
          ),
        ));
      } else {
        spans.add(TextSpan(text: text));
      }
    }
    return spans;
  }

  void _handleJumpUrl(BuildContext context, String url) {
    final result = BilibiliUrlParser.parseDeepLink(url);
    if (result.bvid != null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => VideoDetailPage(bvid: result.bvid!)),
      );
      return;
    }
    if (result.aid != null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => VideoDetailPage(bvid: IdUtils.av2bv(result.aid!))),
      );
      return;
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('链接：$url')),
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
