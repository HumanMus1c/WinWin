import 'package:flutter/material.dart';

import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/common/widgets/refresh_indicator.dart';
import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/http/live.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/pages/member/member_space_page.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/utils/num_utils.dart';

/// 直播页（Phase 7.7.2）。
///
/// 参照 PiliPlus 的 `LivePage`：推荐直播网格 + 区域标签。
/// 当前实现推荐直播列表，点击卡片预留跳转直播间入口。
class LivePage extends StatefulWidget {
  const LivePage({super.key});

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage>
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
    final res = await LiveHttp.liveRecommend(page: _page);
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
    // 嵌入 HomePage 时需顶部留白以避开浮动顶栏 + 分类标签行。
    return Padding(
      padding: const EdgeInsets.only(top: 120),
      child: AppRefreshIndicator(
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
    final cs = theme.colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          // TODO: Phase 4 直播播放器集成后跳转直播间
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text('直播间 ${item.roomId} · 直播播放待集成'),
              duration: const Duration(seconds: 1),
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
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.fiber_manual_record,
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
                            const Icon(
                              Icons.people_alt_outlined,
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
                      style: theme.textTheme.bodyMedium?.copyWith(
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
                            MaterialPageRoute(
                              builder: (_) => MemberSpacePage(mid: uid),
                            ),
                          );
                        }
                      },
                      child: Row(
                        children: [
                          Icon(
                            Icons.person_outline,
                            size: 12,
                            color: cs.outline,
                          ),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(
                              item.uname ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
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
    );
  }
}
