import 'package:flutter_miuix/miuix.dart' show MiuixCard, MiuixCardDefaults, MiuixPressable, MiuixSquircleBorder;
import 'package:material_ui/material_ui.dart';

import 'package:winwin/common/skeleton/skeleton.dart';
import 'package:winwin/common/widgets/demo_mask.dart';
import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/common/widgets/refresh_indicator.dart';
import 'package:winwin/core/account/account_service.dart';
import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/http/live.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/pages/live/live_room_page.dart';
import 'package:winwin/pages/login/login_page.dart';
import 'package:winwin/pages/member/member_space_page.dart';
import 'package:winwin/theme/app_shapes.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/utils/num_utils.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/core/shell/app_routes.dart';

/// 直播二级分类导航条目。
class LiveCategoryTab {
  final int id; // 0 为推荐，-1 为我的关注，>0 为父级分区 ID
  final String label;
  final bool isFollow;

  const LiveCategoryTab({
    required this.id,
    required this.label,
    this.isFollow = false,
  });

  static const LiveCategoryTab recommend =
      LiveCategoryTab(id: 0, label: '推荐');
  static const LiveCategoryTab follow =
      LiveCategoryTab(id: -1, label: '我的关注', isFollow: true);
}

/// 直播页（Phase 7.7.2）。
///
/// 包含“推荐”、“我的关注”以及 API 分区（网游、手游、单机游戏、娱乐、电台、虚拟主播等）二级分类。
/// 顶部吸顶胶囊栏支持平滑横向滚动，子视图基于 [IndexedStack] 懒加载并保留各自滚动与数据状态。
class LivePage extends StatefulWidget {
  const LivePage({super.key});

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage>
    with AutomaticKeepAliveClientMixin {
  late List<LiveCategoryTab> _tabs;
  int _selectedIndex = 0;
  final Set<int> _visitedIndices = {0};
  final ScrollController _tabScrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // 默认展示官方预置的核心分类列表，保障首屏秒开
    _tabs = [
      LiveCategoryTab.recommend,
      LiveCategoryTab.follow,
      ...LiveAreaItem.defaultAreas.map(
        (a) => LiveCategoryTab(id: a.id, label: a.name),
      ),
    ];
    _fetchDynamicAreas();
  }

  @override
  void dispose() {
    _tabScrollController.dispose();
    super.dispose();
  }

