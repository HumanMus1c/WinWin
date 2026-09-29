import 'package:flutter/material.dart';

import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/common/widgets/p_badge.dart';
import 'package:winwin/common/widgets/video_card/video_card_adapter.dart';
import 'package:winwin/common/widgets/video_card/video_context_menu.dart';
import 'package:winwin/core/account/account_service.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/core/log/api_blackbox.dart';
import 'package:winwin/core/log/app_logger.dart';
import 'package:winwin/http/fav.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/models/fav/fav_models.dart';
import 'package:winwin/pages/member/member_space_page.dart';
import 'package:winwin/pages/video/detail_page.dart';
import 'package:winwin/theme/app_shapes.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/app_empty_state.dart';
import 'package:winwin/utils/duration_utils.dart';
import 'package:winwin/utils/grid.dart';
import 'package:winwin/utils/num_utils.dart';

/// 收藏夹页面（移植自 PiliPlus `lib/pages/fav/`，重构为自适应宫格排版）。
void showFavPage(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const FavPage()),
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
    var res = await FavHttp.userFavFolder(
      pn: _page,
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
    return Scaffold(
      appBar: AppBar(title: const Text('我的收藏')),
      body: _loading && _folders.isEmpty
          ? const Center(child: CircularProgressIndicator(color: biliPink))
          : _error != null && _folders.isEmpty
              ? _buildError()
              : _folders.isEmpty
                  ? const AppEmptyState(
                      icon: Icons.folder_off_outlined,
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
                                    child: CircularProgressIndicator(
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

  void _openDetail(FavFolderInfo folder) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FavDetailPage(folder: folder),
      ),
    );
  }

  /// 错误/未登录态：未登录用语义空态，其余用统一错误态（含重试）。
  Widget _buildError() {
    if (_error == '请先登录') {
      return const AppEmptyState(
        icon: Icons.account_circle_outlined,
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final shapes = theme.extension<AppShapes>() ?? AppShapes.material3;
    final radius = shapes.medium;
    final hasCover = folder.cover.isNotEmpty;

    return Card(
      child: InkWell(
        onTap: onTap,
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
                          child: Icon(
                            folder.isPublic
                                ? Icons.folder_outlined
                                : Icons.lock_outline,
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
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          '${folder.mediaCount} 个内容',
                          style: theme.textTheme.labelSmall?.copyWith(
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
      MaterialPageRoute<void>(
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
    return Scaffold(
      appBar: AppBar(title: Text(widget.folder.title)),
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
          ? const Center(child: CircularProgressIndicator(color: biliPink))
          : _items.isEmpty
              ? const AppEmptyState(
                  icon: Icons.folder_off_outlined,
                  title: '该收藏夹暂无视频',
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

  /// 顶部文件夹概览信息卡片
  Widget _buildHeaderInfo() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final folder = widget.folder;
    final upper = folder.upper;

    return Padding(
      padding: const EdgeInsets.all(Style.safeSpace),
      child: Card(
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
                      style: theme.textTheme.titleMedium?.copyWith(
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
                              MaterialPageRoute(
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
                      style: theme.textTheme.labelSmall?.copyWith(
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final shapes = theme.extension<AppShapes>() ?? AppShapes.material3;
    final radius = shapes.medium;
    final duration = item.duration ?? 0;
    final isInvalid = item.bvid == null || item.bvid!.isEmpty;
    final upper = item.upper;
    final cnt = item.cntInfo;
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
          );
        },
        onLongPress: () {
          if (lastTapPosition != null) {
            showVideoContextMenu(
              context: context,
              position: lastTapPosition!,
              data: data,
              videoItem: item,
            );
          }
        },
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
                        color: isInvalid ? cs.outline : null,
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (upper?.name != null && upper!.name!.isNotEmpty)
                          Row(
                            children: [
                              Icon(Icons.person_outline, size: 12, color: cs.outline),
                              const SizedBox(width: 2),
                              Flexible(
                                child: Text(
                                  upper.name!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: cs.outline,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (cnt?.play != null) ...[
                              Icon(
                                Icons.play_circle_outlined,
                                size: 12,
                                color: cs.outline,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                NumUtils.formatNum(cnt!.play),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.outline,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            if (cnt?.danmaku != null) ...[
                              Icon(
                                Icons.subtitles_outlined,
                                size: 12,
                                color: cs.outline,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                NumUtils.formatNum(cnt!.danmaku),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.outline,
                                ),
                              ),
                            ],
                            const Spacer(),
                            VideoPopupMenu(
                              data: data,
                              videoItem: item,
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
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
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
    return Container(
      constraints: const BoxConstraints(maxHeight: 500),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppBar(
            title: const Text('添加到收藏夹'),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator(color: biliPink)))
          else if (_folders == null || _folders!.isEmpty)
            const Expanded(child: Center(child: Text('暂无收藏夹')))
          else
            Expanded(
              child: ListView.builder(
                itemCount: _folders!.length,
                itemBuilder: (context, index) {
                  final f = _folders![index];
                  return CheckboxListTile(
                    value: f.favState == 1,
                    onChanged: _sending
                        ? null
                        : (v) => setState(() {
                              f.favState = v == true ? 1 : 0;
                            }),
                    title: Text(f.title),
                    subtitle: Text('${f.mediaCount} 个内容'),
                    secondary: Icon(
                      f.isPublic ? Icons.folder_outlined : Icons.lock_outline,
                      color: biliPink,
                    ),
                  );
                },
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(Style.md),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _sending ? null : () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: Style.md),
                Expanded(
                  child: FilledButton(
                    onPressed: _sending ? null : _submit,
                    style: FilledButton.styleFrom(backgroundColor: biliPink),
                    child: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('完成'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
