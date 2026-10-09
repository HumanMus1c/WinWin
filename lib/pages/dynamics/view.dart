import 'package:material_ui/material_ui.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import 'package:winwin/common/skeleton/skeleton.dart';
import 'package:winwin/common/skeleton/video_card_v.dart';
import 'package:winwin/common/widgets/dyn/dyn_action_bar.dart';
import 'package:winwin/common/widgets/image/image_gallery_viewer.dart';
import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/common/widgets/p_badge.dart';
import 'package:winwin/common/widgets/refresh_indicator.dart';
import 'package:winwin/core/account/account_service.dart';
import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/common/widgets/demo_editable.dart';
import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/core/demo/demo_overrides.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/http/dyn.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/pages/article/article_page.dart';
import 'package:winwin/pages/bangumi/bangumi_detail_page.dart';
import 'package:winwin/pages/dynamics/detail_page.dart';
import 'package:winwin/pages/live/live_room_page.dart';
import 'package:winwin/pages/member/member_space_page.dart';
import 'package:winwin/pages/video/detail_page.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/utils/bilibili_url_parser.dart';
import 'package:winwin/utils/grid.dart';
import 'package:winwin/utils/id_utils.dart';
import 'package:winwin/utils/image_utils.dart';
import 'package:winwin/utils/num_utils.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/core/shell/app_routes.dart';
import 'package:winwin/core/shell/app_scaffold.dart';

/// 推送动态页。
void showDynamicsPage(BuildContext context) {
  Navigator.of(context).push(
    AppRoute<void>(builder: (_) => const DynamicsPage()),
  );
}

