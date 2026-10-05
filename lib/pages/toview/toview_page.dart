import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'package:winwin/common/skeleton/video_card_h.dart';
import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/common/widgets/p_badge.dart';
import 'package:winwin/common/widgets/video_card/video_card_adapter.dart';
import 'package:winwin/common/widgets/video_card/video_context_menu.dart';
import 'package:winwin/core/account/account_service.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/core/event/event_bus.dart';
import 'package:winwin/core/log/api_blackbox.dart';
import 'package:winwin/core/log/app_logger.dart';
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
import 'package:winwin/theme/app_icons.dart';

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
  StreamSubscription<WatchLaterEvent>? _watchLaterSubscription;

  @override
  void initState() {
    super.initState();
    AccountService().addListener(_onAccountChanged);
    _scrollController.addListener(_onScroll);
    _initWatchLaterSubscription();
    _load(refresh: true);
  }

  void _initWatchLaterSubscription() {
    _watchLaterSubscription =
        EventBus().on<WatchLaterEvent>().listen((event) {
      if (!mounted) return;
      if (!event.inWatchLater) {
        final removed = _items.any((i) => i.aid == event.aid);
        if (removed) {
          setState(() {
            _items.removeWhere((i) => i.aid == event.aid);
            if (_totalCount != null && _totalCount! > 0) {
              _totalCount = _totalCount! - 1;
            }
          });
        }
      } else {
        _load(refresh: true);
      }
    });
  }

  @override
  void dispose() {
    _watchLaterSubscription?.cancel();
    _watchLaterSubscription = null;
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
        _page = 1;
        _totalCount = null;
        _hasMore = true;
        _loading = false;
        _isLoadingMore = false;
        _error = '请先登录';
      });
    }
  }

  void _checkAutoLoad() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_hasMore || _loading || _isLoadingMore) return;
      if (_scrollController.hasClients &&
          _scrollController.position.hasContentDimensions) {
        final pos = _scrollController.position;
        if (pos.maxScrollExtent <= 0) {
          _load();
        }
      }
    });
  }

  Future<void> _load({bool refresh = false}) async {
    await ensureBootstrap();
    if (refresh) {
      _page = 1;
      _hasMore = true;
      _items.clear();
      _totalCount = null;
      _loading = true;
      _isLoadingMore = false;
      _error = null;
      setState(() {});
    } else {
      if (!_hasMore || _isLoadingMore) return;
      _isLoadingMore = true;
      setState(() {});
    }

    if (!Accounts.main.isLogin) {
      ApiBlackbox.log('ToviewPage', 'Load aborted: Accounts.main is not login (${Accounts.main.runtimeType})');
      AppLogger.w('ToviewPage', 'Accounts.main is not login: ${Accounts.main.runtimeType}');
      setState(() {
        _loading = false;
        _isLoadingMore = false;
        _error = '请先登录';
      });
      return;
    }

    ApiBlackbox.log('ToviewPage', 'Fetching toviewList page=$_page');
    AppLogger.d('ToviewPage', 'Loading toview page $_page');
    final res = await ToviewHttp.toviewList(page: _page);
    if (!mounted) return;

    switch (res) {
      case Success(:final response):
        ApiBlackbox.log('ToviewPage', 'Success: ${response.list?.length} items, total count: ${response.count}');
        AppLogger.d('ToviewPage', 'Loaded ${response.list?.length} items, total count: ${response.count}');
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
        ApiBlackbox.log('ToviewPage', 'Error: $errMsg');
        AppLogger.e('ToviewPage', 'Load failed: $errMsg');
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
    if (_scrollController.hasClients &&
        _scrollController.position.hasContentDimensions) {
      final pos = _scrollController.position;
      if (pos.pixels >= pos.maxScrollExtent - 300) {
        _load();
      }
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
        EventBus().emit(WatchLaterEvent(
          aid: item.aid!,
          bvid: item.bvid,
          inWatchLater: false,
        ));
      case Error(:final errMsg):
        showToast(context, errMsg ?? '移除失败');
      case Loading():
        break;
    }
  }

  /// 打开稍后再看项：跳转视频详情页（番剧等无 bvid 类型暂不支持）。
  void _openItem(LaterItem item) {
    final bvid = item.bvid;
    if (bvid == null || bvid.isEmpty) {
      showToast(context, '暂不支持打开该类型内容');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VideoDetailPage(
          bvid: bvid,
          cover: item.pic,
          heroTag: 'toview_$bvid',
        ),
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
      showToast(context, '暂无可播放的视频');
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
        showToast(context, errMsg ?? '清空失败');
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
                  ? AppEmptyState(
                      icon: AppIcon(AppIcons.watchLater()),
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
    return RefreshIndicator(
      color: biliPink,
      onRefresh: () => _load(refresh: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(Style.safeSpace),
            sliver: SliverGrid.builder(
              gridDelegate: Grid.videoCardHDelegate(
                maxCrossAxisExtent: 440.0,
                mainAxisExtent: 110.0,
              ),
              itemCount: 12,
              itemBuilder: (context, index) => const VideoCardHSkeleton(
                coverWidth: 140,
                inCard: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 错误/未登录态：未登录用语义空态，其余用统一错误态（含重试）。
  Widget _buildError() {
    if (_error == '请先登录') {
      return const AppEmptyState(
        icon: Icon(Icons.account_circle_outlined),
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
    final shapes = theme.extension<AppShapes>() ?? AppShapes.miuix;
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

    final data = VideoCardData.from(item);
    Offset? lastTapPosition;

    return Card(
      child: InkWell(
        onTap: onTap,
        onSecondaryTapDown: (details) {
          lastTapPosition = details.globalPosition;
        },
        onSecondaryTapUp: (details) {
          showVideoContextMenu(
            context: context,
            position: details.globalPosition,
            data: data,
            videoItem: item,
            onRemove: onRemove,
          );
        },
        onLongPress: () {
          if (lastTapPosition != null) {
            showVideoContextMenu(
              context: context,
              position: lastTapPosition!,
              data: data,
              videoItem: item,
              onRemove: onRemove,
            );
          }
        },
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
                          heroTag: bvid != null && bvid.isNotEmpty ? 'toview_$bvid' : null,
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
                              AppIcon(AppIcons.viewCount(),
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
                              AppIcon(AppIcons.danmakuCount(),
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
                            VideoPopupMenu(
                              data: data,
                              videoItem: item,
                              onRemove: onRemove,
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: AppIcon(AppIcons.clear(), size: 14),
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
