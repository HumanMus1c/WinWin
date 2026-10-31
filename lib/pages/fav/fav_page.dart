import 'package:flutter/widgets.dart';

import 'package:winwin/common/widgets/app_scroll_bar.dart';
import 'package:winwin/common/widgets/refresh_indicator.dart';
import 'package:winwin/theme/app_colors.dart';
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
import 'package:winwin/core/log/api_blackbox.dart';
import 'package:winwin/core/log/app_logger.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/http/fav.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/models/fav/fav_models.dart';
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
import 'package:flutter_miuix/miuix.dart' show MiuixCard, MiuixCheckboxPreference, MiuixFloatingActionButton, MiuixPressFeedbackType, MiuixPressable, MiuixSmallTopAppBar, MiuixButton;
import 'package:winwin/core/shell/app_scaffold.dart';
import 'package:winwin/ui/components/app_progress.dart';
import 'package:winwin/ui/components/app_components.dart';

/// 收藏夹页面（移植自 PiliPlus `lib/pages/fav/`，重构为自适应宫格排版）。
void showFavPage(BuildContext context) {
  Navigator.of(context).push(
    AppRoute<void>(builder: (_) => const FavPage()),
  );
}

class FavPage extends StatefulWidget {
  const FavPage({super.key});

  @override
  State<FavPage> createState() => _FavPageState();
}