/// 动态页（对齐 PiliPlus 与 BiliPai 响应式排版）。
///
/// 顶部 TabBar 切换动态类型（全部、视频、追番、专栏）。
/// 齐次分类（视频、追番）采用标准网格；异质分类（全部、专栏）采用多列自适应瀑布流。
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
    _DynTabData(label: '追番', type: 'pgc'),
    _DynTabData(label: '专栏', type: 'article'),
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
    return AppScaffold(
      title: '动态',
      // 仅保留分类标签条（无标题栏），TabBar 直接作为 topBar 槽位。
      topBar: TabBar(
        controller: _tabController,
        tabs: _tabs.map((t) => Tab(text: t.label)).toList(),
        dividerHeight: 0,
        indicatorSize: TabBarIndicatorSize.label,
        labelPadding: const EdgeInsets.symmetric(horizontal: Style.md),
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

/// 单个动态 tab 页：下拉刷新 + 列表/宫格/瀑布流 + 分页加载。
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

  /// 演示模式：本地生成的占位动态数量（滚动追加，不拉取云端）。
  int _demoExtra = 8;

  /// 演示模式：上次追加行的滚动位置（需继续滚动约半屏后才再追加）。
  double _demoLastAppendAt = double.negativeInfinity;

  /// 点赞状态记忆（跨瀑布流滚动重建保留，刷新时清空）。
  final Map<String, bool> _likedState = {};
  final Map<String, int> _likeCountState = {};

  bool get _isVideoTab => widget.type == 'video';
  bool get _isPgcTab => widget.type == 'pgc';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    AccountService().addListener(_onAccountChanged);
    _scrollController.addListener(_onScroll);
    _load(refresh: true);
    // 演示模式切换时重建（内容骨架即时生效）。
    Pref.demoModeNotifier.addListener(_onDemoChanged);
  }

  void _onDemoChanged() {
    if (!mounted) return;
    setState(() {});
    if (!Pref.demoMode && _state is Loading) {
      _load(refresh: true);
    }
  }

  @override
  void dispose() {
    AccountService().removeListener(_onAccountChanged);
    Pref.demoModeNotifier.removeListener(_onDemoChanged);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _checkAutoLoad() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_hasMore || _loading) return;
      if (_scrollController.hasClients &&
          _scrollController.position.hasContentDimensions) {
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
    // 演示模式：不拉取云端（滚动追加在 _onScroll 中本地处理）。
    if (Pref.demoMode) return;
    if (_loading) return;
    if (!refresh && !_hasMore) return;
    _loading = true;
    if (refresh) {
      _offset = null;
      _items.clear();
      _likedState.clear();
      _likeCountState.clear();
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
    if (!_scrollController.hasClients ||
        !_scrollController.position.hasContentDimensions) {
      return;
    }
    final pos = _scrollController.position;
    if (pos.pixels < pos.maxScrollExtent - 240) return;
    // 演示模式：本地追加"一行"（数量随列数）；到达底部后需继续滚动约半屏
    // 才会再次追加，避免连续触发追加多行。
    if (Pref.demoMode) {
      if (pos.pixels <= _demoLastAppendAt + pos.viewportDimension * 0.5) {
        return;
      }
      _demoLastAppendAt = pos.pixels;
      final perRow = (pos.viewportDimension / 460).floor().clamp(2, 4);
      setState(() => _demoExtra += perRow);
      return;
    }
    _load(refresh: false);
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
                      sliver: switch (widget.type) {
                        'video' => _buildVideoGrid(),
                        'pgc' => _buildPgcGrid(),
                        'article' => _buildArticleMasonryGrid(),
                        _ => _buildAllMasonryGrid(),
                      },
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

  /// 视频 Tab 宫格排版（齐次纵向视频卡片网格）。
  Widget _buildVideoGrid() {
    final gridDelegate = Grid.videoCardVDelegate(
      mainAxisExtent: MediaQuery.textScalerOf(context).scale(90),
    );
    return SliverGrid.builder(
      gridDelegate: gridDelegate,
      itemCount: _items.length + (Pref.demoMode ? _demoExtra : 0),
      itemBuilder: (context, index) {
        if (Pref.demoMode) {
          return index < _items.length
              ? _buildDemoDynCard(_items[index].id.hashCode,
                  item: _items[index])
              : _buildDemoDynCard(index);
        }
        if (index == _items.length - 1) {
          _onScroll();
        }
        return _DynVideoCard(item: _items[index]);
      },
    );
  }

  /// 追番 Tab 宫格排版（齐次纵向剧集卡片网格）。
  Widget _buildPgcGrid() {
    final gridDelegate = Grid.videoCardVDelegate(
      mainAxisExtent: MediaQuery.textScalerOf(context).scale(90),
    );
    return SliverGrid.builder(
      gridDelegate: gridDelegate,
      itemCount: _items.length + (Pref.demoMode ? _demoExtra : 0),
      itemBuilder: (context, index) {
        if (Pref.demoMode) {
          return index < _items.length
              ? _buildDemoDynCard(_items[index].id.hashCode,
                  item: _items[index])
              : _buildDemoDynCard(index);
        }
        if (index == _items.length - 1) {
          _onScroll();
        }
        return _DynPgcCard(item: _items[index]);
      },
    );
  }

  /// 全部 Tab 自适应多列瀑布流排版（解决异质卡片在标准网格中的行间留白浪费问题）。
  Widget _buildAllMasonryGrid() {
    return SliverMasonryGrid.extent(
      maxCrossAxisExtent: 440.0,
      mainAxisSpacing: Style.cardSpace,
      crossAxisSpacing: Style.cardSpace,
      childCount: _items.length + (Pref.demoMode ? _demoExtra : 0),
      itemBuilder: (context, index) {
        if (Pref.demoMode) {
          return index < _items.length
              ? _buildDemoDynCard(_items[index].id.hashCode,
                  item: _items[index])
              : _buildDemoDynCard(index);
        }
        if (index == _items.length - 1) {
          _onScroll();
        }
        return _buildDynCard(_items[index]);
      },
    );
  }

  /// 专栏 Tab 自适应多列瀑布流排版。
  Widget _buildArticleMasonryGrid() {
    return SliverMasonryGrid.extent(
      maxCrossAxisExtent: 420.0,
      mainAxisSpacing: Style.cardSpace,
      crossAxisSpacing: Style.cardSpace,
      childCount: _items.length + (Pref.demoMode ? _demoExtra : 0),
      itemBuilder: (context, index) {
        if (Pref.demoMode) {
          return index < _items.length
              ? _buildDemoDynCard(_items[index].id.hashCode,
                  item: _items[index])
              : _buildDemoDynCard(index);
        }
        if (index == _items.length - 1) {
          _onScroll();
        }
        return _buildDynCard(_items[index]);
      },
    );
  }

  Widget _buildDynCard(DynItemModel item) {
    if (Pref.demoMode) return _buildDemoDynCard(item.id.hashCode, item: item);
    return _DynCard(
      item: item,
      liked: _likedState[item.id],
      likeCount: _likeCountState[item.id],
      onLikeChanged: (liked, count) {
        _likedState[item.id] = liked;
        _likeCountState[item.id] = count;
      },
    );
  }

  /// 演示模式：动态占位卡（真实条目保留原点击导航；本地条目进入演示详情）。
  Widget _buildDemoDynCard(int seed, {DynItemModel? item}) {
    final VoidCallback onTap;
    if (item == null) {
      onTap = () {
        if (_isVideoTab || _isPgcTab) {
          Navigator.push(
            context,
            AppRoute(
              builder: (_) => VideoDetailPage(bvid: 'BV1demo$seed'),
            ),
          );
        } else {
          Navigator.push(
            context,
            AppRoute(
              builder: (_) => DynamicDetailPage(dynamicId: 'demo_$seed'),
            ),
          );
        }
      };
    } else if (_isVideoTab) {
      final bvid = item.archive?.bvid;
      onTap = () {
        if (bvid == null || bvid.isEmpty) return;
        Navigator.push(
          context,
          AppRoute(
            builder: (_) => VideoDetailPage(
              bvid: bvid,
              cover: item.archive?.cover,
              heroTag: 'dyn_$bvid',
            ),
          ),
        );
      };
    } else if (_isPgcTab) {
      onTap = () {
        final pgc = item.pgc;
        final url = pgc?.jumpUrl;
        final result = (url != null && url.isNotEmpty)
            ? BilibiliUrlParser.parseDeepLink(url)
            : null;
        if (result != null && result.isBangumi) {
          Navigator.push(
            context,
            AppRoute(
              builder: (_) => BangumiDetailPage(
                seasonId: result.seasonId,
                epId: result.epId,
                mediaId: result.mediaId,
              ),
            ),
          );
        } else if (result?.bvid != null) {
          Navigator.push(
            context,
            AppRoute(
              builder: (_) => VideoDetailPage(bvid: result!.bvid!),
            ),
          );
        } else if (item.archive?.bvid != null) {
          Navigator.push(
            context,
            AppRoute(
              builder: (_) => VideoDetailPage(
                bvid: item.archive!.bvid!,
                cover: pgc?.cover ?? item.archive?.cover,
              ),
            ),
          );
        }
      };
    } else {
      onTap = () {
        Navigator.push(
          context,
          AppRoute(
            builder: (_) => DynamicDetailPage(item: item),
          ),
        );
      };
    }
    return _DemoDynCard(seed: seed, onTap: onTap);
  }

  Widget _buildSkeleton() {
    final isGridTab = _isVideoTab || _isPgcTab;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            Style.safeSpace,
            Style.sm,
            Style.safeSpace,
            Style.xxl * 2,
          ),
          sliver: isGridTab
              ? SliverGrid.builder(
                  gridDelegate: Grid.videoCardVDelegate(),
                  itemBuilder: (context, index) => const VideoCardVSkeleton(),
                  itemCount: 12,
                )
              : SliverMasonryGrid.extent(
                  maxCrossAxisExtent: 440.0,
                  mainAxisSpacing: Style.cardSpace,
                  crossAxisSpacing: Style.cardSpace,
                  childCount: 8,
                  itemBuilder: (context, index) => const _DynCardSkeleton(),
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

/// 演示模式：动态占位卡（作者=程序图标+程序名；文案灰色占位；保留互动按钮）。
class _DemoDynCard extends StatelessWidget {
  const _DemoDynCard({required this.seed, this.onTap});

  final int seed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = AppThemeHost.of(context).colors;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Style.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const SkeletonCircle(size: 36),
                  const SizedBox(width: Style.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            AppIcon(
                              AppIcons.profile(),
                              size: 13,
                              color: cs.outline,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              kDemoDisplayName,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const SkeletonLine(width: 60, height: 10),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Style.sm),
              const SkeletonLine(width: double.infinity, height: 13),
              const SizedBox(height: 6),
              const SkeletonLine(width: 200, height: 13),
              const SizedBox(height: Style.sm),
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  decoration: BoxDecoration(
                    color: skeletonBlockColor(context),
                    borderRadius: BorderRadius.circular(Style.radiusSm),
                  ),
                ),
              ),
              const SizedBox(height: Style.sm),
              _DemoDynActionBar(seed: seed),
            ],
          ),
        ),
      ),
    );
  }
}

