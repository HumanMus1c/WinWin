import 'dart:async';

import 'package:flutter_miuix/miuix.dart' show MiuixCard, MiuixFloatingActionButton, MiuixIconButton, MiuixPressFeedbackType, MiuixPressable, MiuixTextButton;
import 'package:flutter/widgets.dart';

import 'package:winwin/common/widgets/refresh_indicator.dart';
import 'package:winwin/theme/app_colors.dart';
import 'package:winwin/common/skeleton/video_card_h.dart';
import 'package:winwin/common/widgets/demo_mask.dart';
import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/common/widgets/p_badge.dart';
import 'package:winwin/common/widgets/video_card/video_card_adapter.dart';
import 'package:winwin/common/widgets/video_card/video_card_info.dart';
import 'package:winwin/common/widgets/video_card/video_context_menu.dart';
import 'package:winwin/common/widgets/video_card/video_cover_stat_badge.dart';
import 'package:winwin/core/account/account_service.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/core/demo/demo_overrides.dart';
import 'package:winwin/core/event/event_bus.dart';
import 'package:winwin/core/log/api_blackbox.dart';
import 'package:winwin/core/log/app_logger.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/toview.dart';
import 'package:winwin/models/toview/toview_models.dart';
import 'package:winwin/pages/member/member_space_page.dart';
import 'package:winwin/pages/video/detail_page.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/app_empty_state.dart';
import 'package:winwin/utils/duration_utils.dart';
import 'package:winwin/utils/grid.dart';
import 'package:winwin/utils/viewport_load_budget.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/core/shell/app_routes.dart';
import 'package:winwin/core/shell/app_dialogs.dart';
import 'package:winwin/core/shell/app_scaffold.dart';
import 'package:winwin/ui/components/app_progress.dart';
import 'package:winwin/ui/components/app_tooltip.dart';
import 'package:winwin/ui/components/app_components.dart';
import 'package:winwin/common/widgets/app_dialog_shell.dart';

