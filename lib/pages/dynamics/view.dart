import 'package:flutter/material.dart';

import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/common/widgets/p_badge.dart';
import 'package:winwin/common/widgets/refresh_indicator.dart';
import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/http/dyn.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/pages/member/member_space_page.dart';
import 'package:winwin/pages/video/detail_page.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/utils/num_utils.dart';

/// 动态页（Phase 7.7.1）。
///
/// 参照 PiliPlus 的 `DynamicsPage`：顶部 TabBar 切换动态类型，
/// 主体为动态流列表。当前实现「全部」+「视频」两个 tab，后续可扩展。
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

/// 单个动态 tab 页：下拉刷新 + 列表 + 分页加载。
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

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load(refresh: true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
    if (pos.pixels >= pos.maxScrollExtent - 200) {
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
                        Style.xxl * 2,
                      ),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            if (i == _items.length) {
                              return _buildTrailer();
                            }
                            return _DynCard(item: _items[i]);
                          },
                          childCount: _items.length + 1,
                        ),
                      ),
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
    if (!_hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: Style.lg),
        child: Center(child: Text('没有更多了')),
      );
    }
    return const SizedBox.shrink();
  }
}

/// 单条动态卡片：作者 + 正文 + 视频（若有）。
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
      margin: const EdgeInsets.only(bottom: Style.sm),
      child: Padding(
        padding: const EdgeInsets.all(Style.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 作者行
            Row(
              children: [
                GestureDetector(
                  onTap: () => _gotoMember(context, author?.mid),
                  child: NetworkImgLayer(
                    src: author?.face,
                    width: 36,
                    height: 36,
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
            // 视频稿件
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
            NetworkImgLayer(
              src: archive.cover,
              width: double.infinity,
              height: 180,
              borderRadius: BorderRadius.circular(Style.radiusSm),
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
                      Colors.black.withValues(alpha: 0.6),
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
                            Icon(Icons.play_circle_outlined,
                                size: 12, color: Colors.white70),
                            const SizedBox(width: 2),
                            Text(
                              NumUtils.formatNum(archive.play),
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