/// 演示模式：动态互动栏（转发/评论/点赞；数值随机、双击可编辑、本地可点）。
class _DemoDynActionBar extends StatefulWidget {
  const _DemoDynActionBar({required this.seed});

  final int seed;

  @override
  State<_DemoDynActionBar> createState() => _DemoDynActionBarState();
}

class _DemoDynActionBarState extends State<_DemoDynActionBar> {
  bool _liked = false;

  @override
  Widget build(BuildContext context) {
    final outline = AppThemeHost.of(context).colors.outline;
    Widget item(Widget icon, String key, {bool active = false}) {
      final color = active ? biliPink : outline;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 4),
          DemoInlineEditNumber(
            overrideKey: key,
            value: DemoOverrides.count(key, min: 10, max: 99999),
            builder: (context, v) => Text(
              NumUtils.formatNum(v?.toInt()),
              style: TextStyle(fontSize: 11, color: color),
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        item(
          AppIcon(AppIcons.repost(), size: 15, color: outline),
          'demo.dyn.${widget.seed}.repost',
        ),
        item(
          AppIcon(AppIcons.comment(), size: 15, color: outline),
          'demo.dyn.${widget.seed}.comment',
        ),
        InkWell(
          onTap: () => setState(() => _liked = !_liked),
          borderRadius: BorderRadius.circular(4),
          child: item(
            AppIcon(
              AppIcons.like(active: _liked),
              size: 15,
              color: _liked ? biliPink : outline,
            ),
            'demo.dyn.${widget.seed}.like',
            active: _liked,
          ),
        ),
      ],
    );
  }
}