class _FavPageState extends State<FavPage> {
  final ScrollController _scrollController = ScrollController();
  final List<FavFolderInfo> _folders = [];
  int _page = 1;
  bool _hasMore = true;
  bool _loading = true;
  bool _isLoadingMore = false;
  String? _error;

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
    if (mounted) setState(() {});
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
        _folders.clear();
        _page = 1;
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
      _folders.clear();
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
      ApiBlackbox.log('FavPage', 'Load aborted: Accounts.main is not login (${Accounts.main.runtimeType})');
      AppLogger.w('FavPage', 'Accounts.main is not login: ${Accounts.main.runtimeType}');
      setState(() {
        _loading = false;
        _isLoadingMore = false;
        _error = '请先登录';
      });
      return;
    }

    ApiBlackbox.log('FavPage', 'Fetching userFavFolder pn=$_page, mid=${Accounts.main.mid}');
    AppLogger.d('FavPage', 'Loading page $_page for mid ${Accounts.main.mid}');
    // 视口预算：收藏夹封面卡约 112 行高，冷启动首批最多 2 屏、补批最多 1 屏。
    final ps = ViewportLoadBudget.capRequestItems(
      fallback: 20,
      visibleItems: ViewportLoadBudget.visibleGridItems(
        viewportExtent: ViewportLoadBudget.viewportExtentOf(
          _scrollController,
          reservedHeight: 160,
        ),
        viewportWidth: ViewportLoadBudget.windowLogicalWidth - 24,
        rowExtent: 112,
        maxCrossAxisExtent: 380,
      ),
      firstPage: refresh,
    );
    var res = await FavHttp.userFavFolder(
      pn: _page,
      ps: ps,
      mid: Accounts.main.mid,
    );
    if (!mounted) return;

    if (res case Success(:final response)) {
      if ((response.list == null || response.list!.isEmpty) && _page == 1) {
        ApiBlackbox.log('FavPage', 'userFavFolder list empty, falling back to allFavFolders');
        final allRes = await FavHttp.allFavFolders(Accounts.main.mid);
        if (!mounted) return;
        if (allRes case Success(response: final allResponse)) {
          if (allResponse.list != null && allResponse.list!.isNotEmpty) {
            res = allRes;
          }
        }
      }
    }

    switch (res) {
      case Success(:final response):
        ApiBlackbox.log('FavPage', 'Success: ${response.list?.length} folders, hasMore: ${response.hasMore}');
        AppLogger.d('FavPage', 'Loaded ${response.list?.length} folders, hasMore: ${response.hasMore}');
        setState(() {
          _loading = false;
          _isLoadingMore = false;
          _error = null;
          if (response.list != null) _folders.addAll(response.list!);
          _hasMore = response.hasMore == true;
          _page++;
        });
        _checkAutoLoad();
      case Error(:final errMsg):
        ApiBlackbox.log('FavPage', 'Error: $errMsg');
        AppLogger.e('FavPage', 'Load failed: $errMsg');
        setState(() {
          _loading = false;
          _isLoadingMore = false;
          if (_folders.isEmpty) {
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

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      body: Pref.demoMode
          ? const DemoListSkeleton()
          : _loading && _folders.isEmpty
          ? const Center(child: AppProgressIndicator(color: biliPink))
          : _error != null && _folders.isEmpty
              ? _buildError()
              : _folders.isEmpty
                  ? AppEmptyState(
                      icon: AppIcon(AppIcons.folderEmpty()),
                      title: '暂无收藏夹',
                      subtitle: '去创建或收藏喜欢的视频吧',
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
                              padding: const EdgeInsets.all(Style.safeSpace),
                              sliver: SliverGrid.builder(
                                gridDelegate: Grid.folderCardDelegate(),
                                itemCount: _folders.length,
                                itemBuilder: (context, index) {
                                  final folder = _folders[index];
                                  return _FavFolderCard(
                                    folder: folder,
                                    onTap: () => _openDetail(folder),
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
                            else if (!_hasMore && _folders.isNotEmpty)
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

  void _openDetail(FavFolderInfo folder) {
    Navigator.of(context).push(
      AppRoute<void>(
        builder: (_) => FavDetailPage(folder: folder),
      ),
    );
  }

  /// 错误/未登录态：未登录用语义空态，其余用统一错误态（含重试）。
  Widget _buildError() {
    if (_error == '请先登录') {
      return AppEmptyState(
        icon: AppIcon(AppIcons.profile()),
        title: '请先登录',
        subtitle: '登录后可查看我的收藏',
      );
    }
    return AppErrorState(
      message: _error ?? '加载失败',
      onRetry: () => _load(refresh: true),
    );
  }
}

/// 收藏夹文件夹卡片（宫格排版，对齐 PiliPlus FavVideoItem）。
class _FavFolderCard extends StatelessWidget {
  const _FavFolderCard({required this.folder, required this.onTap});

  final FavFolderInfo folder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final shapes = tokens.shapes;
    final radius = shapes.medium;
    final hasCover = folder.cover.isNotEmpty;

    return MiuixCard(
      child: MiuixPressable(
        feedbackType: MiuixPressFeedbackType.sink,
        sinkAmount: 0.98,
        onPressed: onTap,
        borderRadius: BorderRadius.all(radius),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面
              ClipRRect(
                borderRadius: BorderRadius.all(radius),
                child: SizedBox(
                  width: 120,
                  height: 120 * 9 / 16,
                  child: hasCover
                      ? NetworkImgLayer(
                          src: folder.cover,
                          width: 120,
                          height: 120 * 9 / 16,
                          borderRadius: BorderRadius.all(radius),
                        )
                      : Container(
                          color: cs.secondaryContainer.withValues(alpha: 0.4),
                          child: AppIcon(
                            folder.isPublic
                                ? AppIcons.folder()
                                : AppIcons.lock(),
                            size: 32,
                            color: biliPink,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              // 文本描述
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      folder.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          '${folder.mediaCount} 个内容',
                          style: tokens.text.labelSmall?.copyWith(
                            color: cs.outline,
                          ),
                        ),
                        const SizedBox(width: 6),
                        PBadge(
                          text: folder.isPublic ? '公开' : '私密',
                          type: PBadgeType.badge,
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

// ── 收藏夹详情（视频列表宫格） ──

class FavDetailPage extends StatefulWidget {
  const FavDetailPage({super.key, required this.folder});

  final FavFolderInfo folder;

  @override
  State<FavDetailPage> createState() => _FavDetailPageState();
}

class _FavDetailPageState extends State<FavDetailPage> {
  final ScrollController _scrollController = ScrollController();
  final List<FavDetailItem> _items = [];
  int _page = 1;
  bool _hasMore = true;
  bool _loading = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load(refresh: true);
    // 演示模式切换时重建（骨架即时生效）。
    Pref.demoModeNotifier.addListener(_onDemoChanged);
  }

  void _onDemoChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    Pref.demoModeNotifier.removeListener(_onDemoChanged);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
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
    if (refresh) {
      _page = 1;
      _hasMore = true;
      _items.clear();
      _loading = true;
      _isLoadingMore = false;
      setState(() {});
    } else {
      if (!_hasMore || _isLoadingMore) return;
      _isLoadingMore = true;
      setState(() {});
    }

    final res = await FavHttp.favDetail(
      mediaId: widget.folder.id,
      pn: _page,
    );
    if (!mounted) return;

    switch (res) {
      case Success(:final response):
        setState(() {
          _loading = false;
          _isLoadingMore = false;
          if (response.medias != null) _items.addAll(response.medias!);
          _hasMore = response.hasMore == true;
          _page++;
        });
        _checkAutoLoad();
      case Error():
        setState(() {
          _loading = false;
          _isLoadingMore = false;
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

  /// 打开收藏夹视频项：跳转视频详情页；
  /// 已失效资源（无 bvid）提示不可打开。
  void _openItem(FavDetailItem item) {
    final bvid = item.bvid;
    if (bvid == null || bvid.isEmpty) {
      showToast(context, '该资源已失效，无法打开');
      return;
    }
    Navigator.of(context).push(
      AppRoute<void>(
        builder: (_) => VideoDetailPage(
          bvid: bvid,
          cover: item.cover,
          heroTag: 'fav_$bvid',
        ),
      ),
    );
  }

  /// 播放全部视频（从第一个有效视频开始播放）。
  void _playAll() {
    final firstValid = _items.firstWhere(
      (item) => item.bvid != null && item.bvid!.isNotEmpty,
      orElse: () => FavDetailItem(),
    );
    if (firstValid.bvid != null && firstValid.bvid!.isNotEmpty) {
      _openItem(firstValid);
    } else {
      showToast(context, '该收藏夹暂无可用视频');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
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
          ? const DemoListSkeleton()
          : _loading && _items.isEmpty
          ? const Center(child: AppProgressIndicator(color: biliPink))
          : _items.isEmpty
              ? AppEmptyState(
                  icon: AppIcon(AppIcons.folderEmpty()),
                  title: '该收藏夹暂无视频',
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
                        // 头部概览信息区
                        SliverToBoxAdapter(
                          child: _buildHeaderInfo(),
                        ),
                        // 视频列表多列宫格
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(
                            Style.safeSpace,
                            0,
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
                              return _FavVideoCard(
                                item: item,
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

  /// 顶部文件夹概览信息卡片
  Widget _buildHeaderInfo() {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final folder = widget.folder;
    final upper = folder.upper;

    return Padding(
      padding: const EdgeInsets.all(Style.safeSpace),
      child: MiuixCard(
        child: Padding(
          padding: const EdgeInsets.all(Style.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (folder.cover.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(Style.radiusSm),
                  child: NetworkImgLayer(
                    src: folder.cover,
                    width: 110,
                    height: 70,
                  ),
                ),
              const SizedBox(width: Style.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      folder.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.text.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (upper?.name != null && upper!.name!.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          if (upper.mid != null && upper.mid! > 0) {
                            Navigator.push(
                              context,
                              AppRoute(
                                builder: (_) => MemberSpacePage(mid: upper.mid!),
                              ),
                            );
                          }
                        },
                        child: Text(
                          '创建者：${upper.name}',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.primary,
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      '共 ${folder.mediaCount} 条视频 · ${folder.isPublic ? "公开" : "私密"}',
                      style: tokens.text.labelSmall?.copyWith(
                        color: cs.outline,
                      ),
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

/// 收藏夹单个视频横向卡片（对齐 FavVideoCardH 与 BiliPai FavoritePersonalCard）。
class _FavVideoCard extends StatelessWidget {
  const _FavVideoCard({required this.item, this.onTap});

  final FavDetailItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final shapes = tokens.shapes;
    final radius = shapes.medium;
    final duration = item.duration ?? 0;
    final isInvalid = item.bvid == null || item.bvid!.isEmpty;
    final upper = item.upper;
    final cnt = item.cntInfo;
    final data = VideoCardData.from(item);

    return MiuixCard(
      child: GestureDetector(
        onSecondaryTapUp: (details) {
          showVideoContextMenu(
            context: context,
            position: details.globalPosition,
            data: data,
            videoItem: item,
          );
        },
        onLongPressStart: (details) {
          showVideoContextMenu(
            context: context,
            position: details.globalPosition,
            data: data,
            videoItem: item,
          );
        },
        child: MiuixPressable(
        feedbackType: MiuixPressFeedbackType.sink,
        sinkAmount: 0.98,
        onPressed: onTap,
        borderRadius: BorderRadius.all(radius),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面
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
                          heroTag: item.bvid != null ? 'fav_${item.bvid}' : null,
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
                      if (cnt?.play != null || cnt?.danmaku != null)
                        Positioned(
                          left: 4,
                          bottom: 4,
                          child: VideoCoverStatBadge(
                            playCount: cnt?.play,
                            danmakuCount: cnt?.danmaku,
                          ),
                        ),
                      if (isInvalid)
                        Positioned(
                          left: 4,
                          top: 4,
                          child: PBadge(
                            text: '已失效',
                            type: PBadgeType.badge,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // 右侧描述（统一信息列：标题 → UP/发布时间 → 动作）
              Expanded(
                child: VideoCardInfoColumn(
                  title: item.title ?? '',
                  ownerName: upper?.name ?? '',
                  titleColor: isInvalid ? cs.outline : null,
                  timeText: VideoCardInfoText.publishedAt(item.pubtime),
                  onOwnerTap: (upper?.mid != null && upper!.mid! > 0)
                      ? () {
                          Navigator.push(
                            context,
                            AppRoute(
                              builder: (_) =>
                                  MemberSpacePage(mid: upper.mid!),
                            ),
                          );
                        }
                      : null,
                  trailing: VideoPopupMenu(
                    data: data,
                    videoItem: item,
                  ),
                ),
              ),
            ],
          ),
        ),
      
        )
      ),
    );
  }
}

// ── 收藏面板（从视频详情页弹出，选择收藏夹） ──

/// 弹出收藏面板。
///
/// [rid] 为视频 aid，[type] 为资源类型（UGC 视频=2）。
/// 成功后回调 [onSuccess]（true=已收藏，false=取消收藏）。
void showFavPanel(
  BuildContext context, {
  required int rid,
  int type = 2,
  ValueChanged<bool>? onSuccess,
}) {
  if (!Accounts.main.isLogin) {
    showToast(context, '请先登录');
    return;
  }
  showAppSheet<void>(
    context: context,
    isScrollControlled: true,
    // 面板底色取 Miuix 行容器色（surfaceContainer），与 MiuixCheckboxPreference
    // 的行底色一致，避免行与面板出现两种灰。
    backgroundColor: AppThemeHost.of(context).colors.surfaceContainer,
    builder: (_) => _FavPanel(rid: rid, type: type, onSuccess: onSuccess),
  );
}

class _FavPanel extends StatefulWidget {
  const _FavPanel({required this.rid, required this.type, this.onSuccess});

  final int rid;
  final int type;
  final ValueChanged<bool>? onSuccess;

  @override
  State<_FavPanel> createState() => _FavPanelState();
}

class _FavPanelState extends State<_FavPanel> {
  List<FavFolderInfo>? _folders;
  Set<int>? _initialFavIds;
  bool _loading = true;
  bool _sending = false;

  /// 收藏夹名搜索关键字（仅用于列表即时过滤，**不参与**提交差集计算）。
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  /// 收藏夹列表控制器（供自挂的项目自绘滚动条 [AppScrollBar] 使用）。
  final ScrollController _listController = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await FavHttp.videoInFolder(
      mid: Accounts.main.mid,
      rid: widget.rid,
      type: widget.type,
    );
    if (!mounted) return;
    switch (res) {
      case Success(:final response):
        setState(() {
          _folders = response.list ?? [];
          _initialFavIds = _folders
              ?.where((f) => f.favState == 1)
              .map((f) => f.id)
              .toSet();
          _loading = false;
        });
      case Error():
        setState(() => _loading = false);
      case Loading():
        break;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _listController.dispose();
    super.dispose();
  }

  /// 按关键字过滤后的收藏夹视图（仅用于列表展示）。
  ///
  /// **提交仍遍历全量 [_folders]**，避免被搜索隐藏的收藏夹其勾选态被误删/漏加。
  List<FavFolderInfo> get _filteredFolders {
    final folders = _folders ?? const <FavFolderInfo>[];
    final q = _query.toLowerCase();
    if (q.isEmpty) return folders;
    return folders
        .where((f) => f.title.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _submit() async {
    if (_folders == null || _initialFavIds == null) return;
    setState(() => _sending = true);

    final addIds = <int>[];
    final delIds = <int>[];
    for (final f in _folders!) {
      final wasFav = _initialFavIds!.contains(f.id);
      final nowFav = f.favState == 1;
      if (nowFav && !wasFav) addIds.add(f.id);
      if (!nowFav && wasFav) delIds.add(f.id);
    }

    final res = await FavHttp.favVideo(
      resources: '${widget.rid}:${widget.type}',
      addIds: addIds.join(','),
      delIds: delIds.join(','),
    );
    if (!mounted) return;

    setState(() => _sending = false);
    switch (res) {
      case Success():
        final isFav = addIds.isNotEmpty ||
            (_initialFavIds!.isNotEmpty && delIds.length != _initialFavIds!.length);
        widget.onSuccess?.call(isFav);
        Navigator.of(context).pop();
      case Error(:final errMsg):
        showToast(context, errMsg ?? '操作失败');
      case Loading():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    return Container(
      constraints: const BoxConstraints(maxHeight: 500),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 关闭 X 已移除：遵循「Esc 生效后移除自绘关闭 X」约定，关闭仍可经
          // 「取消」按钮 / 点击遮罩 / Esc 单层返回（AppSheetRoute 为 PopupRoute）。
          MiuixSmallTopAppBar(
            title: '添加到收藏夹',
          ),
          // 搜索框（新增）：按收藏夹名称即时过滤账户自建收藏夹。
          if (!_loading && (_folders?.isNotEmpty ?? false))
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Style.md,
                Style.sm,
                Style.md,
                Style.xs,
              ),
              child: AppCapsuleTextField(
                controller: _searchController,
                hint: '搜索收藏夹',
                prefix: AppIcon(AppIcons.search(), size: 20),
                fillColor: tokens.colors.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
            ),
          if (_loading)
            const Expanded(child: Center(child: AppProgressIndicator(color: biliPink)))
          else if (_folders == null || _folders!.isEmpty)
            const Expanded(child: Center(child: Text('暂无收藏夹')))
          else if (_filteredFolders.isEmpty)
            const Expanded(child: Center(child: Text('未找到收藏夹')))
          else
            Expanded(
              // 面板内列表自挂项目自绘滚动条（forceLane 跳过「页面级」比例门控：
              // 本列表主轴向尺寸远小于窗口高，不强制会被全局挂载逻辑抑制）。
              child: AppScrollBar(
                controller: _listController,
                forceLane: true,
                child: ListView.builder(
                  controller: _listController,
                  itemCount: _filteredFolders.length,
                  itemBuilder: (context, index) {
                    final f = _filteredFolders[index];
                    // B6：Material CheckboxListTile → Miuix 偏好组件。
                    // 不传 startAction：Miuix 会把 startAction 放进灰底圆形容器，
                    // 与面板观感冲突（且项目图标在该容器内渲染异常）。
                    return MiuixCheckboxPreference(
                      value: f.favState == 1,
                      title: f.title,
                      summary: '${f.mediaCount} 个内容',
                      onChanged: _sending
                          ? null
                          : (v) => setState(() {
                                f.favState = v == true ? 1 : 0;
                              }),
                    );
                  },
                ),
              ),
            ),
          // B6：Material Divider → 0.5px 细分隔线（Miuix 口径）。
          Container(
            height: 0.5,
            color: tokens.colors.outlineVariant.withValues(alpha: 0.3),
          ),
          Padding(
            padding: const EdgeInsets.all(Style.md),
            child: Row(
              children: [
                Expanded(
                  child: MiuixButton(onPressed: _sending ? null : () => Navigator.of(context).pop(), child: const Text('取消')),
                ),
                const SizedBox(width: Style.md),
                Expanded(
                  child: AppPrimaryButton(onPressed: _sending ? null : _submit, child: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: AppProgressIndicator(strokeWidth: 2, color: AppColors.white),
                          )
                        : const Text('完成')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