  /// 异步拉取线上最新直播分区，热更新二级分类栏
  Future<void> _fetchDynamicAreas() async {
    await ensureBootstrap();
    final res = await LiveHttp.liveAreaList();
    if (!mounted) return;
    if (res case Success(:final response)) {
      if (response.isNotEmpty) {
        final currentSelected = _tabs[_selectedIndex];
        final newTabs = [
          LiveCategoryTab.recommend,
          LiveCategoryTab.follow,
          ...response.map((a) => LiveCategoryTab(id: a.id, label: a.name)),
        ];
        var newIndex = newTabs.indexWhere((t) => t.id == currentSelected.id);
        if (newIndex < 0) newIndex = 0;
        setState(() {
          _tabs = newTabs;
          _selectedIndex = newIndex;
          _visitedIndices.add(newIndex);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final shapes = theme.extension<AppShapes>() ?? AppShapes.miuix;

    // 嵌入 HomePage 时需顶部留白以避开浮动顶栏(60) + 一级分类标签行(36)
    return Padding(
      padding: const EdgeInsets.only(top: 112),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 二级分类器胶囊栏（固定吸顶横向滚动）
          _buildSubTabBar(cs, shapes),
          // 分类内容区（懒加载 IndexedStack 保留各自滚动位置与状态）
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: List.generate(_tabs.length, (i) {
                if (!_visitedIndices.contains(i)) {
                  return const SizedBox.shrink();
                }
                final tab = _tabs[i];
                if (tab.isFollow) {
                  return const _LiveFollowSubView();
                }
                return _LiveAreaSubView(
                  key: ValueKey(tab.id),
                  parentAreaId: tab.id,
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubTabBar(ColorScheme cs, AppShapes shapes) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        controller: _tabScrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: Style.safeSpace,
          vertical: Style.xs,
        ),
        itemCount: _tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: Style.sm),
        itemBuilder: (context, index) {
          final isSelected = index == _selectedIndex;
          final tab = _tabs[index];
          return Material(
            color: Colors.transparent,
            child: MiuixPressable(
              borderRadius: shapes.pillBorder,
              onPressed: () {
                if (_selectedIndex != index) {
                  setState(() {
                    _selectedIndex = index;
                    _visitedIndices.add(index);
                  });
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? cs.primary.withValues(alpha: 0.18)
                      : cs.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: shapes.pillBorder,
                  border: Border.all(
                    color: isSelected
                        ? cs.primary.withValues(alpha: 0.45)
                        : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: Center(
                  child: Text(
                    tab.label,
                    style: TextStyle(
                      color: isSelected ? cs.primary : cs.onSurfaceVariant,
                      fontSize: 12.5,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 演示模式：直播页骨架网格（近似 _LiveCard 布局）。
Widget _buildLiveSkeletonGrid({int count = 8}) {
  return CustomScrollView(
    physics: const AlwaysScrollableScrollPhysics(),
    slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          Style.safeSpace,
          Style.sm,
          Style.safeSpace,
          Style.md,
        ),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 280,
            childAspectRatio: 0.85,
            mainAxisSpacing: Style.cardSpace,
            crossAxisSpacing: Style.cardSpace,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => const Skeleton(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SkeletonBox(
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                  SizedBox(height: Style.sm),
                  SkeletonLine(width: double.infinity, height: 12),
                  SizedBox(height: 6),
                  SkeletonLine(width: 90, height: 10),
                ],
              ),
            ),
            childCount: count,
          ),
        ),
      ),
    ],
  );
}

/// 我的关注直播视图：已关注主播的正在直播网格。
class _LiveFollowSubView extends StatefulWidget {
  const _LiveFollowSubView();

  @override
  State<_LiveFollowSubView> createState() => _LiveFollowSubViewState();
}

class _LiveFollowSubViewState extends State<_LiveFollowSubView>
    with AutomaticKeepAliveClientMixin {
  LoadingState<LiveFollowData> _state = LoadingState.loading();
  final List<LiveItemModel> _items = [];
  int _page = 1;
  bool _hasMore = true;
  bool _loading = false;
  late final ScrollController _scrollController;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    if (AccountService().isLogin) {
      _load(refresh: true);
    }
  }

  @override
  void dispose() {
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

  Future<void> _load({required bool refresh}) async {
    if (_loading) return;
    if (!refresh && !_hasMore) return;
    _loading = true;
    if (refresh) {
      _page = 1;
      _items.clear();
      _hasMore = true;
      setState(() => _state = LoadingState.loading());
    }
    await ensureBootstrap();
    final res = await LiveHttp.liveFollow(page: _page);
    if (!mounted) return;
    switch (res) {
      case Success(:final response):
        if (response.list.isEmpty) {
          _hasMore = false;
        } else {
          _items.addAll(response.list);
          _hasMore = response.list.length >= 30;
          _page++;
        }
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
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      _load(refresh: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!AccountService().isLogin) {
      return _buildLoginPrompt(context);
    }
    return AppRefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n is ScrollUpdateNotification || n is ScrollEndNotification) {
            _onScroll();
          }
          return false;
        },
        child: DemoMask(
          skeleton: _buildLiveSkeletonGrid,
          child: () => switch (_state) {
            Loading() => const Center(child: CircularProgressIndicator()),
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
                          Style.md,
                        ),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 280,
                            childAspectRatio: 0.85,
                            mainAxisSpacing: Style.cardSpace,
                            crossAxisSpacing: Style.cardSpace,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, i) {
                              if (i >= _items.length - 2) {
                                _onScroll();
                              }
                              return _LiveCard(item: _items[i]);
                            },
                            childCount: _items.length,
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: _buildTrailer(),
                      ),
                      const SliverToBoxAdapter(
                        child: SizedBox(height: Style.xxl * 2),
                      ),
                    ],
                  ),
          },
        ),
      ),
    );
  }

  Widget _buildLoginPrompt(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(AppIcons.profile(),
            size: 56,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            '登录后查看我的关注直播',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () async {
              await showLoginPage(context);
              if (mounted && AccountService().isLogin) {
                _load(refresh: true);
              }
            },
            icon: AppIcon(AppIcons.loginSubmit()),
            label: const Text('登录'),
          ),
        ],
      ),
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
          Center(child: Text('暂无关注的主播在直播')),
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
    if (!_hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: Style.lg),
        child: Center(child: Text('没有更多了')),
      );
    }
    return const SizedBox.shrink();
  }
}

/// 分区/推荐直播视图：按 parentAreaId（0 为全站推荐）加载直播网格。
class _LiveAreaSubView extends StatefulWidget {
  final int parentAreaId;

  const _LiveAreaSubView({super.key, required this.parentAreaId});