/// 动态瀑布流骨架屏组件（无 Expanded，适配 MasonryGrid 无界高度）。
class _DynCardSkeleton extends StatelessWidget {
  const _DynCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final color = ColorScheme.of(context).onInverseSurface;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Style.md),
        child: Skeleton(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: Style.sm),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(width: 100, height: 12, color: color),
                      const SizedBox(height: 4),
                      Container(width: 60, height: 10, color: color),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: Style.sm),
              Container(width: double.infinity, height: 14, color: color),
              const SizedBox(height: 6),
              Container(width: 200, height: 14, color: color),
              const SizedBox(height: Style.sm),
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(Style.radiusSm),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 视频 Tab 专属纵向视频卡片（对齐 VideoCardV 视觉规范）。
class _DynVideoCard extends StatelessWidget {
  const _DynVideoCard({required this.item});

  final DynItemModel item;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final shapes = tokens.shapes;
    final radius = shapes.medium;
    final archive = item.archive;
    final bvid = archive?.bvid;
    final cover = archive?.cover;
    final title = archive?.title ?? item.text ?? '';
    final durationText = archive?.durationText;
    final play = archive?.play;
    final danmaku = archive?.danmaku;
    final badge = archive?.badge;

    return RepaintBoundary(
      child: Card(
        child: InkWell(
        onTap: () {
          if (bvid == null || bvid.isEmpty) return;
          Navigator.push(
            context,
            AppRoute(
              builder: (_) => VideoDetailPage(
                bvid: bvid,
                cover: cover,
                heroTag: 'dyn_$bvid',
              ),
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
                        heroTag: bvid != null ? 'dyn_$bvid' : null,
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
                      if (badge != null && badge.isNotEmpty)
                        Positioned(
                          right: 6,
                          top: 6,
                          child: PBadge(
                            text: badge,
                            type: PBadgeType.badge,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            // 内容区
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(height: 1.35),
                  ),
                    if (item.author?.name != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          item.author!.name!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: tokens.colors.outline,
                          ),
                        ),
                      ),
                    // 播放与弹幕数统计
                    Row(
                      spacing: 3,
                      children: [
                        AppIcon(AppIcons.viewCount(),
                          size: 13,
                          color: tokens.colors.outline.withValues(alpha: 0.8),
                        ),
                        Text(
                          NumUtils.formatNum(play),
                          style: TextStyle(
                            fontSize: 12,
                            color: tokens.colors.outline.withValues(alpha: 0.8),
                          ),
                        ),
                        const SizedBox(width: 4),
                        AppIcon(AppIcons.danmakuCount(),
                          size: 13,
                          color: tokens.colors.outline.withValues(alpha: 0.8),
                        ),
                        Text(
                          NumUtils.formatNum(danmaku),
                          style: TextStyle(
                            fontSize: 12,
                            color: tokens.colors.outline.withValues(alpha: 0.8),
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
    ),
    );
  }
}

/// 追番 Tab 专属纵向剧集卡片。
class _DynPgcCard extends StatelessWidget {
  const _DynPgcCard({required this.item});

  final DynItemModel item;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final shapes = tokens.shapes;
    final radius = shapes.medium;
    final pgc = item.pgc;
    final cover = pgc?.cover ?? item.archive?.cover;
    final title = pgc?.title ?? item.archive?.title ?? item.text ?? '';
    final badge = pgc?.badge;
    final play = pgc?.play ?? item.archive?.play;
    final danmaku = pgc?.danmaku ?? item.archive?.danmaku;

    return Card(
      child: InkWell(
        onTap: () {
          if (pgc?.jumpUrl != null && pgc!.jumpUrl!.isNotEmpty) {
            _handleUrl(context, pgc.jumpUrl!);
          } else if (item.archive?.bvid != null) {
            Navigator.push(
              context,
              AppRoute(
                builder: (_) => VideoDetailPage(
                  bvid: item.archive!.bvid!,
                  cover: cover,
                ),
              ),
            );
          }
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
                      ),
                      if (badge != null && badge.isNotEmpty)
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: PBadge(
                            text: badge,
                            type: PBadgeType.badge,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            // 内容区
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(height: 1.35),
                  ),
                    if (item.author?.name != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          item.author!.name!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: tokens.colors.outline,
                          ),
                        ),
                      ),
                    // 播放与弹幕数统计
                    Row(
                      spacing: 3,
                      children: [
                        AppIcon(AppIcons.viewCount(),
                          size: 13,
                          color: tokens.colors.outline.withValues(alpha: 0.8),
                        ),
                        Text(
                          NumUtils.formatNum(play),
                          style: TextStyle(
                            fontSize: 12,
                            color: tokens.colors.outline.withValues(alpha: 0.8),
                          ),
                        ),
                        if (danmaku != null) ...[
                          const SizedBox(width: 4),
                          AppIcon(AppIcons.danmakuCount(),
                            size: 13,
                            color: tokens.colors.outline.withValues(alpha: 0.8),
                          ),
                          Text(
                            NumUtils.formatNum(danmaku),
                            style: TextStyle(
                              fontSize: 12,
                              color: tokens.colors.outline.withValues(alpha: 0.8),
                            ),
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

  void _handleUrl(BuildContext context, String url) {
    final result = BilibiliUrlParser.parseDeepLink(url);
    if (result.isBangumi) {
      Navigator.push(
        context,
        AppRoute(
          builder: (_) => BangumiDetailPage(
            seasonId: result.seasonId,
            epId: result.epId,
            mediaId: result.mediaId,
          ),
        ),
      );
      return;
    }
    if (result.bvid != null) {
      Navigator.push(
        context,
        AppRoute(builder: (_) => VideoDetailPage(bvid: result.bvid!)),
      );
      return;
    }
    if (result.aid != null) {
      Navigator.push(
        context,
        AppRoute(builder: (_) => VideoDetailPage(bvid: IdUtils.av2bv(result.aid!))),
      );
      return;
    }
    if (result.isLive || result.roomId != null) {
      Navigator.push(
        context,
        AppRoute(
          builder: (_) => LiveRoomPage(roomId: result.roomId!),
        ),
      );
      return;
    }
    if (result.isArticle || result.articleId != null) {
      Navigator.push(
        context,
        AppRoute(
          builder: (_) => ArticlePage(id: result.articleId!.toString()),
        ),
      );
      return;
    }
    if (result.dynamicId != null) {
      Navigator.push(
        context,
        AppRoute(
          builder: (_) => DynamicDetailPage(dynamicId: result.dynamicId),
        ),
      );
      return;
    }
    showToast(context, '链接：$url');
  }
}

/// 全部 Tab 综合动态卡片：作者 + 正文/富文本 + 视频/图文/Opus/专栏/追番/转发/直播/商品 + 互动统计。
class _DynCard extends StatelessWidget {
  const _DynCard({
    required this.item,
    this.liked,
    this.likeCount,
    this.onLikeChanged,
  });

  final DynItemModel item;

  /// 外部点赞态/点赞数覆盖（列表页跨滚动重建记忆）。
  final bool? liked;
  final int? likeCount;

  /// 点赞成功回写（供列表页记忆）。
  final void Function(bool liked, int likeCount)? onLikeChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final author = item.author;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            AppRoute(
              builder: (_) => DynamicDetailPage(item: item),
            ),
          );
        },
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
                                  style: tokens.text.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (author?.pubAction != null && author!.pubAction!.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Text(
                                  author.pubAction!,
                                  style: tokens.text.labelSmall?.copyWith(
                                    color: cs.outline,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (item.pubTs != null)
                            Text(
                              _formatTime(item.pubTs!),
                              style: tokens.text.labelSmall?.copyWith(
                                color: cs.outline,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              // 正文（富文本解析，防超长溢出设置最大行数）
              if (item.text != null && item.text!.isNotEmpty) ...[
                const SizedBox(height: Style.sm),
                if (item.richTextNodes.isNotEmpty)
                  Text.rich(
                    TextSpan(
                      children: _buildRichSpans(context, item.richTextNodes, cs.primary),
                    ),
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.text.bodyMedium,
                  )
                else
                  Text(
                    item.text!,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.text.bodyMedium,
                  ),
              ],
              // 动态主体内容（按类型分发）
              if (item.isForward && item.orig != null) ...[
                const SizedBox(height: Style.sm),
                _buildForwardContent(context, item.orig!),
              ] else if (item.isVideo && item.archive != null && (item.archive!.bvid != null || item.archive!.title != null)) ...[
                const SizedBox(height: Style.sm),
                _buildVideoPreview(context, item.archive!),
              ] else if (item.isPgc && item.pgc != null) ...[
                const SizedBox(height: Style.sm),
                _buildPgcPreview(context, item.pgc!),
              ] else if (item.draw != null && item.draw!.items.isNotEmpty) ...[
                const SizedBox(height: Style.sm),
                _buildDrawGrid(context, item.draw!.items),
              ] else if (item.opus != null) ...[
                const SizedBox(height: Style.sm),
                _buildOpusCard(context, item.opus!),
              ] else if (item.article != null) ...[
                const SizedBox(height: Style.sm),
                _buildArticleCard(context, item.article!),
              ] else if (item.live != null) ...[
                const SizedBox(height: Style.sm),
                _buildLiveCard(context, item.live!),
              ] else if (item.none != null) ...[
                const SizedBox(height: Style.sm),
                _buildNoneCard(context, item.none!),
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
                DynActionBar(
                  item: item,
                  liked: liked,
                  likeCount: likeCount,
                  onChanged: onLikeChanged,
                  onComment: () {
                    Navigator.push(
                      context,
                      AppRoute(
                        builder: (_) => DynamicDetailPage(
                          item: item,
                          focusComment: true,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 转发动态内容渲染（嵌套原动态卡片，递归深度 ≤ 1）。
  Widget _buildForwardContent(BuildContext context, DynItemModel orig) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final origAuthor = orig.author;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          AppRoute(
            builder: (_) => DynamicDetailPage(item: orig),
          ),
        );
      },
      borderRadius: BorderRadius.circular(Style.radiusMd),
      child: Container(
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
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.text.bodyMedium,
                )
              else
                Text(
                  orig.text!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.text.bodyMedium,
                ),
            ],
            if (orig.isVideo && orig.archive != null && (orig.archive!.bvid != null || orig.archive!.title != null)) ...[
              const SizedBox(height: Style.sm),
              _buildVideoPreview(context, orig.archive!),
            ] else if (orig.isPgc && orig.pgc != null) ...[
              const SizedBox(height: Style.sm),
              _buildPgcPreview(context, orig.pgc!),
            ] else if (orig.draw != null && orig.draw!.items.isNotEmpty) ...[
              const SizedBox(height: Style.sm),
              _buildDrawGrid(context, orig.draw!.items),
            ] else if (orig.opus != null) ...[
              const SizedBox(height: Style.sm),
              _buildOpusCard(context, orig.opus!),
            ] else if (orig.article != null) ...[
              const SizedBox(height: Style.sm),
              _buildArticleCard(context, orig.article!),
            ] else if (orig.live != null) ...[
              const SizedBox(height: Style.sm),
              _buildLiveCard(context, orig.live!),
            ] else if (orig.none != null) ...[
              const SizedBox(height: Style.sm),
              _buildNoneCard(context, orig.none!),
            ],
          ],
        ),
      ),
    );
  }

  /// 追番剧集动态卡片预览。
  Widget _buildPgcPreview(BuildContext context, DynPgc pgc) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final cover = pgc.cover;

    return InkWell(
      onTap: () {
        if (pgc.jumpUrl != null && pgc.jumpUrl!.isNotEmpty) {
          _handleJumpUrl(context, pgc.jumpUrl!);
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
            if (cover != null && cover.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(Style.radiusXs),
                child: SizedBox(
                  width: 90,
                  height: 60,
                  child: Stack(
                    children: [
                      NetworkImgLayer(
                        src: cover,
                        width: 90,
                        height: 60,
                        borderRadius: BorderRadius.circular(Style.radiusXs),
                      ),
                      if (pgc.badge != null && pgc.badge!.isNotEmpty)
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: PBadge(text: pgc.badge!, type: PBadgeType.badge),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: Style.sm),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pgc.title ?? '剧集更新',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (pgc.play != null || pgc.danmaku != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (pgc.play != null) ...[
                          AppIcon(AppIcons.viewCount(), size: 12, color: cs.outline),
                          const SizedBox(width: 2),
                          Text(
                            NumUtils.formatNum(pgc.play),
                            style: TextStyle(fontSize: 11, color: cs.outline),
                          ),
                        ],
                        if (pgc.danmaku != null) ...[
                          const SizedBox(width: 6),
                          AppIcon(AppIcons.danmakuCount(), size: 12, color: cs.outline),
                          const SizedBox(width: 2),
                          Text(
                            NumUtils.formatNum(pgc.danmaku),
                            style: TextStyle(fontSize: 11, color: cs.outline),
                          ),
                        ],
                      ],
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

  /// 图文九宫格图片渲染（1 图自然比例/单大图，2-4 图 2x2，5-9 图 3x3）。
  Widget _buildDrawGrid(BuildContext context, List<DynDrawItem> pics) {
    if (pics.isEmpty) return const SizedBox.shrink();
    final imageUrls = [
      for (final p in pics)
        if (p.src != null && p.src!.isNotEmpty) p.src!,
    ];

    if (pics.length == 1) {
      final item = pics.first;
      final w = item.width ?? 16;
      final h = item.height ?? 9;
      final aspect = (w > 0 && h > 0) ? (w / h).clamp(0.7, 2.0) : 16 / 9;
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 240),
        child: AspectRatio(
          aspectRatio: aspect,
          child: GestureDetector(
            onTap: () {
              if (imageUrls.isNotEmpty) {
                showImageGallery(
                  context,
                  imageUrls: imageUrls,
                  thumbnailUrls: imageUrls,
                  initialIndex: 0,
                );
              }
            },
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
        ),
      );
    }

    final crossAxisCount = pics.length == 4 ? 2 : (pics.length >= 3 ? 3 : 2);
    final displayPics = pics.take(9).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : 380.0;
        const spacing = 4.0;
        final rawItemWidth = (totalWidth - spacing * (crossAxisCount - 1)) / crossAxisCount;
        final itemWidth = rawItemWidth.clamp(50.0, 130.0);

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: displayPics.asMap().entries.map((entry) {
            final idx = entry.key;
            final pic = entry.value;
            return GestureDetector(
              onTap: () {
                if (imageUrls.isNotEmpty) {
                  showImageGallery(
                    context,
                    imageUrls: imageUrls,
                    thumbnailUrls: imageUrls,
                    initialIndex: idx,
                  );
                }
              },
              child: SizedBox(
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
              ),
            );
          }).toList(),
        );
      },
    );
  }

  /// Opus 新版图文/文章卡片渲染。
  Widget _buildOpusCard(BuildContext context, DynOpus opus) {
    final tokens = AppThemeHost.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (opus.title != null && opus.title!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              opus.title!,
              style: tokens.text.titleSmall?.copyWith(
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
              style: tokens.text.bodyMedium,
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
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final cover = article.covers.isNotEmpty ? article.covers.first : null;

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Style.radiusMd),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        onTap: () {
          final id = article.id;
          if (id != null && id > 0) {
            Navigator.push(
              context,
              AppRoute(
                builder: (_) => ArticlePage(
                  id: id.toString(),
                  title: article.title,
                  cover: cover,
                  desc: article.desc,
                ),
              ),
            );
          } else if (article.jumpUrl != null && article.jumpUrl!.isNotEmpty) {
            _handleJumpUrl(context, article.jumpUrl!);
          }
        },
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
                      style: tokens.text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (article.desc != null && article.desc!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        article.desc!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: tokens.text.bodySmall?.copyWith(
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
      ),
    );
  }

  /// 直播卡片渲染（UP主开播或直播推荐）。
  Widget _buildLiveCard(BuildContext context, DynLive live) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final isLiving = live.liveStatus == 1 || live.badge == '直播中';

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Style.radiusMd),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        onTap: () {
          var roomId = live.roomId;
          if ((roomId == null || roomId <= 0) &&
              live.jumpUrl != null &&
              live.jumpUrl!.isNotEmpty) {
            roomId = BilibiliUrlParser.parse(live.jumpUrl!).roomId;
          }
          if (roomId != null && roomId > 0) {
            Navigator.push(
              context,
              AppRoute(
                builder: (_) => LiveRoomPage(
                  roomId: roomId!,
                  title: live.title,
                  uname: live.uname,
                  cover: live.cover,
                ),
              ),
            );
          } else if (live.jumpUrl != null && live.jumpUrl!.isNotEmpty) {
            _handleJumpUrl(context, live.jumpUrl!);
          }
        },
        borderRadius: BorderRadius.circular(Style.radiusMd),
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
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: isLiving ? Colors.redAccent : Colors.grey.shade600,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isLiving ? Icons.sensors : Icons.sensors_off,
                                color: Colors.white,
                                size: 10,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                isLiving ? (live.badge ?? 'LIVE') : '已结束',
                                style: const TextStyle(
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
                      live.title ?? (isLiving ? '正在直播' : '直播已结束'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (live.descFirst != null && live.descFirst!.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: cs.secondaryContainer,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              live.descFirst!,
                              style: TextStyle(
                                fontSize: 10,
                                color: cs.onSecondaryContainer,
                              ),
                            ),
                          )
                        else if (live.uname != null && live.uname!.isNotEmpty)
                          Text(
                            live.uname!,
                            style: tokens.text.labelSmall?.copyWith(color: cs.outline),
                          ),
                        if (live.watchedShow != null && live.watchedShow!.isNotEmpty) ...[
                          const Spacer(),
                          Icon(AppIcons.eye(), size: 12, color: cs.outline),
                          const SizedBox(width: 3),
                          Text(
                            live.watchedShow!,
                            style: tokens.text.labelSmall?.copyWith(color: cs.outline),
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
      ),
    );
  }

  /// 失效/空动态卡片渲染。
  Widget _buildNoneCard(BuildContext context, DynNone none) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(Style.radiusSm),
      ),
      child: Row(
        spacing: 6,
        children: [
          AppIcon(AppIcons.info(), size: 16, color: cs.outline),
          Expanded(
            child: Text(
              none.tips ?? '动态内容已失效',
              style: TextStyle(fontSize: 12, color: cs.outline),
            ),
          ),
        ],
      ),
    );
  }

  /// 附加商品卡模块渲染。
  Widget _buildGoodsCard(BuildContext context, DynAdditional additional) {
    if (additional.goodsItems.isEmpty) return const SizedBox.shrink();
    final item = additional.goodsItems.first;
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;

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
                    style: tokens.text.bodySmall?.copyWith(fontWeight: FontWeight.w500),
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
            AppIcon(AppIcons.goodsEntry(), size: 16, color: cs.primary),
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
          AppRoute(
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
              ),
            ),
            if (archive.badge != null && archive.badge!.isNotEmpty)
              Positioned(
                right: 6,
                top: 6,
                child: PBadge(
                  text: archive.badge!,
                  type: PBadgeType.badge,
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
                            AppIcon(AppIcons.viewCount(),
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
                            AppIcon(AppIcons.danmakuCount(),
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
              ImageUtils.thumbnailUrl(node.emojiUrl, type: 'emote'),
              width: 20,
              height: 20,
              cacheWidth: ImageUtils.decodeClamp(20, context, max: 128),
              cacheHeight: ImageUtils.decodeClamp(20, context, max: 128),
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
                  AppRoute(builder: (_) => VideoDetailPage(bvid: bvid)),
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
                  AppRoute(builder: (_) => MemberSpacePage(mid: mid)),
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
    if (result.isBangumi) {
      Navigator.push(
        context,
        AppRoute(
          builder: (_) => BangumiDetailPage(
            seasonId: result.seasonId,
            epId: result.epId,
            mediaId: result.mediaId,
          ),
        ),
      );
      return;
    }
    if (result.bvid != null) {
      Navigator.push(
        context,
        AppRoute(builder: (_) => VideoDetailPage(bvid: result.bvid!)),
      );
      return;
    }
    if (result.aid != null) {
      Navigator.push(
        context,
        AppRoute(builder: (_) => VideoDetailPage(bvid: IdUtils.av2bv(result.aid!))),
      );
      return;
    }
    if (result.isLive || result.roomId != null) {
      Navigator.push(
        context,
        AppRoute(
          builder: (_) => LiveRoomPage(roomId: result.roomId!),
        ),
      );
      return;
    }
    if (result.isArticle || result.articleId != null) {
      Navigator.push(
        context,
        AppRoute(
          builder: (_) => ArticlePage(id: result.articleId!.toString()),
        ),
      );
      return;
    }
    if (result.dynamicId != null) {
      Navigator.push(
        context,
        AppRoute(
          builder: (_) => DynamicDetailPage(dynamicId: result.dynamicId),
        ),
      );
      return;
    }
    showToast(context, '链接：$url');
  }

  void _gotoMember(BuildContext context, int? mid) {
    if (mid == null || mid <= 0) return;
    Navigator.push(
      context,
      AppRoute(builder: (_) => MemberSpacePage(mid: mid)),
    );
  }

  static String _formatTime(int ts) {
    if (ts <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.isNegative || diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 30) return '${diff.inDays}天前';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
