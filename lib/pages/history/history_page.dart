import 'package:flutter_miuix/miuix.dart'
    show MiuixCard, MiuixIconButton, MiuixPressFeedbackType, MiuixPressable, MiuixTextButton;
import 'package:flutter/widgets.dart';

import 'package:winwin/common/widgets/refresh_indicator.dart';
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
import 'package:winwin/pages/article/article_page.dart';
import 'package:winwin/pages/bangumi/bangumi_detail_page.dart';
import 'package:winwin/pages/live/live_room_page.dart';
import 'package:winwin/pages/member/member_space_page.dart';
import 'package:winwin/pages/video/detail_page.dart';
import 'package:winwin/theme/app_colors.dart';
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
import 'package:winwin/core/shell/app_transparent_host.dart';
import 'package:winwin/ui/components/app_progress.dart';
import 'package:winwin/ui/components/app_tooltip.dart';
import 'package:winwin/ui/components/app_components.dart';
import 'package:winwin/common/widgets/app_dialog_shell.dart';

/// 历史记录页面（移植自 PiliPlus `lib/pages/history/`，重构为自适应多列宫格排版）。
///
/// 多类型支持（对标官方 `/x/web-interface/history/cursor` 与上游 PiliPlus）：
/// - 分类栏由服务端 `data.tab` 动态下发（官方 `type` 全集 `all/archive/live/article`）；
/// - 切换分类按 `type` 重新分页，各分类独立缓存（切回不重拉）；
/// - 点击按 `history.business` 跳转对应落地页：稿件→视频、番剧/影视(pgc)→番剧详情、
///   直播(live)→直播间、专栏/文集(article/article-list)→文章页。
void showHistoryPage(BuildContext context) {
  Navigator.of(
    context,
  ).push(AppRoute<void>(builder: (_) => const HistoryPage()));
}

/// 单个分类（type）的分页状态（对齐上游「每 type 一个 Controller 保活」）。
class _HistoryTabState {
  final List<HistoryItem> items = [];
  int? max;
  int? viewAt;
  bool hasMore = true;
  bool loading = true;
  bool isLoadingMore = false;
  String? error;

  /// 是否已完成过一次**成功**加载（切回该分类时据此判断是否需重新请求）。
  bool loaded = false;
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final ScrollController _scrollController = ScrollController();

  /// 当前分类（官方 `type`：all/archive/live/article）。
  String _type = 'all';

  /// 各分类独立状态缓存。
  final Map<String, _HistoryTabState> _tabStates = {};

  /// 服务端下发的分类列表（仅在 `all` 首次刷新时捕获）。
  List<HistoryTab> _tabs = const [];

  /// 演示模式：本地追加的演示卡片数量（滚动每次仅 +1 行）。
  int _demoExtra = 0;

  /// 演示模式：上次追加行的滚动位置（需继续滚动约半屏后才再追加）。
  double _demoLastAppendAt = double.negativeInfinity;

