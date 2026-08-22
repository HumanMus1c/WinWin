import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/common/widgets/level_badge.dart';
import 'package:winwin/common/widgets/medal_widget.dart';
import 'package:winwin/common/widgets/p_badge.dart';
import 'package:winwin/common/widgets/refresh_indicator.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/http/dyn.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/member.dart';
import 'package:winwin/pages/member/season_series_detail_page.dart';
import 'package:winwin/pages/relation/member_relation_page.dart';
import 'package:winwin/pages/video/detail_page.dart';
import 'package:winwin/theme/app_shapes.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/utils/date_utils.dart';
import 'package:winwin/utils/duration_utils.dart';
import 'package:winwin/utils/grid.dart';
import 'package:winwin/utils/num_utils.dart';

/// 动态类型筛选枚举。
enum _DynFilterType {
  all('全部'),
  video('视频'),
  drawArticle('图文与专栏'),
  forward('转发');

  final String label;
  const _DynFilterType(this.label);
}

/// 用户空间页（对齐 PiliPlus 与 BiliPai 全面设计规范）。
///
/// 包含：
/// - 沉浸式顶部背景横幅（带渐变过渡）。
/// - 完备的用户信息头部（头像+挂件+官方认证标、大会员高亮与徽标、Lv0~Lv6与硬核等级徽标、详细经验进度条、粉丝牌、我关注的人也在关注、签名、UID与空间标签、封禁提示）。
/// - 交互操作：关注/取关/互关状态切换、私信入口、分享与更多菜单。
/// - 关系统计入口：关注数、粉丝数、获赞数（点击直达关系列表）。
/// - 标签栏（TabBar）：投稿视频、合集和系列、用户动态、详细资料。
/// - 投稿视频网格：支持最新发布与最多播放（热门）排序切换，齐次 16:10 视频卡片，完整播放/弹幕/时长/发布时间外显。
/// - 用户创建的合集：支持合集与系列列表展示，点击进入合集详情视频列表。
/// - 用户动态瀑布流：支持动态类型筛选（全部/视频/图文/转发），自适应多列瀑布流。
class MemberSpacePage extends StatefulWidget {
  const MemberSpacePage({super.key, required this.mid});

  final int mid;

  @override
  State<MemberSpacePage> createState() => _MemberSpacePageState();
}