/// 稍后再看页面（移植自 PiliPlus `lib/pages/later/`，重构为自适应多列宫格排版）。
void showToviewPage(BuildContext context) {
  Navigator.of(context).push(
    AppRoute<void>(builder: (_) => const ToviewPage()),
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

  /// 演示模式：本地追加的演示卡片数量（滚动每次仅 +1 行）。
  int _demoExtra = 0;

  /// 演示模式：上次追加行的滚动位置（需继续滚动约半屏后才再追加）。
  double _demoLastAppendAt = double.negativeInfinity;

  @override
  void initState() {
    super.initState();
    AccountService().addListener(_onAccountChanged);
    _scrollController.addListener(_onScroll);
    _initWatchLaterSubscription();
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
    // 演示模式：不拉取云端列表（滚动追加在 _onScroll 中本地处理）。
    if (Pref.demoMode) {
      _loading = false;
      return;
    }
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
    // 视口预算：稍后再看为 VideoCardH 宫格，冷启动首批最多 2 屏、补批最多 1 屏。
    final ps = ViewportLoadBudget.capRequestItems(
      fallback: 20,
      visibleItems: ViewportLoadBudget.visibleGridItems(
        viewportExtent: ViewportLoadBudget.viewportExtentOf(
          _scrollController,
          reservedHeight: 160,
        ),
        viewportWidth: ViewportLoadBudget.windowLogicalWidth - 24,
        rowExtent: 118,
        maxCrossAxisExtent: 440,
      ),
      firstPage: refresh,
    );
    final res = await ToviewHttp.toviewList(page: _page, ps: ps);
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
      AppRoute<void>(
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
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: const Text('清空稍后再看'),
        content: const Text('确定清空所有稍后再看？此操作不可撤销。'),
        actions: [
          MiuixTextButton('取消', onPressed: () => Navigator.pop(ctx, false)),
          AppPrimaryButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清空')),
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
    return AppScaffold(
      actions: [
        if (_items.isNotEmpty)
          MiuixIconButton(

            onPressed: _clearAll,

            child: AppTooltip(message: '清空', child: AppIcon(AppIcons.clearAll())),
          ),
      ],
      floatingActionButton: _items.isNotEmpty
          ? MiuixFloatingActionButton(
              onPressed: _playAll,
              containerColor: biliPink,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Style.md),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(AppIcons.playAll(), color: AppColors.white),
                    const SizedBox(width: Style.sm),
                    Text(
                      '播放全部',
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: Pref.demoMode
          ? _buildDemoList()
          : _loading && _items.isEmpty
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
                      child: AppRefreshIndicator(
                        displacement: 40.0,
                        strokeWidth: 2.5,
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
                                    child: AppProgressIndicator(
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
    return AppRefreshIndicator(
      displacement: 40.0,
      strokeWidth: 2.5,
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
                showProgressSlot: true,
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
        subtitle: '登录后可查看稍后再看',
      );
    }
    return AppErrorState(
      message: _error ?? '加载失败',
      onRetry: () => _load(refresh: true),
    );
  }
}

/// 稍后再看多列横向卡片（统一历史 / 收藏夹详情的信息布局规范）。
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
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final shapes = tokens.shapes;
    final radius = shapes.medium;
    final duration = item.duration ?? 0;
    final progress = item.progress ?? 0;
    final bvid = item.bvid;
    final owner = item.owner;
    final ownerMid = owner?.mid;

    double progressFraction = 0.0;
    if (progress > 0 && duration > 0) {
      progressFraction = (progress / duration).clamp(0.0, 1.0);
    } else if (progress == -1) {
      progressFraction = 1.0;
    }

    final data = VideoCardData.from(item);

    return MiuixCard(
      child: GestureDetector(
        onSecondaryTapUp: (details) {
          showVideoContextMenu(
            context: context,
            position: details.globalPosition,
            data: data,
            videoItem: item,
            onRemove: onRemove,
          );
        },
        onLongPressStart: (details) {
          showVideoContextMenu(
            context: context,
            position: details.globalPosition,
            data: data,
            videoItem: item,
            onRemove: onRemove,
          );
        },
        child: MiuixPressable(
          feedbackType: MiuixPressFeedbackType.sink,
          sinkAmount: 0.98,
          onPressed: onTap,
          borderRadius: BorderRadius.all(radius),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 封面：时长 / 统计角标；进度条统一放卡片下缘
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
                                heroTag: bvid != null && bvid.isNotEmpty
                                    ? 'toview_$bvid'
                                    : null,
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
                                            'demo.tv.${bvid ?? ''}',
                                          )
                                        : duration,
                                  ),
                                  type: PBadgeType.duration,
                                ),
                              ),
                            if (Pref.demoMode ||
                                data.playCount != null ||
                                data.danmakuCount != null)
                              Positioned(
                                left: 4,
                                bottom: 4,
                                child: VideoCoverStatBadge(
                                  playCount: Pref.demoMode
                                      ? DemoOverrides.count(
                                          'demo.tvplay.${bvid ?? ''}',
                                          min: 1000,
                                          max: 9999999,
                                        )
                                      : data.playCount,
                                  danmakuCount: Pref.demoMode
                                      ? DemoOverrides.count(
                                          'demo.tvdm.${bvid ?? ''}',
                                          min: 10,
                                          max: 99999,
                                        )
                                      : data.danmakuCount,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // 右侧描述（统一信息列：标题 → UP/发布时间 → 进度/动作）
                    Expanded(
                      child: VideoCardInfoColumn(
                        title: item.title ?? '',
                        ownerName: owner?.name ?? '',
                        demo: Pref.demoMode,
                        timeText: Pref.demoMode
                            ? ''
                            : VideoCardInfoText.publishedAt(item.pubdate),
                        progressText: Pref.demoMode
                            ? ''
                            : VideoCardInfoText.progress(
                                item.progress,
                                item.duration,
                              ),
                        onOwnerTap: ownerMid != null && ownerMid > 0
                            ? () {
                                Navigator.push(
                                  context,
                                  AppRoute(
                                    builder: (_) =>
                                        MemberSpacePage(mid: ownerMid),
                                  ),
                                );
                              }
                            : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            VideoPopupMenu(
                              data: data,
                              videoItem: item,
                              onRemove: onRemove,
                            ),
                            const SizedBox(width: 4),
                            MiuixIconButton(
                              minWidth: 24,
                              minHeight: 24,
                              onPressed: onRemove,
                              child: AppTooltip(
                                message: '从稍后再看移除',
                                child: AppIcon(
                                  AppIcons.clear(),
                                  size: 14,
                                  color: cs.outline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 播放进度条：统一置于卡片下缘（与历史记录一致）。
              if (progressFraction > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2.5),
                    child: AppLinearProgressIndicator(
                      value: progressFraction,
                      minHeight: 4,
                      backgroundColor: cs.primary.withValues(alpha: 0.16),
                      color: cs.primary,
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