  _HistoryTabState get _state =>
      _tabStates.putIfAbsent(_type, _HistoryTabState.new);

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
    if (!Pref.demoMode && _state.items.isEmpty) {
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
        _tabStates.clear();
        _tabs = const [];
        _type = 'all';
        final s = _state;
        s.loading = false;
        s.error = '请先登录';
      });
    }
  }

  /// 切换分类：命中缓存则直接展示，否则首次拉取。
  void _switchType(String type) {
    if (_type == type) return;
    setState(() => _type = type);
    final s = _state;
    if (!s.loaded) {
      _load(refresh: true);
    } else {
      _checkAutoLoad();
    }
  }

  void _checkAutoLoad() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = _state;
      if (!s.hasMore || s.loading || s.isLoadingMore) return;
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
    final s = _state;
    // 演示模式：不拉取云端列表（滚动追加在 _onScroll 中本地处理）。
    if (Pref.demoMode) {
      s.loading = false;
      return;
    }
    await ensureBootstrap();
    if (refresh) {
      s.max = null;
      s.viewAt = null;
      s.hasMore = true;
      s.items.clear();
      s.loading = true;
      s.isLoadingMore = false;
      s.error = null;
      setState(() {});
    } else {
      if (!s.hasMore || s.isLoadingMore) return;
      s.isLoadingMore = true;
      setState(() {});
    }

    if (!Accounts.main.isLogin) {
      AppLogger.w(
        'HistoryPage',
        'Accounts.main is not login: ${Accounts.main.runtimeType}',
      );
      setState(() {
        s.loading = false;
        s.isLoadingMore = false;
        s.error = '请先登录';
      });
      return;
    }

    AppLogger.d(
      'HistoryPage',
      'Loading history type: $_type max: ${s.max}, viewAt: ${s.viewAt}',
    );
    final res = await HistoryHttp.historyList(
      type: _type,
      max: s.max,
      viewAt: s.viewAt,
    );
    if (!mounted) return;

    switch (res) {
      case Success(:final response):
        AppLogger.d('HistoryPage', 'Loaded ${response.list?.length} items');
        setState(() {
          s.loading = false;
          s.isLoadingMore = false;
          s.error = null;
          s.loaded = true;
          if (response.list != null) s.items.addAll(response.list!);
          // 分类栏仅由 `all` 首次刷新时捕获（官方仅在默认分类下发 tab）。
          if (refresh &&
              _type == 'all' &&
              response.tab != null &&
              response.tab!.isNotEmpty) {
            _tabs = response.tab!;
          }
          // 游标分页：优先使用服务端下发的 cursor，回退到末尾项推算
          if (response.cursor != null &&
              response.cursor!.max != null &&
              response.cursor!.max! > 0) {
            s.max = response.cursor!.max;
            s.viewAt = response.cursor!.viewAt;
            s.hasMore = (response.list?.length ?? 0) >= 20 && s.max != 0;
          } else if (response.list != null && response.list!.isNotEmpty) {
            final last = response.list!.last;
            s.max = last.history.oid;
            s.viewAt = last.viewAt;
            s.hasMore = response.list!.length >= 20;
          } else {
            s.hasMore = false;
          }
        });
        _checkAutoLoad();
      case Error(:final errMsg):
        AppLogger.e('HistoryPage', 'Load failed: $errMsg');
        setState(() {
          s.loading = false;
          s.isLoadingMore = false;
          if (s.items.isEmpty) {
            s.error = errMsg ?? '加载失败';
          }
        });
      case Loading():
        break;
    }
  }

  void _onScroll() {
    final s = _state;
    if (!s.hasMore || s.loading || s.isLoadingMore) return;
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
        setState(() => _state.items.remove(item));
      case Error(:final errMsg):
        showToast(context, errMsg ?? '删除失败');
      case Loading():
        break;
    }
  }

  /// 打开历史项：按 `history.business` 分发到对应落地页。
  ///
  /// - `archive`/空 → 普通视频详情（可续播）；
  /// - `pgc` → 番剧/影视详情（按 epid）；
  /// - `live` → 直播间（未开播则提示）；
  /// - `article`/`article-list` → 专栏/文集文章页；
  /// - `cheese`（课程）→ 暂不支持（WinWin 尚无课程落地页）。
  void _openItem(HistoryItem item) {
    final business = item.history.business ?? 'archive';

    // 专栏 / 文集
    if (business.contains('article')) {
      final id =
          business == 'article-list' ? item.history.cid : item.history.oid;
      if (id == null) {
        showToast(context, '暂不支持打开该类型记录');
        return;
      }
      Navigator.of(context).push(
        AppRoute<void>(
          builder: (_) => ArticlePage(
            id: id.toString(),
            title: item.title,
            cover: item.cover,
          ),
        ),
      );
      return;
    }

    // 直播
    if (business == 'live') {
      if (item.liveStatus != 1) {
        showToast(context, '直播未开播');
        return;
      }
      final roomId = item.history.oid;
      if (roomId == null) {
        showToast(context, '暂不支持打开该类型记录');
        return;
      }
      Navigator.of(context).push(
        AppRoute<void>(
          builder: (_) => LiveRoomPage(
            roomId: roomId,
            title: item.title,
            cover: item.cover,
          ),
        ),
      );
      return;
    }

    // 番剧 / 影视（pgc）
    if (business == 'pgc') {
      final epId = item.history.epid;
      if (epId == null) {
        showToast(context, '暂不支持打开该类型记录');
        return;
      }
      Navigator.of(context).push(
        AppRoute<void>(
          builder: (_) => BangumiDetailPage(
            epId: epId,
            cover: item.cover,
            title: item.title,
          ),
        ),
      );
      return;
    }

    // 稿件（archive / 空）
    final bvid = item.history.bvid;
    final isArchive = business == 'archive' || business.isEmpty;
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
      builder: (ctx) => AppAlertDialog(
        title: const Text('清空历史'),
        content: const Text('确定清空所有观看历史？此操作不可撤销。'),
        actions: [
          MiuixTextButton('取消', onPressed: () => Navigator.pop(ctx, false)),
          AppPrimaryButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清空')),
        ],
      ),
    );
    if (confirmed != true) return;

    final res = await HistoryHttp.clearHistory();
    if (!mounted) return;
    switch (res) {
      case Success():
        setState(() {
          // 服务端清空所有类型，同步清空全部分类缓存。
          for (final st in _tabStates.values) {
            st.items.clear();
            st.hasMore = false;
          }
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
        if (!Pref.demoMode && _state.items.isNotEmpty)
          MiuixIconButton(
            onPressed: _clearAll,

            child: AppTooltip(
              message: '清空',
              child: AppIcon(AppIcons.clearAll()),
            ),
          ),
      ],
      body: Pref.demoMode ? _buildDemoList() : _buildContent(context),
    );
  }

  /// 正文：分类栏 + 内容区（分类未下发或演示模式下退化为纯内容）。
  Widget _buildContent(BuildContext context) {
    final content = _state.loading && _state.items.isEmpty
        ? _buildSkeleton()
        : _state.error != null && _state.items.isEmpty
        ? _buildError()
        : _state.items.isEmpty
        ? AppEmptyState(
            icon: AppIcon(AppIcons.history(selected: false)),
            title: '暂无观看记录',
            subtitle: '看过的视频会出现在这里',
          )
        : _buildList();

    if (_tabs.isEmpty) return content;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTabBar(context),
        Expanded(child: content),
      ],
    );
  }

  /// 分类胶囊栏：`全部` + 服务端下发分类（对齐上游 PiliPlus，样式复用直播/番剧页）。
  Widget _buildTabBar(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final shapes = tokens.shapes;
    final entries = <({String type, String label})>[
      (type: 'all', label: '全部'),
      for (final t in _tabs)
        if (t.type != null && t.type!.isNotEmpty && t.name != null)
          (type: t.type!, label: t.name!),
    ];

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: Style.safeSpace,
          vertical: Style.xs,
        ),
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(width: Style.sm),
        itemBuilder: (context, index) {
          final entry = entries[index];
          final isSelected = _type == entry.type;
          return AppTransparentHost(
            child: MiuixPressable(
              feedbackType: MiuixPressFeedbackType.sink,
              sinkAmount: 0.98,
              borderRadius: shapes.pillBorder,
              onPressed: () => _switchType(entry.type),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? cs.primary.withValues(alpha: 0.18)
                      : cs.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: shapes.pillBorder,
                  border: Border.all(
                    color: isSelected
                        ? cs.primary.withValues(alpha: 0.45)
                        : AppColors.transparent,
                    width: 1,
                  ),
                ),
                child: Center(
                  child: Text(
                    entry.label,
                    style: TextStyle(
                      color: isSelected ? cs.primary : cs.onSurfaceVariant,
                      fontSize: 12.5,
                      // 显式行高收紧行盒：消除字体度量导致的下坠，Center 后光学居中。
                      height: 1.2,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 内容列表（当前分类）。
  Widget _buildList() {
    final s = _state;
    return NotificationListener<ScrollNotification>(
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
                gridDelegate: Grid.videoCardHDelegate(
                  maxCrossAxisExtent: 440.0,
                  mainAxisExtent: 110.0,
                ),
                itemCount: s.items.length,
                itemBuilder: (context, index) {
                  final item = s.items[index];
                  return _HistoryCard(
                    item: item,
                    onDelete: () => _deleteItem(item),
                    onTap: () => _openItem(item),
                  );
                },
              ),
            ),
            if (s.isLoadingMore)
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
            else if (!s.hasMore && s.items.isNotEmpty)
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
    );
  }

  /// 演示模式：本地列表（初始仅填充视口所需行数；滚动每次仅 +1 行）。
  Widget _buildDemoList() {
    final perRow = (MediaQuery.sizeOf(context).width / 460).floor().clamp(2, 8);
    final rowsFit = ((MediaQuery.sizeOf(context).height - 160) / 122)
        .ceil()
        .clamp(3, 12);
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
      AppRoute(builder: (_) => VideoDetailPage(bvid: 'BV1demo$index')),
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
              itemBuilder: (context, index) =>
                  const VideoCardHSkeleton(coverWidth: 140, inCard: true),
            ),
          ),
        ],
      ),
    );
  }

  /// 错误/未登录态：未登录用语义空态，其余用统一错误态（含重试）。
  Widget _buildError() {
    final err = _state.error;
    if (err == '请先登录') {
      return AppEmptyState(
        icon: AppIcon(AppIcons.profile()),
        title: '请先登录',
        subtitle: '登录后可查看历史记录',
      );
    }
    return AppErrorState(
      message: err ?? '加载失败',
      onRetry: () => _load(refresh: true),
    );
  }
}

