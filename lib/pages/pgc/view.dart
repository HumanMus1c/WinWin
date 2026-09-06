import 'package:flutter/material.dart';

import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/common/widgets/refresh_indicator.dart';
import 'package:winwin/core/account/account_service.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/member.dart';
import 'package:winwin/http/pgc.dart';
import 'package:winwin/pages/bangumi/bangumi_detail_page.dart';
import 'package:winwin/pages/login/login_page.dart';
import 'package:winwin/theme/app_shapes.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/utils/grid.dart';
import 'package:winwin/utils/num_utils.dart';

/// 番剧二级分类枚举
enum PgcSubTab {
  myFollow('我的追番'),
  hot('热门追番');

  final String label;
  const PgcSubTab(this.label);
}

/// 番剧页（Phase 7.7.4）。
///
/// 包含“我的追番”和“热门追番”两个二级分类器。
/// 顶部吸顶分类胶囊栏，子视图基于 [IndexedStack] 懒加载并保留各自滚动与数据状态。
class PgcPage extends StatefulWidget {
  const PgcPage({super.key});

  @override
  State<PgcPage> createState() => _PgcPageState();
}

class _PgcPageState extends State<PgcPage>
    with AutomaticKeepAliveClientMixin {
  late PgcSubTab _selectedSubTab;
  late final Set<PgcSubTab> _visitedTabs;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // 已登录默认进入“我的追番”，未登录默认进入“热门追番”
    _selectedSubTab = AccountService().isLogin
        ? PgcSubTab.myFollow
        : PgcSubTab.hot;
    _visitedTabs = {_selectedSubTab};
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final shapes = theme.extension<AppShapes>() ?? AppShapes.ios;

    // 嵌入 HomePage 时顶部留白 112 避开浮动顶栏(60) + 分类标签行(36)
    return Padding(
      padding: const EdgeInsets.only(top: 112),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 二级分类器胶囊栏（固定吸顶）
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Style.safeSpace,
              vertical: Style.xs,
            ),
            child: Row(
              children: PgcSubTab.values.map((tab) {
                final isSelected = tab == _selectedSubTab;
                return Padding(
                  padding: const EdgeInsets.only(right: Style.sm),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: shapes.pillBorder,
                      onTap: () {
                        if (_selectedSubTab != tab) {
                          setState(() {
                            _selectedSubTab = tab;
                            _visitedTabs.add(tab);
                          });
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
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
                        child: Text(
                          tab.label,
                          style: TextStyle(
                            color: isSelected
                                ? cs.primary
                                : cs.onSurfaceVariant,
                            fontSize: 12.5,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          // 分类内容区（懒加载 IndexedStack 保留各自滚动位置与状态）
          Expanded(
            child: IndexedStack(
              index: _selectedSubTab.index,
              children: PgcSubTab.values.map((tab) {
                if (!_visitedTabs.contains(tab)) {
                  return const SizedBox.shrink();
                }
                return switch (tab) {
                  PgcSubTab.myFollow => const _MyFollowBangumiView(),
                  PgcSubTab.hot => const _HotBangumiView(),
                };
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

/// 热门追番视图：全站高热度番剧索引网格。
class _HotBangumiView extends StatefulWidget {
  const _HotBangumiView();

  @override
  State<_HotBangumiView> createState() => _HotBangumiViewState();
}

class _HotBangumiViewState extends State<_HotBangumiView>
    with AutomaticKeepAliveClientMixin {
  LoadingState<List<Map<String, dynamic>>?> _state = LoadingState.loading();
  final List<Map<String, dynamic>> _items = [];
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
    final res = await PgcHttp.pgcIndex(page: _page);
    if (!mounted) return;
    switch (res) {
      case Success(:final response):
        if (response == null || response.isEmpty) {
          _hasMore = false;
        } else {
          _items.addAll(response);
          _hasMore = response.length >= 20;
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
    final gridDelegate = SliverGridDelegateWithExtentAndRatio(
      maxCrossAxisExtent: 180,
      mainAxisSpacing: Style.cardSpace,
      crossAxisSpacing: Style.cardSpace,
      childAspectRatio: 2 / 3,
      mainAxisExtent: MediaQuery.textScalerOf(context).scale(60),
    );

    return AppRefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n is ScrollUpdateNotification || n is ScrollEndNotification) {
            _onScroll();
          }
          return false;
        },
        child: switch (_state) {
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
                        Style.xs,
                        Style.safeSpace,
                        Style.md,
                      ),
                      sliver: SliverGrid(
                        gridDelegate: gridDelegate,
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            if (i >= _items.length - 2) {
                              _onScroll();
                            }
                            return _PgcCard(item: _items[i]);
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
          Center(child: Text('暂无番剧')),
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

/// 我的追番视图：已登录用户追番列表 + 未登录守卫。
class _MyFollowBangumiView extends StatefulWidget {
  const _MyFollowBangumiView();

  @override
  State<_MyFollowBangumiView> createState() => _MyFollowBangumiViewState();
}

class _MyFollowBangumiViewState extends State<_MyFollowBangumiView>
    with AutomaticKeepAliveClientMixin {
  LoadingState<SpaceBangumiData> _state = LoadingState.loading();
  final List<SpaceBangumiItem> _items = [];
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
    AccountService().addListener(_onAccountChanged);
    if (AccountService().isLogin) {
      _load(refresh: true);
    }
  }

  @override
  void dispose() {
    AccountService().removeListener(_onAccountChanged);
    _scrollController.removeListener(_onScroll);
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
      });
    }
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
    if (!AccountService().isLogin) return;
    if (!refresh && !_hasMore) return;
    _loading = true;
    if (refresh) {
      _page = 1;
      _items.clear();
      _hasMore = true;
      setState(() => _state = LoadingState.loading());
    }
    await ensureBootstrap();
    final mid = Accounts.main.mid > 0
        ? Accounts.main.mid
        : (AccountService().userInfo?.mid ?? 0);
    final res = await MemberHttp.spaceBangumi(
      mid: mid,
      type: 1,
      pn: _page,
      ps: 30,
    );
    if (!mounted) return;
    switch (res) {
      case Success(:final response):
        final list = response.list;
        if (list.isEmpty) {
          _hasMore = false;
        } else {
          _items.addAll(list);
          _hasMore = !response.isEnd && list.length >= 20;
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

    // 未登录展示登录引导
    if (!AccountService().isLogin) {
      return _buildLoginPrompt(context);
    }

    final gridDelegate = SliverGridDelegateWithExtentAndRatio(
      maxCrossAxisExtent: 180,
      mainAxisSpacing: Style.cardSpace,
      crossAxisSpacing: Style.cardSpace,
      childAspectRatio: 2 / 3,
      mainAxisExtent: MediaQuery.textScalerOf(context).scale(60),
    );

    return AppRefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n is ScrollUpdateNotification || n is ScrollEndNotification) {
            _onScroll();
          }
          return false;
        },
        child: switch (_state) {
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
                        Style.xs,
                        Style.safeSpace,
                        Style.md,
                      ),
                      sliver: SliverGrid(
                        gridDelegate: gridDelegate,
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            if (i >= _items.length - 2) {
                              _onScroll();
                            }
                            return _MyBangumiCard(item: _items[i]);
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
    );
  }

  Widget _buildLoginPrompt(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.account_circle_outlined,
            size: 56,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            '登录后查看我的追番',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => showLoginPage(context),
            icon: const Icon(Icons.login),
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
          Center(child: Text('暂无追番')),
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

/// 我的追番卡片：封面 + 标题 + 更新话数/已看进度 + 角标。
class _MyBangumiCard extends StatelessWidget {
  const _MyBangumiCard({required this.item});

  final SpaceBangumiItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final title = item.title ?? '';
    final cover = item.cover;
    final badge = item.badge;
    final indexShow = item.indexShow;
    final progress = item.progress;
    final follow = item.follow;

    final subtitle = progress?.isNotEmpty == true
        ? progress!
        : (follow != null ? '${NumUtils.formatNum(follow)} 系列追番' : '');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BangumiDetailPage(
                seasonId: item.seasonId,
                mediaId: item.mediaId,
              ),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  fit: StackFit.expand,
                  children: [
                    NetworkImgLayer(
                      src: cover,
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      borderRadius: BorderRadius.zero,
                    ),
                    if (badge?.isNotEmpty == true)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.pink.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            badge!,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    if (indexShow?.isNotEmpty == true)
                      Positioned(
                        left: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            indexShow!,
                            style: const TextStyle(
                              fontSize: 9,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(Style.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.outline,
                        ),
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
}

/// 热门番剧卡片：封面 + 标题 + 角标（分数/追番人数）。
class _PgcCard extends StatelessWidget {
  const _PgcCard({required this.item});

  final Map<String, dynamic> item;

  String? get _cover => item['cover']?.toString();
  String get _title => item['title']?.toString() ?? '';
  // API 字段为 `subTitle`（大写 S）— 番剧标语；`index_show` 为集数信息。
  String? get _subtitle => item['subTitle']?.toString();
  // `order` 是展示用字符串（如 "1770.6万追番"），直接显示。
  String? get _orderText => item['order']?.toString();
  String? get _badge => item['badge']?.toString();
  // `score` 是顶层字符串（如 "9.7"），需解析为 double。
  double? get _score {
    final raw = item['score'];
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }

  int? get _seasonId {
    final v = item['season_id'] ?? item['seasonId'];
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '');
  }

  int? get _mediaId {
    final v = item['media_id'] ?? item['mediaId'];
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          final sId = _seasonId;
          final mId = _mediaId;
          if (sId != null || mId != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => BangumiDetailPage(
                  seasonId: sId,
                  mediaId: mId,
                ),
              ),
            );
          } else {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              SnackBar(
                content: Text(_title),
                duration: const Duration(seconds: 1),
              ),
            );
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  fit: StackFit.expand,
                  children: [
                    NetworkImgLayer(
                      src: _cover,
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      borderRadius: BorderRadius.zero,
                    ),
                    if (_badge?.isNotEmpty == true)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.pink.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _badge!,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    if (_score != null && (_badge == null || _badge!.isEmpty))
                      Positioned(
                        right: 4,
                        top: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _score!.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    if (_orderText != null && _orderText!.isNotEmpty)
                      Positioned(
                        left: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _orderText!,
                            style: const TextStyle(
                              fontSize: 9,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(Style.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (_subtitle != null && _subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        _subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.outline,
                        ),
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
}