class _MemberSpacePageState extends State<MemberSpacePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final ScrollController _scrollController = ScrollController();

  LoadingState<MemberSpaceData> _spaceState = LoadingState.loading();
  MemberCardInfoData? _cardInfo;
  MemberImages? _extraTopPhoto;

  // 投稿视频列表数据与排序
  final List<MemberVideoItem> _videos = [];
  bool _loadingVideos = false;
  bool _videoEnd = false;
  bool _videoFailed = false;
  ArchiveOrderType _videoOrder = ArchiveOrderType.pubdate;

  // 合集与系列数据
  final List<SpaceSsModel> _seasonsSeries = [];
  bool _loadingSeasons = false;
  bool _seasonEnd = false;
  bool _seasonFailed = false;
  int _seasonPage = 1;

  // 用户动态数据
  final List<DynItemModel> _dynamics = [];
  bool _loadingDynamics = false;
  bool _dynamicEnd = false;
  bool _dynamicFailed = false;
  String? _dynamicOffset;
  _DynFilterType _selectedDynFilter = _DynFilterType.all;

  // 关系状态 (0=未关注, 1=悄关, 2=已关注, 4/6=互关, 128=拉黑, -10=特关)
  int _relationStatus = 0;
  bool _isFollowingUpdating = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadSpace(),
      _loadCardInfo(),
      _loadTopPhoto(),
      _loadInitialVideos(),
      _loadInitialSeasons(),
      _loadInitialDynamics(),
    ]);
  }

  Future<void> _loadSpace() async {
    setState(() => _spaceState = LoadingState.loading());
    final res = await MemberHttp.space(mid: widget.mid);
    if (!mounted) return;
    setState(() => _spaceState = res);

    if (res case Success(:final response)) {
      final card = response.card;
      if (card != null) {
        _relationStatus = card.relation ?? 0;
      }
    }
  }

  Future<void> _loadCardInfo() async {
    final res = await MemberHttp.memberCardInfo(mid: widget.mid);
    if (!mounted) return;
    if (res case Success(:final response)) {
      setState(() => _cardInfo = response);
    }
  }

  Future<void> _loadTopPhoto() async {
    final res = await MemberHttp.topPhoto(mid: widget.mid);
    if (!mounted) return;
    if (res case Success(:final response)) {
      setState(() => _extraTopPhoto = response);
    }
  }

  Future<void> _loadInitialVideos() async {
    _videos.clear();
    _videoEnd = false;
    _videoFailed = false;
    await _loadMoreVideos();
  }

  Future<void> _loadMoreVideos() async {
    if (_loadingVideos || _videoEnd || _videoFailed) return;
    setState(() => _loadingVideos = true);
    final res = await MemberHttp.spaceArchive(
      mid: widget.mid,
      order: _videoOrder,
    );
    if (!mounted) return;
    _loadingVideos = false;
    switch (res) {
      case Success(:final response):
        _videos.addAll(response.list);
        _videoEnd = response.isEnd ?? false;
        _videoFailed = false;
        setState(() {});
      case Error():
        _videoFailed = true;
        setState(() {});
      case Loading():
        break;
    }
  }

  void _switchVideoOrder(ArchiveOrderType newOrder) {
    if (_videoOrder == newOrder) return;
    setState(() {
      _videoOrder = newOrder;
    });
    _loadInitialVideos();
  }

  Future<void> _loadInitialSeasons() async {
    _seasonsSeries.clear();
    _seasonPage = 1;
    _seasonEnd = false;
    _seasonFailed = false;
    await _loadMoreSeasons();
  }

  Future<void> _loadMoreSeasons() async {
    if (_loadingSeasons || _seasonEnd || _seasonFailed) return;
    setState(() => _loadingSeasons = true);
    final res = await MemberHttp.seasonSeriesList(
      mid: widget.mid,
      pn: _seasonPage,
    );
    if (!mounted) return;
    _loadingSeasons = false;
    switch (res) {
      case Success(:final response):
        final items = response.allItems;
        _seasonsSeries.addAll(items);
        final total = response.page?.total ?? 0;
        _seasonEnd = items.isEmpty || _seasonsSeries.length >= total;
        _seasonPage++;
        _seasonFailed = false;
        setState(() {});
      case Error():
        _seasonFailed = true;
        setState(() {});
      case Loading():
        break;
    }
  }

  Future<void> _loadInitialDynamics() async {
    _dynamics.clear();
    _dynamicOffset = null;
    _dynamicEnd = false;
    _dynamicFailed = false;
    _loadMoreDynamics();
  }

  Future<void> _loadMoreDynamics() async {
    if (_loadingDynamics || _dynamicEnd || _dynamicFailed) return;
    setState(() => _loadingDynamics = true);
    final res = await DynHttp.memberDynamic(
      hostMid: widget.mid,
      offset: _dynamicOffset,
    );
    if (!mounted) return;
    _loadingDynamics = false;
    switch (res) {
      case Success(:final response):
        _dynamics.addAll(response.items);
        _dynamicOffset = response.hasMore ? response.offset : null;
        _dynamicEnd = !response.hasMore;
        _dynamicFailed = false;
        setState(() {});
      case Error():
        _dynamicFailed = true;
        setState(() {});
      case Loading():
        break;
    }
  }

  Future<void> _toggleFollow() async {
    if (!Accounts.main.isLogin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录')),
      );
      return;
    }
    if (_isFollowingUpdating) return;

    final isCurrentlyFollowed = _relationStatus == 1 ||
        _relationStatus == 2 ||
        _relationStatus == 4 ||
        _relationStatus == 6 ||
        _relationStatus == -10;

    final act = isCurrentlyFollowed ? 2 : 1; // 1: 关注, 2: 取消关注
    setState(() => _isFollowingUpdating = true);

    final res = await MemberHttp.relationMod(mid: widget.mid, act: act);
    if (!mounted) return;
    setState(() => _isFollowingUpdating = false);

    switch (res) {
      case Success():
        setState(() {
          _relationStatus = isCurrentlyFollowed ? 0 : 2;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isCurrentlyFollowed ? '已取消关注' : '关注成功')),
        );
      case Error(:final errMsg):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errMsg ?? '操作失败')),
        );
      case Loading():
        break;
    }
  }

  List<DynItemModel> get _filteredDynamics {
    switch (_selectedDynFilter) {
      case _DynFilterType.all:
        return _dynamics;
      case _DynFilterType.video:
        return _dynamics.where((d) => d.isVideo).toList();
      case _DynFilterType.drawArticle:
        return _dynamics.where((d) => d.isDraw || d.isArticle || d.isOpus).toList();
      case _DynFilterType.forward:
        return _dynamics.where((d) => d.isForward).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: switch (_spaceState) {
        Loading() => const Center(child: CircularProgressIndicator(color: biliPink)),
        Error(:final errMsg) => _buildError(errMsg, _loadAll),
        Success(:final response) => _buildSpaceContent(response),
      },
    );
  }

  Widget _buildSpaceContent(MemberSpaceData data) {
    final card = data.card;
    final images = data.images;
    final theme = Theme.of(context);
    final isOwner = Accounts.main.isLogin && Accounts.main.mid == widget.mid;

    return AppRefreshIndicator(
      onRefresh: _loadAll,
      child: NestedScrollView(
        controller: _scrollController,
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              pinned: true,
              expandedHeight: 330.0,
              elevation: 0,
              scrolledUnderElevation: 2,
              leading: IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                ),
                onPressed: () => Navigator.maybePop(context),
              ),
              actions: [
                if (!isOwner)
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.share_outlined, color: Colors.white, size: 20),
                    ),
                    onPressed: () => _copyToClipboard('https://space.bilibili.com/${widget.mid}', '主页链接已复制'),
                  ),
                PopupMenuButton<String>(
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.more_vert, color: Colors.white, size: 20),
                  ),
                  onSelected: (val) {
                    if (val == 'copy_uid') {
                      _copyToClipboard(widget.mid.toString(), 'UID 已复制');
                    } else if (val == 'copy_link') {
                      _copyToClipboard('https://space.bilibili.com/${widget.mid}', '主页链接已复制');
                    } else if (val == 'report') {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已收到举报请求')),
                      );
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'copy_uid', child: Text('复制 UID')),
                    const PopupMenuItem(value: 'copy_link', child: Text('复制主页链接')),
                    if (!isOwner) const PopupMenuItem(value: 'report', child: Text('举报该用户')),
                  ],
                ),
                const SizedBox(width: Style.sm),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: _buildHeaderBackground(context, card, images),
              ),
            ),
            SliverToBoxAdapter(
              child: _buildUserDetailCard(context, card, data.silence),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _SliverAppBarDelegate(
                TabBar(
                  controller: _tabController,
                  indicatorSize: TabBarIndicatorSize.label,
                  labelColor: theme.colorScheme.primary,
                  unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                  indicatorColor: theme.colorScheme.primary,
                  tabs: [
                    Tab(text: '投稿 (${_videos.length})'),
                    Tab(text: '合集 (${_seasonsSeries.length})'),
                    Tab(text: '动态 (${_dynamics.length})'),
                    const Tab(text: '详细资料'),
                  ],
                ),
                theme.colorScheme.surface,
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildVideosTab(),
            _buildSeasonsTab(),
            _buildDynamicsTab(),
            _buildAboutTab(card),
          ],
        ),
      ),
    );
  }

  /// 顶部横幅与头像背景
  Widget _buildHeaderBackground(
    BuildContext context,
    MemberCard? card,
    MemberImages? images,
  ) {
    final theme = Theme.of(context);
    String? topPhoto = images?.topPhoto ??
        images?.imgUrl ??
        _extraTopPhoto?.topPhoto ??
        _extraTopPhoto?.imgUrl ??
        _cardInfo?.spaceLImg ??
        _cardInfo?.spaceSImg;

    if (topPhoto != null && topPhoto.isNotEmpty) {
      if (topPhoto.startsWith('//')) {
        topPhoto = 'https:$topPhoto';
      } else if (topPhoto.startsWith('http://')) {
        topPhoto = topPhoto.replaceFirst('http://', 'https://');
      }
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        if (topPhoto != null && topPhoto.isNotEmpty)
          CachedNetworkImage(
            imageUrl: topPhoto,
            fit: BoxFit.cover,
            errorWidget: (_, _, _) => _defaultHeaderGradient(theme),
          )
        else
          _defaultHeaderGradient(theme),
        // 阴影遮罩
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.4),
                Colors.transparent,
                theme.scaffoldBackgroundColor.withValues(alpha: 0.8),
                theme.scaffoldBackgroundColor,
              ],
              stops: const [0.0, 0.4, 0.85, 1.0],
            ),
          ),
        ),
      ],
    );
  }

  Widget _defaultHeaderGradient(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            biliPink.withValues(alpha: 0.7),
            biliBlue.withValues(alpha: 0.5),
            theme.scaffoldBackgroundColor,
          ],
        ),
      ),
    );
  }

  /// 用户详细信息卡片（头像、名字、会员、等级经验、粉丝牌、认证、签名、关注TA的人等）
  Widget _buildUserDetailCard(BuildContext context, MemberCard? card, int? silence) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isVip = card?.vip?.isVip ?? false;
    final vipColor = cs.primary;
    final level = card?.level ?? _cardInfo?.currentLevel ?? 0;
    final isSenior = card?.levelInfo?.isSeniorMember ?? false;
    final medal = card?.liveFansWearing?.detailV2;
    final followedUpper = card?.followingsFollowedUpper;
    final isOwner = Accounts.main.isLogin && Accounts.main.mid == widget.mid;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Style.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头像 + 关系操作按钮行
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 头像与认证标
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 78,
                    height: 78,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: cs.surface, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: (card?.face?.isNotEmpty ?? false)
                        ? CachedNetworkImage(
                            imageUrl: card!.face!,
                            fit: BoxFit.cover,
                            placeholder: (_, _) => const ColoredBox(color: Colors.grey),
                            errorWidget: (_, _, _) => const Icon(Icons.person, size: 40),
                          )
                        : const Icon(Icons.person, size: 40),
                  ),
                  if (card?.officialVerify?.isOfficial ?? false)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: cs.surface,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.offline_bolt,
                          size: 20,
                          color: card?.officialVerify?.type == 0
                              ? Colors.amber.shade600
                              : Colors.blue.shade600,
                        ),
                      ),
                    ),
                ],
              ),
              const Spacer(),
              // 操作按钮（关注 / 私信）
              if (!isOwner) ...[
                IconButton.filledTonal(
                  onPressed: () {
                    _copyToClipboard('UID: ${widget.mid}', '用户已选择');
                  },
                  tooltip: '私信',
                  icon: const Icon(Icons.mail_outline, size: 20),
                ),
                const SizedBox(width: Style.sm),
                FilledButton.tonal(
                  onPressed: _isFollowingUpdating ? null : _toggleFollow,
                  style: FilledButton.styleFrom(
                    backgroundColor: _relationStatus != 0
                        ? cs.surfaceContainerHighest
                        : biliPink,
                    foregroundColor: _relationStatus != 0
                        ? cs.onSurfaceVariant
                        : Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: Style.lg, vertical: Style.sm),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isFollowingUpdating)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else ...[
                        Icon(
                          _relationStatus != 0 ? Icons.check : Icons.add,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          switch (_relationStatus) {
                            0 => '关注',
                            1 => '悄悄关注',
                            2 => '已关注',
                            4 || 6 => '已互关',
                            128 => '移除黑名单',
                            -10 => '特别关注',
                            _ => '已关注',
                          },
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: Style.md),
          // 用户昵称 + 会员标 + 等级标 + 粉丝牌
          Wrap(
            spacing: Style.sm,
            runSpacing: Style.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              GestureDetector(
                onTap: () => _copyToClipboard(card?.name ?? '', '昵称已复制'),
                child: Text(
                  card?.name ?? '未知用户',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isVip ? vipColor : null,
                  ),
                ),
              ),
              if (isVip)
                PBadge(
                  text: card?.vip?.labelText ?? '大会员',
                  type: PBadgeType.badge,
                ),
              LevelBadge(level: level, isSenior: isSenior),
              if (medal != null)
                MedalWidget(
                  medalName: medal.medalName ?? '勋章',
                  level: medal.level ?? 1,
                  backgroundColor: medal.parsedBackgroundColor,
                  nameColor: medal.parsedTextColor,
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('粉丝勋章: ${medal.medalName} Lv.${medal.level}')),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: Style.sm),
          // 等级经验进度条
          LevelExpBar(
            level: level,
            currentExp: _cardInfo?.currentExp,
            nextExp: _cardInfo?.nextExp,
            currentMin: _cardInfo?.currentMin,
            isSenior: isSenior,
          ),
          // 官方认证描述
          if ((card?.officialVerify?.desc?.isNotEmpty ?? false) ||
              (card?.officialVerify?.spliceTitle?.isNotEmpty ?? false)) ...[
            const SizedBox(height: Style.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: Style.sm, vertical: 3),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(Style.radiusSm),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    size: 14,
                    color: Colors.amber.shade700,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      card?.officialVerify?.desc ?? card?.officialVerify?.spliceTitle ?? '',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // 用户个性签名
          if (card?.sign?.isNotEmpty ?? false) ...[
            const SizedBox(height: Style.sm),
            SelectableText(
              card!.sign!.trim(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.85),
                height: 1.4,
              ),
            ),
          ],
          // UID 与 空间标签
          const SizedBox(height: Style.sm),
          Wrap(
            spacing: Style.md,
            runSpacing: Style.xs,
            children: [
              GestureDetector(
                onTap: () => _copyToClipboard(widget.mid.toString(), 'UID 已复制'),
                child: Text(
                  'UID: ${widget.mid}',
                  style: TextStyle(fontSize: 12, color: cs.outline),
                ),
              ),
              if (card?.spaceTags.isNotEmpty ?? false)
                for (final tag in card!.spaceTags)
                  Text(
                    tag.title ?? '',
                    style: TextStyle(fontSize: 12, color: cs.outline),
                  ),
            ],
          ),
          // “我关注的人也在关注”
          if (followedUpper != null && followedUpper.items.isNotEmpty) ...[
            const SizedBox(height: Style.sm),
            InkWell(
              onTap: () {
                showMemberRelationPage(
                  context,
                  type: RelationType.followings,
                  vmid: widget.mid,
                );
              },
              borderRadius: BorderRadius.circular(Style.radiusSm),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: Style.sm, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(Style.radiusSm),
                ),
                child: Row(
                  children: [
                    _buildOverlappingAvatars(followedUpper.items.take(3).toList()),
                    const SizedBox(width: Style.sm),
                    Expanded(
                      child: Text(
                        '${followedUpper.items.map((e) => e.name ?? '').join('、')} 等人也关注了 TA',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 16, color: cs.outline),
                  ],
                ),
              ),
            ),
          ],
          // 封禁提示
          if (silence == 1) ...[
            const SizedBox(height: Style.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: Style.md, vertical: Style.xs),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(Style.radiusSm),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.block, size: 16, color: Colors.red),
                  SizedBox(width: Style.sm),
                  Text('该账号当前处于封禁状态', style: TextStyle(color: Colors.red, fontSize: 12)),
                ],
              ),
            ),
          ],
          // 统计行（关注 / 粉丝 / 获赞）
          const SizedBox(height: Style.md),
          Row(
            children: [
              _statItem(
                context,
                label: '关注',
                count: card?.following ?? 0,
                onTap: () => showMemberRelationPage(
                  context,
                  type: RelationType.followings,
                  vmid: widget.mid,
                ),
              ),
              const SizedBox(width: Style.xxl),
              _statItem(
                context,
                label: '粉丝',
                count: card?.fans ?? _cardInfo?.follower ?? 0,
                onTap: () => showMemberRelationPage(
                  context,
                  type: RelationType.fans,
                  vmid: widget.mid,
                ),
              ),
              const SizedBox(width: Style.xxl),
              _statItem(
                context,
                label: '获赞',
                count: card?.likes?.likeNum ?? _cardInfo?.likeNum ?? 0,
              ),
            ],
          ),
          const SizedBox(height: Style.md),
        ],
      ),
    );
  }

  Widget _buildOverlappingAvatars(List<MemberFollowedUpperItem> items) {
    return SizedBox(
      height: 22,
      width: (items.length * 15.0 + 7.0),
      child: Stack(
        children: [
          for (int i = 0; i < items.length; i++)
            Positioned(
              left: i * 15.0,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                clipBehavior: Clip.antiAlias,
                child: (items[i].face?.isNotEmpty ?? false)
                    ? CachedNetworkImage(
                        imageUrl: items[i].face!,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => const ColoredBox(color: Colors.grey),
                      )
                    : const ColoredBox(color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statItem(
    BuildContext context, {
    required String label,
    required int count,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          NumUtils.formatNum(count),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Style.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: content,
        ),
      );
    }
    return content;
  }

  /// 投稿视频 Tab（齐次网格排版，支持最新/热门排序切换）
  Widget _buildVideosTab() {
    final gridDelegate = Grid.videoCardVDelegate(
      mainAxisExtent: MediaQuery.textScalerOf(context).scale(86),
    );

    return CustomScrollView(
      slivers: [
        // 排序切换栏 (最新发布 / 最多播放热门)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Style.safeSpace, Style.sm, Style.safeSpace, 0),
            child: Row(
              children: [
                Text(
                  '共 ${_videos.length} 支视频',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                const Spacer(),
                for (final order in ArchiveOrderType.values)
                  Padding(
                    padding: const EdgeInsets.only(left: Style.xs),
                    child: ChoiceChip(
                      label: Text(order.label),
                      selected: _videoOrder == order,
                      onSelected: (selected) {
                        if (selected) {
                          _switchVideoOrder(order);
                        }
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_videos.isEmpty && !_loadingVideos)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 80),
              child: Center(child: Text('暂无投稿视频')),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.all(Style.safeSpace),
            sliver: SliverGrid(
              gridDelegate: gridDelegate,
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index >= _videos.length) return null;
                  if (index == _videos.length - 1) {
                    _loadMoreVideos();
                  }
                  return _buildVideoCard(_videos[index]);
                },
                childCount: _videos.length,
              ),
            ),
          ),
        if (_loadingVideos)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: Style.lg),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
        if (_videoFailed)
          SliverToBoxAdapter(
            child: Center(
              child: TextButton(
                onPressed: () {
                  setState(() => _videoFailed = false);
                  _loadMoreVideos();
                },
                child: const Text('加载失败，点击重试'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildVideoCard(MemberVideoItem item) {
    final theme = Theme.of(context);
    final shapes = theme.extension<AppShapes>() ?? AppShapes.ios;
    final radius = shapes.medium;
    final bvid = item.bvid;

    return Card(
      child: InkWell(
        onTap: bvid == null
            ? null
            : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VideoDetailPage(bvid: bvid, cover: item.pic),
                  ),
                ),
        borderRadius: BorderRadius.all(radius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 10,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NetworkImgLayer(
                    src: item.pic,
                    width: double.infinity,
                    height: double.infinity,
                    borderRadius: BorderRadius.vertical(top: radius),
                  ),
                  if ((item.duration ?? 0) > 0)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: PBadge(
                        text: DurationUtils.formatDuration(item.duration),
                        type: PBadgeType.duration,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(height: 1.35),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.play_circle_outlined,
                        size: 13,
                        color: theme.colorScheme.outline.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        NumUtils.formatNum(item.play),
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.outline.withValues(alpha: 0.8),
                        ),
                      ),
                      if (item.danmaku != null) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.subtitles_outlined,
                          size: 13,
                          color: theme.colorScheme.outline.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          NumUtils.formatNum(item.danmaku),
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.outline.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                      if (item.pubdate != null) ...[
                        const Spacer(),
                        Text(
                          DateFormatUtils.dateFormat(item.pubdate!),
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.outline.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 合集与系列 Tab
  Widget _buildSeasonsTab() {
    if (_seasonsSeries.isEmpty && !_loadingSeasons) {
      return const Center(child: Text('暂无创建的合集或系列'));
    }

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(Style.safeSpace),
          sliver: SliverList.builder(
            itemCount: _seasonsSeries.length,
            itemBuilder: (context, index) {
              if (index == _seasonsSeries.length - 1) {
                _loadMoreSeasons();
              }
              final model = _seasonsSeries[index];
              return _buildSeasonSeriesCard(model);
            },
          ),
        ),
        if (_loadingSeasons)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: Style.lg),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
        if (_seasonFailed)
          SliverToBoxAdapter(
            child: Center(
              child: TextButton(
                onPressed: () {
                  setState(() => _seasonFailed = false);
                  _loadMoreSeasons();
                },
                child: const Text('加载失败，点击重试'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSeasonSeriesCard(SpaceSsModel model) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final meta = model.meta;
    if (meta == null) return const SizedBox.shrink();

    final isSeason = meta.isSeason;
    final total = meta.total ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: Style.md),
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Style.radiusMd),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.25)),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SeasonSeriesDetailPage(
                mid: widget.mid,
                seasonId: meta.seasonId,
                seriesId: meta.seriesId,
                title: meta.name ?? '合集列表',
                cover: meta.cover,
                description: meta.description,
                total: meta.total,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(Style.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(Style.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面图与角标
              ClipRRect(
                borderRadius: BorderRadius.circular(Style.radiusSm),
                child: Stack(
                  children: [
                    SizedBox(
                      width: 120,
                      height: 75,
                      child: NetworkImgLayer(
                        src: meta.cover,
                        width: 120,
                        height: 75,
                        borderRadius: BorderRadius.circular(Style.radiusSm),
                      ),
                    ),
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: PBadge(
                        text: '${isSeason ? '合集' : '系列'}: $total',
                        type: PBadgeType.badge,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Style.md),
              // 标题、更新时间、简介
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meta.name ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (meta.ptime != null)
                      Text(
                        '更新于 ${DateFormatUtils.dateFormat(meta.ptime!)}',
                        style: TextStyle(fontSize: 11, color: cs.outline),
                      ),
                    if (meta.description?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 4),
                      Text(
                        meta.description!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  /// 动态 Tab（类型筛选条 + 自适应高度瀑布流排版）
  Widget _buildDynamicsTab() {
    final filtered = _filteredDynamics;

    return CustomScrollView(
      slivers: [
        // 动态类型筛选器
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Style.safeSpace, Style.sm, Style.safeSpace, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _DynFilterType.values.map((filter) {
                  final isSelected = _selectedDynFilter == filter;
                  return Padding(
                    padding: const EdgeInsets.only(right: Style.sm),
                    child: FilterChip(
                      label: Text(filter.label),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _selectedDynFilter = filter);
                        }
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        if (filtered.isEmpty && !_loadingDynamics)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 80),
              child: Center(child: Text('暂无该类型动态')),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.all(Style.safeSpace),
            sliver: SliverMasonryGrid.extent(
              maxCrossAxisExtent: 440.0,
              mainAxisSpacing: Style.cardSpace,
              crossAxisSpacing: Style.cardSpace,
              childCount: filtered.length,
              itemBuilder: (context, index) {
                if (index == filtered.length - 1) {
                  _loadMoreDynamics();
                }
                return _buildSpaceDynamicCard(filtered[index]);
              },
            ),
          ),
        if (_loadingDynamics)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: Style.lg),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
        if (_dynamicFailed)
          SliverToBoxAdapter(
            child: Center(
              child: TextButton(
                onPressed: () {
                  setState(() => _dynamicFailed = false);
                  _loadMoreDynamics();
                },
                child: const Text('动态加载失败，点击重试'),
              ),
            ),
          ),
      ],
    );
  }

  /// 用户空间动态卡片（自适应不同动态类型的高度和内部结构）
  Widget _buildSpaceDynamicCard(DynItemModel item) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final author = item.author;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Style.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 头部作者与时间
            Row(
              children: [
                NetworkImgLayer(
                  src: author?.face,
                  width: 38,
                  height: 38,
                  type: 'avatar',
                ),
                const SizedBox(width: Style.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              author?.name ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (author?.pubAction?.isNotEmpty ?? false) ...[
                            const SizedBox(width: 4),
                            Text(
                              author!.pubAction!,
                              style: TextStyle(fontSize: 11, color: cs.outline),
                            ),
                          ],
                        ],
                      ),
                      if (item.pubTs != null)
                        Text(
                          DateFormatUtils.dateFormat(item.pubTs!),
                          style: TextStyle(fontSize: 11, color: cs.outline),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            // 正文富文本
            if (item.text?.isNotEmpty ?? false) ...[
              const SizedBox(height: Style.sm),
              if (item.richTextNodes.isNotEmpty)
                Text.rich(
                  TextSpan(children: _buildRichSpans(context, item.richTextNodes, cs.primary)),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                )
              else
                Text(
                  item.text!,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
            ],
            // 动态主体：视频 / 追番 / 图文 / 专栏 / 直播 / 转发
            if (item.isForward && item.orig != null) ...[
              const SizedBox(height: Style.sm),
              _buildForwardContent(context, item.orig!),
            ] else if (item.isVideo && item.archive?.bvid != null) ...[
              const SizedBox(height: Style.sm),
              _buildVideoPreview(context, item.archive!),
            ] else if (item.isPgc && item.pgc != null) ...[
              const SizedBox(height: Style.sm),
              _buildPgcPreview(context, item.pgc!),
            ] else if (item.draw != null && item.draw!.items.isNotEmpty) ...[
              const SizedBox(height: Style.sm),
              _buildDrawGrid(context, item.draw!.items),
            ] else if (item.opus != null) ...[
              const SizedBox(height: Style.sm),
              _buildOpusCard(context, item.opus!),
            ] else if (item.article != null) ...[
              const SizedBox(height: Style.sm),
              _buildArticleCard(context, item.article!),
            ] else if (item.liveRcmd != null) ...[
              const SizedBox(height: Style.sm),
              _buildLiveCard(context, item.liveRcmd!),
            ],
            // 附加商品卡
            if (item.additional?.goodsItems.isNotEmpty ?? false) ...[
              const SizedBox(height: Style.sm),
              _buildGoodsCard(context, item.additional!),
            ],
            // 底部互动行
            if (item.stat != null) ...[
              const SizedBox(height: Style.sm),
              const Divider(height: 1, thickness: 0.5),
              const SizedBox(height: Style.xs),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statActionItem(Icons.reply_outlined, item.stat!.repost ?? 0, cs.outline),
                  _statActionItem(Icons.chat_bubble_outline, item.stat!.comment ?? 0, cs.outline),
                  _statActionItem(Icons.thumb_up_outlined, item.stat!.like ?? 0, cs.outline),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statActionItem(IconData icon, int count, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          count > 0 ? NumUtils.formatNum(count) : '0',
          style: TextStyle(fontSize: 12, color: color),
        ),
      ],
    );
  }

  Widget _buildForwardContent(BuildContext context, DynItemModel orig) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final origAuthor = orig.author;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Style.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(Style.radiusMd),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (origAuthor?.name != null)
            GestureDetector(
              onTap: () {
                final authorMid = origAuthor?.mid;
                if (authorMid != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => MemberSpacePage(mid: authorMid)),
                  );
                }
              },
              child: Text(
                '@${origAuthor?.name}',
                style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          if (orig.text?.isNotEmpty ?? false) ...[
            const SizedBox(height: 4),
            Text(
              orig.text!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ],
          if (orig.isVideo && orig.archive?.bvid != null) ...[
            const SizedBox(height: Style.sm),
            _buildVideoPreview(context, orig.archive!),
          ] else if (orig.draw != null && orig.draw!.items.isNotEmpty) ...[
            const SizedBox(height: Style.sm),
            _buildDrawGrid(context, orig.draw!.items),
          ] else if (orig.opus != null) ...[
            const SizedBox(height: Style.sm),
            _buildOpusCard(context, orig.opus!),
          ],
        ],
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
          MaterialPageRoute(builder: (_) => VideoDetailPage(bvid: bvid, cover: archive.cover)),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Style.radiusSm),
        child: Stack(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: NetworkImgLayer(
                src: archive.cover,
                width: double.infinity,
                height: double.infinity,
                borderRadius: BorderRadius.circular(Style.radiusSm),
              ),
            ),
            Positioned.fill(
              child: Container(
                alignment: Alignment.bottomLeft,
                padding: const EdgeInsets.all(Style.sm),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.65)],
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
                    if (archive.durationText != null || archive.play != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (archive.durationText != null)
                            PBadge(text: archive.durationText, type: PBadgeType.duration),
                          if (archive.play != null) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.play_circle_outlined, size: 12, color: Colors.white70),
                            const SizedBox(width: 2),
                            Text(
                              NumUtils.formatNum(archive.play),
                              style: const TextStyle(fontSize: 11, color: Colors.white70),
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

  Widget _buildDrawGrid(BuildContext context, List<DynDrawItem> pics) {
    if (pics.isEmpty) return const SizedBox.shrink();
    if (pics.length == 1) {
      final item = pics.first;
      final w = item.width ?? 16;
      final h = item.height ?? 9;
      final aspect = (w > 0 && h > 0) ? (w / h).clamp(0.7, 2.0) : 16 / 9;
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 240),
        child: AspectRatio(
          aspectRatio: aspect,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Style.radiusSm),
            child: NetworkImgLayer(
              src: item.src,
              width: double.infinity,
              height: double.infinity,
              borderRadius: BorderRadius.circular(Style.radiusSm),
            ),
          ),
        ),
      );
    }

    final crossAxisCount = pics.length == 4 ? 2 : (pics.length >= 3 ? 3 : 2);
    final displayPics = pics.take(9).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : 380.0;
        const spacing = 4.0;
        final rawItemWidth = (totalWidth - spacing * (crossAxisCount - 1)) / crossAxisCount;
        final itemWidth = rawItemWidth.clamp(50.0, 130.0);

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: displayPics.map((pic) {
            return SizedBox(
              width: itemWidth,
              height: itemWidth,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Style.radiusSm),
                child: NetworkImgLayer(
                  src: pic.src,
                  width: double.infinity,
                  height: double.infinity,
                  borderRadius: BorderRadius.circular(Style.radiusSm),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildOpusCard(BuildContext context, DynOpus opus) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (opus.title?.isNotEmpty ?? false)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              opus.title!,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        if (opus.summaryText?.isNotEmpty ?? false)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              opus.summaryText!,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        if (opus.pics.isNotEmpty) _buildDrawGrid(context, opus.pics),
        if (opus.video?.bvid != null) ...[
          const SizedBox(height: Style.sm),
          _buildVideoPreview(context, opus.video!),
        ],
      ],
    );
  }

  Widget _buildArticleCard(BuildContext context, DynArticle article) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cover = article.covers.isNotEmpty ? article.covers.first : null;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Style.radiusMd),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Style.md),
        child: Row(
          children: [
            if (cover?.isNotEmpty ?? false) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(Style.radiusSm),
                child: SizedBox(
                  width: 100,
                  height: 70,
                  child: NetworkImgLayer(src: cover, width: 100, height: 70),
                ),
              ),
              const SizedBox(width: Style.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (article.label?.isNotEmpty ?? false)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: PBadge(text: article.label!, type: PBadgeType.badge),
                    ),
                  Text(
                    article.title ?? '专栏文章',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveCard(BuildContext context, DynLiveRcmd live) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Style.radiusMd),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Style.md),
        child: Row(
          children: [
            if (live.cover?.isNotEmpty ?? false) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(Style.radiusSm),
                child: Stack(
                  children: [
                    SizedBox(
                      width: 110,
                      height: 70,
                      child: NetworkImgLayer(src: live.cover, width: 110, height: 70),
                    ),
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text(
                          'LIVE',
                          style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Style.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    live.title ?? '正在直播',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  if (live.watchedShow?.isNotEmpty ?? false)
                    Text(
                      live.watchedShow!,
                      style: TextStyle(fontSize: 11, color: cs.outline),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPgcPreview(BuildContext context, DynPgc pgc) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cover = pgc.cover;

    return Container(
      padding: const EdgeInsets.all(Style.sm),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(Style.radiusSm),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          if (cover?.isNotEmpty ?? false) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(Style.radiusXs),
              child: SizedBox(
                width: 90,
                height: 60,
                child: NetworkImgLayer(src: cover, width: 90, height: 60),
              ),
            ),
            const SizedBox(width: Style.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pgc.title ?? '剧集更新',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (pgc.badge?.isNotEmpty ?? false)
                  PBadge(text: pgc.badge!, type: PBadgeType.badge),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoodsCard(BuildContext context, DynAdditional additional) {
    final item = additional.goodsItems.first;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(Style.sm),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(Style.radiusSm),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          if (item.cover?.isNotEmpty ?? false) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(Style.radiusXs),
              child: NetworkImgLayer(src: item.cover, width: 36, height: 36),
            ),
            const SizedBox(width: Style.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name ?? '商品推荐',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                ),
                if (item.price?.isNotEmpty ?? false)
                  Text(
                    item.price!,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<InlineSpan> _buildRichSpans(
    BuildContext context,
    List<DynRichTextNode> nodes,
    Color primaryColor,
  ) {
    final spans = <InlineSpan>[];
    for (final node in nodes) {
      final type = node.type ?? '';
      final text = node.text ?? node.origText ?? '';
      if (text.isEmpty) continue;

      if (node.emojiUrl?.isNotEmpty ?? false) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Image.network(
              node.emojiUrl!,
              width: 20,
              height: 20,
              errorBuilder: (_, _, _) => Text(text),
            ),
          ),
        ));
      } else if (type.contains('BV') || (node.rid?.startsWith('BV') ?? false)) {
        final bvid = node.rid ?? (text.startsWith('BV') ? text : null);
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: InkWell(
            onTap: () {
              if (bvid != null) {
                Navigator.push(context, MaterialPageRoute(builder: (_) => VideoDetailPage(bvid: bvid)));
              }
            },
            child: Text(text, style: TextStyle(color: primaryColor, fontWeight: FontWeight.w500)),
          ),
        ));
      } else if (type.contains('AT') || text.startsWith('@')) {
        final mid = int.tryParse(node.rid ?? '');
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: InkWell(
            onTap: () {
              if (mid != null && mid > 0) {
                Navigator.push(context, MaterialPageRoute(builder: (_) => MemberSpacePage(mid: mid)));
              }
            },
            child: Text(text, style: TextStyle(color: primaryColor, fontWeight: FontWeight.w500)),
          ),
        ));
      } else {
        spans.add(TextSpan(text: text));
      }
    }
    return spans;
  }

  /// 详细资料 Tab
  Widget _buildAboutTab(MemberCard? card) {
    final theme = Theme.of(context);
    final level = card?.level ?? _cardInfo?.currentLevel ?? 0;
    final isSenior = card?.levelInfo?.isSeniorMember ?? false;

    return ListView(
      padding: const EdgeInsets.all(Style.safeSpace),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Style.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('基本信息', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: Style.md),
                _infoRow('UID', '${widget.mid}'),
                _infoRow('昵称', card?.name ?? '未知'),
                _infoRow('等级', 'Lv.$level ${isSenior ? '(硬核会员)' : ''}'),
                if (_cardInfo?.currentExp != null)
                  _infoRow('当前经验', '${_cardInfo!.currentExp} / ${_cardInfo!.nextExp ?? 'MAX'}'),
                if (card?.vip?.isVip ?? false)
                  _infoRow('会员状态', card?.vip?.labelText ?? '大会员'),
                if (card?.officialVerify?.isOfficial ?? false)
                  _infoRow('官方认证', card?.officialVerify?.desc ?? card?.officialVerify?.spliceTitle ?? '已认证'),
                if (card?.sign?.isNotEmpty ?? false)
                  _infoRow('个性签名', card!.sign!),
                if (_cardInfo?.archiveCount != null)
                  _infoRow('稿件总数', '${_cardInfo!.archiveCount}'),
                if (_cardInfo?.likeNum != null)
                  _infoRow('获赞总数', NumUtils.formatNum(_cardInfo!.likeNum)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Style.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(String text, String tip) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tip)));
  }

  Widget _buildError(String? errMsg, VoidCallback onRetry) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_outlined, size: 48, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: Style.lg),
          Text(errMsg ?? '加载失败', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: Style.xl),
          FilledButton.tonal(onPressed: onRetry, child: const Text('点击重试')),
        ],
      ),
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar, this._bgColor);

  final TabBar _tabBar;
  final Color _bgColor;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: _bgColor,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return oldDelegate._bgColor != _bgColor || oldDelegate._tabBar != _tabBar;
  }
}