  @override
  State<_LiveAreaSubView> createState() => _LiveAreaSubViewState();
}

class _LiveAreaSubViewState extends State<_LiveAreaSubView>
    with AutomaticKeepAliveClientMixin {
  LoadingState<LiveRecommendData> _state = LoadingState.loading();
  final List<LiveItemModel> _items = [];
  int _page = 1;
  bool _hasMore = true;
  bool _loading = false;
  late final ScrollController _scrollController;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    _load(refresh: true);
  }

  @override
  void dispose() {
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

  Future<void> _load({required bool refresh}) async {
    if (_loading) return;
    if (!refresh && !_hasMore) return;
    _loading = true;
    if (refresh) {
      _page = 1;
      _items.clear();
      _hasMore = true;
      setState(() => _state = LoadingState.loading());
    }
    await ensureBootstrap();
    final res = await LiveHttp.liveRecommend(
      page: _page,
      parentAreaId: widget.parentAreaId,
    );
    if (!mounted) return;
    switch (res) {
      case Success(:final response):
        if (response.list.isEmpty) {
          _hasMore = false;
        } else {
          _items.addAll(response.list);
          _hasMore = response.list.length >= 20;
          _page++;
        }
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
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      _load(refresh: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AppRefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n is ScrollUpdateNotification || n is ScrollEndNotification) {
            _onScroll();
          }
          return false;
        },
        child: DemoMask(
          skeleton: _buildLiveSkeletonGrid,
          child: () => switch (_state) {
            Loading() => const Center(child: CircularProgressIndicator()),
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
                          Style.md,
                        ),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 280,
                            childAspectRatio: 0.85,
                            mainAxisSpacing: Style.cardSpace,
                            crossAxisSpacing: Style.cardSpace,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, i) {
                              if (i >= _items.length - 2) {
                                _onScroll();
                              }
                              return _LiveCard(item: _items[i]);
                            },
                            childCount: _items.length,
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: _buildTrailer(),
                      ),
                      const SliverToBoxAdapter(
                        child: SizedBox(height: Style.xxl * 2),
                      ),
                    ],
                  ),
          },
        ),
      ),
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
          Center(child: Text('暂无直播')),
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
    if (!_hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: Style.lg),
        child: Center(child: Text('没有更多了')),
      );
    }
    return const SizedBox.shrink();
  }
}

/// 直播卡片：封面 + 标题 + 主播 + 人气 + 区域。
class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.item});

  final LiveItemModel item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = AppThemeHost.of(context);
    final cs = theme.colorScheme;
    return ClipPath(clipper: ShapeBorderClipper(shape: MiuixSquircleBorder(cornerRadius: MiuixCardDefaults.cornerRadius)), child: MiuixCard(
      child: MiuixPressable(
        onPressed: () {
          final roomId = item.roomId;
          if (roomId == null || roomId <= 0) return;
          Navigator.push(
            context,
            AppRoute(
              builder: (_) => LiveRoomPage(
                roomId: roomId,
                title: item.title,
                uname: item.uname,
                cover: item.cover,
              ),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面
            AspectRatio(
              aspectRatio: 16 / 10,
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  fit: StackFit.expand,
                  children: [
                    NetworkImgLayer(
                      src: item.cover,
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      borderRadius: BorderRadius.zero,
                    ),
                    // 直播中标识
                    if (item.isLiving)
                      Positioned(
                        left: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AppIcon(AppIcons.recording(),
                                size: 10,
                                color: Colors.white,
                              ),
                              SizedBox(width: 2),
                              Text(
                                '直播中',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    // 人气
                    if (item.online != null)
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AppIcon(AppIcons.people(),
                                size: 10,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                NumUtils.formatNum(item.online),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // 文本信息
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(Style.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        final uid = item.uid;
                        if (uid != null && uid > 0) {
                          Navigator.push(
                            context,
                            AppRoute(
                              builder: (_) => MemberSpacePage(mid: uid),
                            ),
                          );
                        }
                      },
                      child: Row(
                        children: [
                          AppIcon(AppIcons.profile(),
                            size: 12,
                            color: cs.outline,
                          ),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(
                              item.uname ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tokens.text.labelSmall?.copyWith(
                                color: cs.outline,
                              ),
                            ),
                          ),
                          if (item.areaName != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: cs.secondaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                item.areaName!,
                                style: TextStyle(
                                  fontSize: 9,
                                  color: cs.onSecondaryContainer,
                                ),
                              ),
                            ),
                        ],
                      ),
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
}