/// 历史记录多列横向卡片（对齐 PiliPlus 与 BiliPai 历史卡片规范）。
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.item, required this.onDelete, this.onTap});

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

    // 类型角标：已收藏优先，否则用服务端 badge（如「番剧」「直播」）。
    final badgeText = item.isFav == 1
        ? '已收藏'
        : (item.badge?.isNotEmpty == true ? item.badge : null);

    double progressFraction = 0.0;
    if (progress > 0 && duration > 0) {
      progressFraction = (progress / duration).clamp(0.0, 1.0);
    } else if (progress == -1) {
      progressFraction = 1.0;
    }

    return MiuixCard(
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
                              heroTag: bvid != null && bvid.isNotEmpty
                                  ? 'history_$bvid'
                                  : null,
                            ),
                          ),
                          if (badgeText != null)
                            Positioned(
                              left: 4,
                              top: 4,
                              child: PBadge(
                                text: badgeText,
                                type: item.isFav == 1
                                    ? PBadgeType.status
                                    : PBadgeType.primary,
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
                          // B7 反馈轮#2：进度条已移出封面（改置于卡片下边框上方）。
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
                            ? const SkeletonLine(
                                width: double.infinity,
                                height: 13,
                              )
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
                                        builder: (_) =>
                                            MemberSpacePage(mid: authorMid),
                                      ),
                                    );
                                  }
                                },
                                child: Row(
                                  children: [
                                    AppIcon(
                                      AppIcons.profile(),
                                      size: 12,
                                      color: cs.outline,
                                    ),
                                    const SizedBox(width: 2),
                                    Flexible(
                                      child: Text(
                                        Pref.demoMode
                                            ? kDemoDisplayName
                                            : authorName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: tokens.text.labelSmall?.copyWith(
                                          color: cs.outline,
                                          // B7 反馈轮#2：显式 11 口径（与日期行
                                          // 一致；避免继承 14 撑破行高预算）。
                                          fontSize: 11,
                                        ),
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
                                // B7 反馈轮#2：改紧凑按压原语（24×24 命中盒），
                                // 与右/下边框保留安全空间，杜绝溢出导致不可点。
                                MiuixPressable(
                                  borderRadius: BorderRadius.circular(6),
                                  onPressed: onDelete,
                                  child: AppTooltip(
                                    message: '删除此记录',
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        6,
                                        5,
                                        4,
                                        5,
                                      ),
                                      child: AppIcon(
                                        AppIcons.clear(),
                                        size: 14,
                                        color: cs.outline,
                                      ),
                                    ),
                                  ),
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
            // 进度条：移出封面，置于卡片下边框上方（增强视觉样式）。
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
    );
  }
}