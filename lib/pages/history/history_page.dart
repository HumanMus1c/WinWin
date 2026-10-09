import 'package:material_ui/material_ui.dart';

import 'package:winwin/common/skeleton/skeleton.dart';
import 'package:winwin/common/skeleton/video_card_h.dart';
import 'package:winwin/common/widgets/demo_mask.dart';
import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/common/widgets/p_badge.dart';
import 'package:winwin/core/account/account_service.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/core/demo/demo_overrides.dart';
import 'package:winwin/core/log/app_logger.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/http/history.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/models/history/history_models.dart';
import 'package:winwin/pages/member/member_space_page.dart';
import 'package:winwin/pages/video/detail_page.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/app_empty_state.dart';
import 'package:winwin/utils/date_utils.dart';
import 'package:winwin/utils/duration_utils.dart';
import 'package:winwin/utils/grid.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/core/shell/app_routes.dart';
import 'package:winwin/core/shell/app_dialogs.dart';
import 'package:winwin/core/shell/app_scaffold.dart';

/// 历史记录页面（移植自 PiliPlus `lib/pages/history/`，重构为自适应多列宫格排版）。
void showHistoryPage(BuildContext context) {
  Navigator.of(context).push(
    AppRoute<void>(builder: (_) => const HistoryPage()),
  );
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final ScrollController _scrollController = ScrollController();
  final List<HistoryItem> _items = [];
  int? _max;
  int? _viewAt;
  bool _hasMore = true;
  bool _loading = true;
  bool _isLoadingMore = false;
  String? _error;

  /// 演示模式：本地追加的演示卡片数量（滚动每次仅 +1 行）。
  int _demoExtra = 0;

  /// 演示模式：上次追加行的滚动位置（需继续滚动约半屏后才再追加）。
  double _demoLastAppendAt = double.negativeInfinity;

  @override
  void initState() {
    super.initState();
    AccountService().addListener(_onAccountChanged);
    _scrollController.addListener(_onScroll);
    _load(refresh: true);
    // 演示模式切换时重建（骨架即时生效）。
    Pref.demoModeNotifier.addListener(_onDemoChanged);
  }

  void _onDemoChanged() {
    if (!mounted) return;
    setState(() {});
    if (!Pref.demoMode && _items.isEmpty) {
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

  void _onAccountChanged() {
    if (!mounted) return;
    if (AccountService().isLogin) {
      _load(refresh: true);
    } else {
      setState(() {
        _items.clear();
        _max = null;
        _viewAt = null;
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
    // 演示模式：不拉取云端列表（滚动追加在 _onScroll 中本地处理）。
    if (Pref.demoMode) {
      _loading = false;
      return;
    }
    await ensureBootstrap();
    if (refresh) {
      _max = null;
      _viewAt = null;
      _hasMore = true;
      _items.clear();
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
      AppLogger.w('HistoryPage', 'Accounts.main is not login: ${Accounts.main.runtimeType}');
      setState(() {
        _loading = false;
        _isLoadingMore = false;
        _error = '请先登录';
      });
      return;
    }

    AppLogger.d('HistoryPage', 'Loading history max: $_max, viewAt: $_viewAt');
    final res = await HistoryHttp.historyList(
      max: _max,
      viewAt: _viewAt,
    );
    if (!mounted) return;

    switch (res) {
      case Success(:final response):
        AppLogger.d('HistoryPage', 'Loaded ${response.list?.length} items');
        setState(() {
          _loading = false;
          _isLoadingMore = false;
          _error = null;
          if (response.list != null) _items.addAll(response.list!);
          // 游标分页：优先使用服务端下发的 cursor，回退到末尾项推算
          if (response.cursor != null &&
              response.cursor!.max != null &&
              response.cursor!.max! > 0) {
            _max = response.cursor!.max;
            _viewAt = response.cursor!.viewAt;
            _hasMore = (response.list?.length ?? 0) >= 20 && _max != 0;
          } else if (response.list != null && response.list!.isNotEmpty) {
            final last = response.list!.last;
            _max = last.history.oid;
            _viewAt = last.viewAt;
            _hasMore = response.list!.length >= 20;
          } else {
            _hasMore = false;
          }
        });
        _checkAutoLoad();
      case Error(:final errMsg):
        AppLogger.e('HistoryPage', 'Load failed: $errMsg');
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
        // 演示模式：滚动仅本地追加"一行"（数量=视口列数），不请求云端。
        if (Pref.demoMode) {
          if (pos.pixels <= _demoLastAppendAt + pos.viewportDimension * 0.5) {
            return;
          }
          _demoLastAppendAt = pos.pixels;
          final perRow = (pos.viewportDimension / 460).floor().clamp(2, 8);
          setState(() => _demoExtra += perRow);
          return;
        }
        _load();
      }
    }
  }

  Future<void> _deleteItem(HistoryItem item) async {
    final res = await HistoryHttp.delHistory(item.delKid);
    if (!mounted) return;
    switch (res) {
      case Success():
        setState(() => _items.remove(item));
      case Error(:final errMsg):
        showToast(context, errMsg ?? '删除失败');
      case Loading():
        break;
    }
  }

  /// 打开历史项：仅 archive 类型且有 bvid 的稿件可跳转详情页续播，
  /// 直播/专栏/番剧等类型暂不支持。
  void _openItem(HistoryItem item) {
    final bvid = item.history.bvid;
    final business = item.history.business;
    final isArchive = business == 'archive' ||
        business == null ||
        business.isEmpty;
    if (bvid == null || bvid.isEmpty || !isArchive) {
      showToast(context, '暂不支持打开该类型记录');
      return;
    }
    Navigator.of(context).push(
      AppRoute<void>(
        builder: (_) => VideoDetailPage(
          bvid: bvid,
          cover: item.cover,
          heroTag: 'history_$bvid',
        ),
      ),
    );
  }

  Future<void> _clearAll() async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空历史'),
        content: const Text('确定清空所有观看历史？此操作不可撤销。'),
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

    final res = await HistoryHttp.clearHistory();
    if (!mounted) return;
    switch (res) {
      case Success():
        setState(() {
          _items.clear();
          _hasMore = false;
        });
      case Error(:final errMsg):
        showToast(context, errMsg ?? '清空失败');
      case Loading():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: '历史',
      actions: [
        if (_items.isNotEmpty)
          IconButton(
            icon: AppIcon(AppIcons.clearAll()),
            tooltip: '清空',
            onPressed: _clearAll,
          ),
      ],
      body: Pref.demoMode
          ? _buildDemoList()
          : _loading && _items.isEmpty
          ? _buildSkeleton()
          : _error != null && _items.isEmpty
              ? _buildError()
              : _items.isEmpty
                  ? AppEmptyState(
                      icon: Icon(AppIcons.history(selected: false)),
                      title: '暂无观看记录',
                      subtitle: '看过的视频会出现在这里',
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
                              padding: const EdgeInsets.all(Style.safeSpace),
                              sliver: SliverGrid.builder(
                                gridDelegate: Grid.videoCardHDelegate(
                                  maxCrossAxisExtent: 440.0,
                                  mainAxisExtent: 110.0,
                                ),
                                itemCount: _items.length,
                                itemBuilder: (context, index) {
                                  final item = _items[index];
                                  return _HistoryCard(
                                    item: item,
                                    onDelete: () => _deleteItem(item),
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
                                        color: AppThemeHost.of(context).colors.outline,
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

  /// 演示模式：本地列表（初始仅填充视口所需行数；滚动每次仅 +1 行）。
  Widget _buildDemoList() {
    final perRow = (MediaQuery.sizeOf(context).width / 460).floor().clamp(2, 8);
    final rowsFit =
        ((MediaQuery.sizeOf(context).height - 160) / 122).ceil().clamp(3, 12);
    return CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(Style.safeSpace),
          sliver: SliverGrid.builder(
            gridDelegate: Grid.videoCardHDelegate(
              maxCrossAxisExtent: 440.0,
              mainAxisExtent: 110.0,
            ),
            itemCount: rowsFit * perRow + _demoExtra,
            itemBuilder: (context, index) => DemoVideoCardH(
              seed: index,
              onTap: () => _openDemoVideo(context, index),
            ),
          ),
        ),
      ],
    );
  }

  /// 演示模式：打开本地演示视频详情（不拉取云端数据）。
  void _openDemoVideo(BuildContext context, int index) {
    Navigator.push(
      context,
      AppRoute(
        builder: (_) => VideoDetailPage(bvid: 'BV1demo$index'),
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
      return AppEmptyState(
        icon: AppIcon(AppIcons.profile()),
        title: '请先登录',
        subtitle: '登录后可查看历史记录',
      );
    }
    return AppErrorState(
      message: _error ?? '加载失败',
      onRetry: () => _load(refresh: true),
    );
  }
}

/// 历史记录多列横向卡片（对齐 PiliPlus 与 BiliPai 历史卡片规范）。
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.item,
    required this.onDelete,
    this.onTap,
  });

  final HistoryItem item;
  final VoidCallback onDelete;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final shapes = tokens.shapes;
    final radius = shapes.medium;
    final duration = item.duration ?? 0;
    final progress = item.progress ?? 0;
    final bvid = item.history.bvid;
    final authorName = item.authorName ?? '';
    final authorMid = item.authorMid ?? 0;

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
                          src: item.cover,
                          width: 140,
                          height: 140 * 9 / 16,
                          borderRadius: BorderRadius.all(radius),
                          heroTag: bvid != null && bvid.isNotEmpty ? 'history_$bvid' : null,
                        ),
                      ),
                      if (duration > 0 || Pref.demoMode)
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: PBadge(
                            text: DurationUtils.formatDuration(
                              Pref.demoMode
                                  ? DemoOverrides.durationSeconds(
                                      'demo.hist.${bvid ?? ''}',
                                    )
                                  : duration,
                            ),
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
                    Pref.demoMode
                        ? const SkeletonLine(width: double.infinity, height: 13)
                        : Text(
                            item.title ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: tokens.text.bodyMedium?.copyWith(
                              height: 1.35,
                            ),
                          ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (authorName.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              if (authorMid > 0) {
                                Navigator.push(
                                  context,
                                  AppRoute(
                                    builder: (_) => MemberSpacePage(mid: authorMid),
                                  ),
                                );
                              }
                            },
                            child: Row(
                              children: [
                                AppIcon(AppIcons.profile(), size: 12, color: cs.outline),
                                const SizedBox(width: 2),
                                Flexible(
                                  child: Text(
                                    Pref.demoMode ? kDemoDisplayName : authorName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: tokens.text.labelSmall
                                        ?.copyWith(color: cs.outline),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (!Pref.demoMode &&
                                item.viewAt != null &&
                                item.viewAt! > 0)
                              Text(
                                DateFormatUtils.dateFormat(item.viewAt),
                                style: tokens.text.labelSmall?.copyWith(
                                  color: cs.outline,
                                  fontSize: 11,
                                ),
                              ),
                            const Spacer(),
                            IconButton(
                              icon: AppIcon(AppIcons.clear(), size: 14),
                              tooltip: '删除此记录',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 24,
                                minHeight: 24,
                              ),
                              color: cs.outline,
                              onPressed: onDelete,
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
