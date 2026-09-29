import 'package:flutter/material.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';

import 'package:winwin/common/widgets/video_card/video_card_h.dart';
import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/search.dart';
import 'package:winwin/models/search/result.dart';
import 'package:winwin/models/search/search_type.dart';
import 'package:winwin/pages/bangumi/bangumi_detail_page.dart';
import 'package:winwin/pages/member/member_space_page.dart';
import 'package:winwin/pages/search/services/search_history_service.dart';
import 'package:winwin/pages/video/detail_page.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/utils/grid.dart';
import 'package:winwin/utils/image_utils.dart';
import 'package:winwin/utils/num_utils.dart';

/// 搜索面板 — 单个 Tab 对应的结果列表。
///
/// 移植自 PiliPlus 的 `CommonSearchPanel`，去除 GetX 依赖。
/// 统一处理分页加载、Loading/Error/Success 状态。
class SearchPanel extends StatefulWidget {
  const SearchPanel({
    super.key,
    required this.keyword,
    required this.searchType,
  });

  final String keyword;
  final SearchType searchType;

  @override
  State<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends State<SearchPanel>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  final List<dynamic> _items = [];
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  bool _firstLoaded = false;
  String? _errorMsg;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadData();
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
      if (!_hasMore || _loading || !_firstLoaded) return;
      if (_scrollController.hasClients &&
          _scrollController.position.hasContentDimensions) {
        final pos = _scrollController.position;
        if (pos.maxScrollExtent <= 0) {
          _loadMore();
        }
      }
    });
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.hasContentDimensions &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _loadData() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _errorMsg = null;
      if (_page == 1) _firstLoaded = false;
    });

    final res = await SearchHttp.searchByType(
      searchType: widget.searchType,
      keyword: widget.keyword,
      page: _page,
    );

    if (!mounted) return;
    setState(() {
      _loading = false;
      _firstLoaded = true;
      switch (res) {
        case Success(:final response):
          final list = response.list ?? [];
          if (_page == 1) _items.clear();
          _items.addAll(list);
          _hasMore = list.length >= 20;
          if (_hasMore) _page++;
        case Error(:final errMsg):
          _errorMsg = errMsg ?? '加载失败';
        case Loading():
          break;
      }
    });
    _checkAutoLoad();
  }

  void _loadMore() {
    if (!_loading && _hasMore && _firstLoaded) {
      _loadData();
    }
  }

  Future<void> _onRefresh() async {
    _page = 1;
    _hasMore = true;
    await _loadData();
  }

  SliverGridDelegate _getGridDelegate() {
    switch (widget.searchType) {
      case SearchType.video:
        return Grid.videoCardHDelegate(
          maxCrossAxisExtent: 440.0,
          mainAxisExtent: 110.0,
        );
      case SearchType.biliUser:
        return Grid.userCardDelegate(
          maxCrossAxisExtent: 440.0,
          mainAxisExtent: 76.0,
        );
      case SearchType.liveRoom:
        return Grid.videoCardHDelegate(
          maxCrossAxisExtent: 440.0,
          mainAxisExtent: 110.0,
        );
      case SearchType.mediaBangumi:
      case SearchType.mediaFt:
        return Grid.pgcCardDelegate(
          maxCrossAxisExtent: 440.0,
          mainAxisExtent: 130.0,
        );
      case SearchType.article:
        return Grid.videoCardHDelegate(
          maxCrossAxisExtent: 440.0,
          mainAxisExtent: 110.0,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_firstLoaded && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_firstLoaded && _items.isEmpty && _errorMsg != null) {
      return _buildErrorView();
    }
    if (_firstLoaded && _items.isEmpty) {
      return _buildEmptyView();
    }
    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(Style.safeSpace),
            sliver: SliverGrid.builder(
              gridDelegate: _getGridDelegate(),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                if (index >= _items.length - 4) {
                  _loadMore();
                }
                return _buildItem(_items[index]);
              },
            ),
          ),
          SliverToBoxAdapter(
            child: _buildFooter(),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(dynamic item) {
    return switch (widget.searchType) {
      SearchType.video => _buildVideoCard(item as SearchVideoItemModel),
      SearchType.biliUser => _buildUserCard(item as SearchUserItemModel),
      SearchType.liveRoom => _buildLiveCard(item as SearchLiveItemModel),
      SearchType.mediaBangumi || SearchType.mediaFt =>
        _buildPgcCard(item as SearchPgcItemModel),
      SearchType.article => _buildArticleCard(item as SearchArticleItemModel),
    };
  }

  // ─────────────────────────── 视频卡片 ───────────────────────────

  Widget _buildVideoCard(SearchVideoItemModel item) {
    return VideoCardH(
      videoItem: item,
      coverWidth: 144,
      onTap: () {
        if (item.mid != null && (item.author?.isNotEmpty ?? false)) {
          SearchHistoryService().addVisitedUser(
            mid: item.mid!,
            name: item.author!,
            face: item.face ?? '',
          );
        }
        if (item.bvid != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VideoDetailPage(bvid: item.bvid!),
            ),
          );
        }
      },
    );
  }

  // ─────────────────────────── 用户卡片 ───────────────────────────

  Widget _buildUserCard(SearchUserItemModel item) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () {
          if (item.mid != null && (item.uname?.isNotEmpty ?? false)) {
            SearchHistoryService().addVisitedUser(
              mid: item.mid!,
              name: item.uname!,
              face: item.upic ?? '',
            );
          }
          if (item.mid != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MemberSpacePage(mid: item.mid!),
              ),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              ClipOval(
                child: CachedNetworkImage(
                  imageUrl: ImageUtils.thumbnailUrl(item.upic, type: 'avatar'),
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  memCacheWidth: ImageUtils.decodeClamp(48, context, max: 256),
                  memCacheHeight: ImageUtils.decodeClamp(48, context, max: 256),
                  placeholder: (_, _) => Container(
                    color: theme.colorScheme.surfaceContainer,
                  ),
                  errorBuilder: (_, _, _) => Container(
                    color: theme.colorScheme.surfaceContainer,
                    child: const Icon(Icons.person),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.uname ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (item.level != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text(
                              'Lv${item.level}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '粉丝: ${NumUtils.formatNum(item.fans)}  视频: ${NumUtils.formatNum(item.videos)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, color: theme.colorScheme.outline),
                    ),
                    if (item.verifyInfo != null &&
                        item.verifyInfo!.isNotEmpty)
                      Text(
                        item.verifyInfo!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11, color: theme.colorScheme.outline),
                      ),
                  ],
                ),
              ),
              if (item.isLive == 1)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: biliPink,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '直播中',
                    style: TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────── 直播卡片 ───────────────────────────

  Widget _buildLiveCard(SearchLiveItemModel item) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () {
          // 直播间跳转暂未实现，显示提示
          showToast(
            context,
            '直播功能暂未接入：${item.uname} 的直播间',
            duration: const Duration(seconds: 2),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(Style.radiusSm),
                child: SizedBox(
                  width: 144,
                  height: 144 * 9 / 16,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: ImageUtils.thumbnailUrl(item.cover,
                            width: 144, height: 81),
                        fit: BoxFit.cover,
                        memCacheWidth:
                            ImageUtils.decodeClamp(144, context, max: 1080),
                        memCacheHeight:
                            ImageUtils.decodeClamp(81, context, max: 1080),
                        placeholder: (_, _) => Container(
                          color: theme.colorScheme.surfaceContainer,
                        ),
                        errorBuilder: (_, _, _) => Container(
                          color: theme.colorScheme.surfaceContainer,
                          child: const Icon(Icons.error_outline),
                        ),
                      ),
                      Positioned(
                        left: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: biliPink,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text(
                            '${NumUtils.formatNum(item.online)}人气',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 10),
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
                      item.title ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.person_outline,
                            size: 13, color: theme.colorScheme.outline),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            item.uname ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12, color: theme.colorScheme.outline),
                          ),
                        ),
                      ],
                    ),
                    if (item.cateName != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.cateName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11, color: theme.colorScheme.outline),
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

  // ─────────────────────────── 番剧/影视卡片 ───────────────────────────

  Widget _buildPgcCard(SearchPgcItemModel item) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
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
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(Style.radiusSm),
                child: SizedBox(
                  width: 80,
                  height: 114,
                  child: CachedNetworkImage(
                    imageUrl: ImageUtils.thumbnailUrl(item.cover,
                        width: 80, height: 114),
                    fit: BoxFit.cover,
                    memCacheWidth:
                        ImageUtils.decodeClamp(80, context, max: 1080),
                    memCacheHeight:
                        ImageUtils.decodeClamp(114, context, max: 1080),
                    placeholder: (_, _) => Container(
                      color: theme.colorScheme.surfaceContainer,
                    ),
                    errorBuilder: (_, _, _) => Container(
                      color: theme.colorScheme.surfaceContainer,
                      child: const Icon(Icons.error_outline),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    if (item.orgTitle != null &&
                        item.orgTitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.orgTitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11, color: theme.colorScheme.outline),
                      ),
                    ],
                    const SizedBox(height: 4),
                    if (item.areas != null || item.styles != null)
                      Text(
                        [item.areas, item.styles]
                            .where((s) => s != null && s.isNotEmpty)
                            .join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11, color: theme.colorScheme.outline),
                      ),
                    const Spacer(),
                    if (item.indexShow != null)
                      Text(
                        item.indexShow!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11,
                            color: biliPink,
                            fontWeight: FontWeight.w500),
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

  // ─────────────────────────── 专栏卡片 ───────────────────────────

  Widget _buildArticleCard(SearchArticleItemModel item) {
    final theme = Theme.of(context);
    final hasImg = item.imageUrls != null && item.imageUrls!.isNotEmpty;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () {
          showToast(
            context,
            '专栏功能暂未接入：${item.title}',
            duration: const Duration(seconds: 2),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasImg) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(Style.radiusSm),
                  child: SizedBox(
                    width: 120,
                    height: 94,
                    child: CachedNetworkImage(
                      imageUrl: ImageUtils.thumbnailUrl(item.imageUrls!.first,
                          width: 120, height: 94),
                      fit: BoxFit.cover,
                      memCacheWidth:
                          ImageUtils.decodeClamp(120, context, max: 1080),
                      memCacheHeight:
                          ImageUtils.decodeClamp(94, context, max: 1080),
                      placeholder: (_, _) => Container(
                        color: theme.colorScheme.surfaceContainer,
                      ),
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    if (item.desc != null && item.desc!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.desc!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11, color: theme.colorScheme.outline),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      '${NumUtils.formatNum(item.view)}阅读 · ${NumUtils.formatNum(item.like)}喜欢',
                      style: TextStyle(
                          fontSize: 11, color: theme.colorScheme.outline),
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

  // ─────────────────────────── 状态视图 ───────────────────────────

  Widget _buildFooter() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(Style.md),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (!_hasMore) {
      return Padding(
        padding: const EdgeInsets.all(Style.md),
        child: Center(
          child: Text(
            '没有更多了',
            style: TextStyle(
                color: Theme.of(context).colorScheme.outline, fontSize: 12),
          ),
        ),
      );
    }
    if (_errorMsg != null) {
      return Padding(
        padding: const EdgeInsets.all(Style.md),
        child: Center(
          child: TextButton(
            onPressed: _loadMore,
            child: Text(_errorMsg!),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: Style.sm),
          Text(_errorMsg!),
          const SizedBox(height: Style.md),
          OutlinedButton(onPressed: _onRefresh, child: const Text('重试')),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off,
              size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: Style.sm),
          Text(
            '没有找到相关内容',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ],
      ),
    );
  }
}
