import 'package:flutter/material.dart';

import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/common/widgets/p_badge.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/toview.dart';
import 'package:winwin/models/toview/toview_models.dart';
import 'package:winwin/pages/member/member_space_page.dart';
import 'package:winwin/pages/video/detail_page.dart';
import 'package:winwin/theme/app_shapes.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/app_empty_state.dart';
import 'package:winwin/utils/duration_utils.dart';
import 'package:winwin/utils/grid.dart';
import 'package:winwin/utils/num_utils.dart';

/// 稍后再看页面（移植自 PiliPlus `lib/pages/later/`，重构为自适应多列宫格排版）。
void showToviewPage(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const ToviewPage()),
  );
}

class ToviewPage extends StatefulWidget {
  const ToviewPage({super.key});

  @override
  State<ToviewPage> createState() => _ToviewPageState();
}

class _ToviewPageState extends State<ToviewPage> {
  final ScrollController _scrollController = ScrollController();
  final List<LaterItem> _items = [];
  int _page = 1;
  int? _totalCount;
  bool _hasMore = true;
  bool _loading = true;
  bool _isLoadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
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
      if (!_hasMore || _loading || _isLoadingMore) return;
      if (_scrollController.hasClients) {
        final pos = _scrollController.position;
        if (pos.maxScrollExtent <= 0) {
          _load();
        }
      }
    });
  }

  Future<void> _load({bool refresh = false}) async {
    if (refresh) {
      _page = 1;
      _hasMore = true;
      _items.clear();
      _loading = true;
      _isLoadingMore = false;
      setState(() {});
    } else {
      if (!_hasMore || _loading || _isLoadingMore) return;
      _isLoadingMore = true;
      setState(() {});
    }

    if (!Accounts.main.isLogin) {
      setState(() {
        _loading = false;
        _isLoadingMore = false;
        _error = '请先登录';
      });
      return;
    }

    final res = await ToviewHttp.toviewList(page: _page);
    if (!mounted) return;

    switch (res) {
      case Success(:final response):
        setState(() {
          _loading = false;
          _isLoadingMore = false;
          _error = null;
          _totalCount = response.count;
          if (response.list != null) _items.addAll(response.list!);
          _hasMore = _items.length < (_totalCount ?? 0) &&
              (response.list?.isNotEmpty ?? false);
          _page++;
        });
        _checkAutoLoad();
      case Error(:final errMsg):
        setState(() {
          _loading = false;
          _isLoadingMore = false;
          if (_items.isEmpty) {
            _error = errMsg ?? '加载失败';
          }
        });
      case Loading():
        break;
    }
  }

  void _onScroll() {
    if (!_hasMore || _loading || _isLoadingMore) return;
    if (_scrollController.hasClients) {
      final pos = _scrollController.position;
      if (pos.pixels >= pos.maxScrollExtent - 300) {
        _load();
      }
    } else {
      _load();
    }
  }

  Future<void> _removeItem(LaterItem item) async {
    if (item.aid == null) return;
    final res = await ToviewHttp.delToview('${item.aid}');
    if (!mounted) return;
    switch (res) {
      case Success():
        setState(() {
          _items.remove(item);
          if (_totalCount != null) _totalCount = _totalCount! - 1;
        });
      case Error(:final errMsg):
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(errMsg ?? '移除失败')),
        );
      case Loading():
        break;
    }
  }

  /// 打开稍后再看项：跳转视频详情页（番剧等无 bvid 类型暂不支持）。
  void _openItem(LaterItem item) {
    final bvid = item.bvid;
    if (bvid == null || bvid.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('暂不支持打开该类型内容')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VideoDetailPage(bvid: bvid, cover: item.pic),
      ),
    );
  }

  /// 播放全部视频（从第 1 个有效视频起播）。
  void _playAll() {
    final firstValid = _items.firstWhere(
      (item) => item.bvid != null && item.bvid!.isNotEmpty,
      orElse: () => LaterItem(),
    );
    if (firstValid.bvid != null && firstValid.bvid!.isNotEmpty) {
      _openItem(firstValid);
    } else {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('暂无可播放的视频')),
      );
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空稍后再看'),
        content: const Text('确定清空所有稍后再看？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final res = await ToviewHttp.clearToview();
    if (!mounted) return;
    switch (res) {
      case Success():
        setState(() {
          _items.clear();
          _hasMore = false;
          _totalCount = 0;
        });
      case Error(:final errMsg):
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(errMsg ?? '清空失败')),
        );
      case Loading():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('稍后再看'),
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: '清空',
              onPressed: _clearAll,
            ),
        ],
      ),
      floatingActionButton: _items.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _playAll,
              backgroundColor: biliPink,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.playlist_play),
              label: const Text('播放全部'),
            )
          : null,
      body: _loading && _items.isEmpty
          ? _buildSkeleton()
          : _error != null && _items.isEmpty
              ? _buildError()
              : _items.isEmpty
                  ? const AppEmptyState(
                      icon: Icons.watch_later_outlined,
                      title: '稍后再看列表为空',
                      subtitle: '把想看的视频加入稍后再看吧',
                    )
                  : NotificationListener<ScrollNotification>(
                      onNotification: (n) {
                        if (n is ScrollUpdateNotification || n is ScrollEndNotification) {
                          _onScroll();
                        }
                        return false;
                      },
                      child: RefreshIndicator(
                        color: biliPink,
                        onRefresh: () => _load(refresh: true),
                        child: CustomScrollView(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(
                                Style.safeSpace,
                                Style.safeSpace,
                                Style.safeSpace,
                                80,
                              ),
                              sliver: SliverGrid.builder(
                                gridDelegate: Grid.videoCardHDelegate(
                                  maxCrossAxisExtent: 440.0,
                                  mainAxisExtent: 110.0,
                                ),
                                itemCount: _items.length,
                                itemBuilder: (context, index) {
                                  if (index >= _items.length - 2) {
                                    _onScroll();
                                  }
                                  final item = _items[index];
                                  return _ToviewCard(
                                    item: item,
                                    onRemove: () => _removeItem(item),
                                    onTap: () => _openItem(item),
                                  );
                                },
                              ),
                            ),
                            if (_isLoadingMore)
                              const SliverToBoxAdapter(
                                child: Padding(
                                  padding: EdgeInsets.all(Style.md),
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: biliPink,
                                    ),
                                  ),
                                ),
                              )
                            else if (!_hasMore && _items.isNotEmpty)
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: Style.md),
                                  child: Center(
                                    child: Text(
                                      '没有更多了',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context).colorScheme.outline,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
    );
  }

  Widget _buildSkeleton() {
    return CustomScrollView(
      physics: const NeverScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(Style.safeSpace),
          sliver: SliverGrid.builder(
            gridDelegate: Grid.videoCardHDelegate(
              maxCrossAxisExtent: 440.0,
              mainAxisExtent: 110.0,
            ),
            itemCount: 12,
            itemBuilder: (context, index) => Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(Style.radiusSm),
                      child: Container(
                        width: 140,
                        height: 140 * 9 / 16,
                        color: Colors.grey.withValues(alpha: 0.15),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Container(
                            height: 14,
                            width: double.infinity,
                            color: Colors.grey.withValues(alpha: 0.15),
                          ),
                          Container(
                            height: 12,
                            width: 100,
                            color: Colors.grey.withValues(alpha: 0.15),
                          ),
                          Container(
                            height: 10,
                            width: 60,
                            color: Colors.grey.withValues(alpha: 0.15),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 错误/未登录态：未登录用语义空态，其余用统一错误态（含重试）。
  Widget _buildError() {
    if (_error == '请先登录') {
      return const AppEmptyState(
        icon: Icons.account_circle_outlined,
        title: '请先登录',
        subtitle: '登录后可查看稍后再看',
      );
    }
    return AppErrorState(
      message: _error ?? '加载失败',
      onRetry: () => _load(refresh: true),
    );
  }
}

/// 稍后再看多列横向卡片（对齐 PiliPlus 与 BiliPai 稍后再看规范）。
class _ToviewCard extends StatelessWidget {
  const _ToviewCard({
    required this.item,
    required this.onRemove,
    this.onTap,
  });

  final LaterItem item;
  final VoidCallback onRemove;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final shapes = theme.extension<AppShapes>() ?? AppShapes.ios;
    final radius = shapes.medium;
    final duration = item.duration ?? 0;
    final progress = item.progress ?? 0;
    final bvid = item.bvid;
    final owner = item.owner;
    final stat = item.stat;

    double progressFraction = 0.0;
    if (progress > 0 && duration > 0) {
      progressFraction = (progress / duration).clamp(0.0, 1.0);
    } else if (progress == -1) {
      progressFraction = 1.0;
    }

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.all(radius),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面与进度
              ClipRRect(
                borderRadius: BorderRadius.all(radius),
                child: SizedBox(
                  width: 140,
                  height: 140 * 9 / 16,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: NetworkImgLayer(
                          src: item.pic,
                          width: 140,
                          height: 140 * 9 / 16,
                          borderRadius: BorderRadius.all(radius),
                          heroTag: bvid != null && bvid.isNotEmpty ? 'cover_$bvid' : null,
                        ),
                      ),
                      if (duration > 0)
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: PBadge(
                            text: DurationUtils.formatDuration(duration),
                            type: PBadgeType.duration,
                          ),
                        ),
                      if (progressFraction > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: LinearProgressIndicator(
                            value: progressFraction,
                            minHeight: 2.5,
                            backgroundColor: Colors.black38,
                            valueColor: AlwaysStoppedAnimation(cs.primary),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // 右侧描述
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      item.title ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.35,
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (owner?.name != null && owner!.name!.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              if (owner.mid != null && owner.mid! > 0) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => MemberSpacePage(mid: owner.mid!),
                                  ),
                                );
                              }
                            },
                            child: Row(
                              children: [
                                Icon(Icons.person_outline, size: 12, color: cs.outline),
                                const SizedBox(width: 2),
                                Flexible(
                                  child: Text(
                                    owner.name!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: cs.outline,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (stat?.view != null) ...[
                              Icon(
                                Icons.play_circle_outlined,
                                size: 12,
                                color: cs.outline,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                NumUtils.formatNum(stat!.view),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.outline,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            if (stat?.danmaku != null) ...[
                              Icon(
                                Icons.subtitles_outlined,
                                size: 12,
                                color: cs.outline,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                NumUtils.formatNum(stat!.danmaku),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.outline,
                                ),
                              ),
                            ],
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.close, size: 14),
                              tooltip: '从稍后再看移除',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 24,
                                minHeight: 24,
                              ),
                              color: cs.outline,
                              onPressed: onRemove,
                            ),
                          ],
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
