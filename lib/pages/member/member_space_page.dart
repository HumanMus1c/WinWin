import 'dart:async';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import 'package:winwin/theme/app_colors.dart';
import 'package:winwin/common/skeleton/skeleton.dart';
import 'package:winwin/common/skeleton/video_card_h.dart';
import 'package:winwin/common/skeleton/video_card_v.dart';
import 'package:winwin/common/widgets/dyn/dyn_action_bar.dart';
import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/common/widgets/level_badge.dart';
import 'package:winwin/common/widgets/medal_widget.dart';
import 'package:winwin/common/widgets/miuix_popup_menu.dart';
import 'package:winwin/common/widgets/p_badge.dart';
import 'package:winwin/common/widgets/refresh_indicator.dart';
import 'package:winwin/common/widgets/demo_editable.dart';
import 'package:winwin/common/widgets/demo_mask.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/core/demo/demo_overrides.dart';
import 'package:winwin/core/event/event_bus.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/http/dyn.dart';
import 'package:winwin/http/fav.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/member.dart';
import 'package:winwin/models/fav/fav_models.dart';
import 'package:winwin/common/widgets/image/image_gallery_viewer.dart';
import 'package:winwin/utils/image_utils.dart';
import 'package:winwin/pages/article/article_page.dart';
import 'package:winwin/pages/bangumi/bangumi_detail_page.dart';
import 'package:winwin/pages/dynamics/detail_page.dart';
import 'package:winwin/pages/fav/fav_page.dart';
import 'package:winwin/pages/live/live_room_page.dart';
import 'package:winwin/pages/member/season_series_detail_page.dart';
import 'package:winwin/pages/relation/member_relation_page.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/pages/video/detail_page.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/utils/date_utils.dart';
import 'package:winwin/utils/duration_utils.dart';
import 'package:winwin/utils/grid.dart';
import 'package:winwin/utils/num_utils.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/core/shell/app_routes.dart';
import 'package:winwin/core/shell/app_dialogs.dart';
import 'package:winwin/core/shell/app_scaffold.dart';
import 'package:winwin/ui/components/app_progress.dart';
import 'package:winwin/ui/components/app_tooltip.dart';
import 'package:winwin/ui/components/app_components.dart';

/// 动态类型筛选枚举。
enum _DynFilterType {
  all('全部'),
  video('视频'),
  drawArticle('图文与专栏'),
  forward('转发');

  final String label;
  const _DynFilterType(this.label);
}

/// 空间板块类型枚举。
enum _SpaceTabType {
  video('投稿'),
  seasons('合集'),
  dynamics('动态'),
  fav('收藏'),
  bangumi('追番'),
  liked('点赞'),
  about('详细资料');

  final String label;
  const _SpaceTabType(this.label);
}

/// 演示模式粉丝牌预设配色选项。
const List<(int, String)> _kMedalColorOptions = [
  (0, '默认'),
  (1, '粉色'),
  (2, '蓝色'),
  (3, '青色'),
  (4, '紫色'),
  (5, '金色'),
  (6, '红色'),
];

/// 演示模式粉丝牌预设配色值。
const Map<int, Color> _kMedalColors = {
  1: Color(0xFFFB7299),
  2: Color(0xFF5C9CE6),
  3: Color(0xFF42B8B0),
  4: Color(0xFF9B6BE0),
  5: Color(0xFFD9A03F),
  6: Color(0xFFE05E5E),
};

/// 演示模式下可编辑的粉丝牌（牌子名 / 等级 / 配色，仅演示期生效）。
class _DemoMedalEdit extends StatefulWidget {
  const _DemoMedalEdit({
    required this.visible,
    required this.medalName,
    required this.level,
    this.backgroundColor,
    this.nameColor,
  });

  final bool visible;
  final String medalName;
  final int level;
  final Color? backgroundColor;
  final Color? nameColor;

  @override
  State<_DemoMedalEdit> createState() => _DemoMedalEditState();
}

class _DemoMedalEditState extends State<_DemoMedalEdit> {
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    Pref.demoModeNotifier.addListener(_onChanged);
    DemoOverrides.revision.addListener(_onChanged);
  }

  @override
  void dispose() {
    Pref.demoModeNotifier.removeListener(_onChanged);
    DemoOverrides.revision.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _edit() {
    showAppDialog<void>(
      context: context,
      builder: (_) => _DemoMedalDialog(
        name: DemoOverrides.text('space.medal.name') ?? widget.medalName,
        level: DemoOverrides.choice('space.medal.level') ?? widget.level,
        colorIndex: DemoOverrides.choice('space.medal.color') ?? 0,
        canReset: DemoOverrides.text('space.medal.name') != null ||
            DemoOverrides.choice('space.medal.level') != null ||
            DemoOverrides.choice('space.medal.color') != null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!Pref.demoMode) {
      if (!widget.visible) return const SizedBox.shrink();
      return MedalWidget(
        medalName: widget.medalName,
        level: widget.level,
        backgroundColor: widget.backgroundColor ?? biliPink,
        nameColor: widget.nameColor ?? AppColors.white,
        onTap: () {
          showToast(context, '粉丝勋章: ${widget.medalName} Lv.${widget.level}');
        },
      );
    }
    // 演示模式：悬停高亮、点击编辑（覆盖值 ?? 真实值）。
    final name = DemoOverrides.text('space.medal.name') ?? widget.medalName;
    final level = DemoOverrides.choice('space.medal.level') ?? widget.level;
    final colorIndex = DemoOverrides.choice('space.medal.color') ?? 0;
    final bg = _kMedalColors[colorIndex] ?? widget.backgroundColor ?? biliPink;
    final hasOverride = DemoOverrides.text('space.medal.name') != null ||
        DemoOverrides.choice('space.medal.level') != null ||
        DemoOverrides.choice('space.medal.color') != null;
    final cs = AppThemeHost.of(context).colors;
    return AppTooltip(
      message: '演示模式：点击编辑',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _edit,
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: _hovered
                    ? cs.primary.withValues(alpha: 0.10)
                    : AppColors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: (widget.visible || hasOverride)
                  ? MedalWidget(
                      medalName: name,
                      level: level,
                      backgroundColor: bg,
                      nameColor: widget.nameColor ?? AppColors.white,
                    )
                  : const SizedBox(width: 64, height: 16),
            ),
          ),
        ),
      ),
    );
  }
}

/// 粉丝牌编辑弹层（牌子名 + 等级 + 配色）。
class _DemoMedalDialog extends StatefulWidget {
  const _DemoMedalDialog({
    required this.name,
    required this.level,
    required this.colorIndex,
    required this.canReset,
  });

  final String name;
  final int level;
  final int colorIndex;
  final bool canReset;

  @override
  State<_DemoMedalDialog> createState() => _DemoMedalDialogState();
}

class _DemoMedalDialogState extends State<_DemoMedalDialog> {
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.name);
  late final TextEditingController _levelCtrl =
      TextEditingController(text: '${widget.level}');
  late int _colorIndex = widget.colorIndex;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _levelCtrl.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final level = int.tryParse(_levelCtrl.text.trim());
    if (level == null || level < 0) {
      showToast(context, '请输入非负整数等级');
      return;
    }
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      showToast(context, '牌子名不能为空');
      return;
    }
    await DemoOverrides.set('space.medal.name', name);
    await DemoOverrides.set('space.medal.level', level);
    await DemoOverrides.set('space.medal.color', _colorIndex);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _reset() async {
    await DemoOverrides.clear('space.medal.name');
    await DemoOverrides.clear('space.medal.level');
    await DemoOverrides.clear('space.medal.color');
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑粉丝牌'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: '牌子名'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _levelCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: '等级'),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (idx, label) in _kMedalColorOptions)
                ChoiceChip(
                  label: Text(label, style: const TextStyle(fontSize: 12)),
                  selected: _colorIndex == idx,
                  onSelected: (_) => setState(() => _colorIndex = idx),
                ),
            ],
          ),
        ],
      ),
      actions: [
        if (widget.canReset)
          MiuixTextButton('恢复默认', onPressed: _reset),
        MiuixTextButton('取消', onPressed: () => Navigator.pop(context)),
        AppPrimaryButton(onPressed: _apply, child: const Text('确定')),
      ],
    );
  }
}

/// 用户空间页（对齐 PiliPlus 与 BiliPai 全面设计规范）。
///
/// 包含：
/// - 沉浸式顶部背景横幅（双通道与自动协议补全）。
/// - 完备的用户信息头部（头像+挂件+官方认证标、大会员高亮与徽标、Lv0~Lv6与硬核等级徽标、详细经验进度条、粉丝牌、我关注的人也在关注、签名、UID与空间标签、封禁提示）。
/// - 交互操作：关注/取关/互关状态切换、私信入口、分享与更多菜单。
/// - 关系统计入口：关注数、粉丝数、获赞数（点击直达关系列表）。
/// - 动态板块标签栏（TabBar）：根据公开状态自适应呈现（未公开隐私板块自动隐藏）。
class MemberSpacePage extends StatefulWidget {
  const MemberSpacePage({super.key, required this.mid});

  final int mid;

  @override
  State<MemberSpacePage> createState() => _MemberSpacePageState();
}

class _MemberSpacePageState extends State<MemberSpacePage>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  final List<TabController> _pendingDisposeControllers = [];
  bool _isDisposed = false;

  LoadingState<MemberSpaceData> _spaceState = LoadingState.loading();
  MemberCardInfoData? _cardInfo;
  MemberImages? _extraTopPhoto;
  SpaceNavNumData? _navNum;

  // 投稿视频列表数据与排序
  final List<MemberVideoItem> _videos = [];
  bool _loadingVideos = false;
  bool _videoEnd = false;
  bool _videoFailed = false;
  int _videoPage = 1;
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

  /// 点赞状态记忆（跨瀑布流滚动重建保留）。
  final Map<String, bool> _likedState = {};
  final Map<String, int> _likeCountState = {};
  bool _dynamicEnd = false;
  bool _dynamicFailed = false;
  String? _dynamicOffset;
  _DynFilterType _selectedDynFilter = _DynFilterType.all;

  // 收藏夹列表数据
  final List<FavFolderInfo> _favFolders = [];
  bool _loadingFav = false;
  bool _favFailed = false;
  String? _favError;

  // 追番与追剧列表数据
  final List<SpaceBangumiItem> _bangumiList = [];
  bool _loadingBangumi = false;
  bool _bangumiFailed = false;
  String? _bangumiError;
  int _bangumiType = 1; // 1=追番, 2=追剧
  int _bangumiPage = 1;
  bool _bangumiEnd = false;

  // 点赞视频数据
  final List<MemberVideoItem> _likedVideos = [];
  bool _loadingLiked = false;
  bool _likedFailed = false;
  String? _likedError;

  // 关系状态 (0=未关注, 1=悄关, 2=已关注, 4/6=互关, 128=拉黑, -10=特关)
  int _relationStatus = 0;
  bool _isFollowingUpdating = false;
  StreamSubscription<FollowEvent>? _followSubscription;

  /// 计算当前对外开放可见的 Tab 列表（未公开或私密板块保留 Tab 并展示隐私状态）。
  List<_SpaceTabType> get _availableTabs {
    final isOwner = Accounts.main.isLogin && Accounts.main.mid == widget.mid;
    final tabs = <_SpaceTabType>[_SpaceTabType.video];

    // 合集与系列：本人可见，或者有公开合集数据/合集计数
    if (isOwner || _seasonsSeries.isNotEmpty || (_navNum != null && _navNum!.channel > 0)) {
      tabs.add(_SpaceTabType.seasons);
    }

    // 动态：公开基础板块
    tabs.add(_SpaceTabType.dynamics);

    // 收藏夹：本人可见，或者有收藏夹数据/收藏计数（隐私设置未公开时在 Tab 内展示隐私提示）
    if (isOwner || _favFolders.isNotEmpty || (_navNum != null && _navNum!.favourite > 0)) {
      tabs.add(_SpaceTabType.fav);
    }

    // 追番追剧：本人可见，或者有追番数据/追番计数（隐私设置未公开时在 Tab 内展示隐私提示）
    final bangumiCount = _navNum != null ? (_navNum!.bangumi + _navNum!.cinema) : _bangumiList.length;
    if (isOwner || _bangumiList.isNotEmpty || (_navNum != null && bangumiCount > 0)) {
      tabs.add(_SpaceTabType.bangumi);
    }

    // 点赞视频：本人可见，或者有公开点赞视频/点赞计数
    if (isOwner || _likedVideos.isNotEmpty || (_navNum != null && _navNum!.like > 0)) {
      tabs.add(_SpaceTabType.liked);
    }

    // 详细资料
    tabs.add(_SpaceTabType.about);
    return tabs;
  }

  void _syncTabController() {
    if (_isDisposed || !mounted) return;
    final tabs = _availableTabs;
    if (_tabController.length != tabs.length) {
      final oldController = _tabController;
      final oldIndex = oldController.index;
      _tabController = TabController(
        length: tabs.length,
        vsync: this,
        initialIndex: oldIndex.clamp(0, tabs.length - 1),
      );
      _pendingDisposeControllers.add(oldController);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isDisposed) return;
        for (final c in _pendingDisposeControllers) {
          c.dispose();
        }
        _pendingDisposeControllers.clear();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _availableTabs.length, vsync: this);
    _initFollowSubscription();
    _loadAll();
    // 演示模式/自定义覆盖变更时重建（遮罩与替换值即时生效）。
    Pref.demoModeNotifier.addListener(_onDemoChanged);
    DemoOverrides.revision.addListener(_onDemoChanged);
  }

  void _initFollowSubscription() {
    _followSubscription = EventBus().on<FollowEvent>().listen((event) {
      if (!mounted) return;
      if (event.mid == widget.mid) {
        final isCurrentlyFollowed = _relationStatus == 1 ||
            _relationStatus == 2 ||
            _relationStatus == 4 ||
            _relationStatus == 6 ||
            _relationStatus == -10;
        if (isCurrentlyFollowed != event.isFollowing) {
          setState(() {
            _relationStatus = event.isFollowing ? 2 : 0;
          });
        }
      }
    });
  }

  void _onDemoChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _isDisposed = true;
    Pref.demoModeNotifier.removeListener(_onDemoChanged);
    DemoOverrides.revision.removeListener(_onDemoChanged);
    _followSubscription?.cancel();
    _followSubscription = null;
    for (final c in _pendingDisposeControllers) {
      c.dispose();
    }
    _pendingDisposeControllers.clear();
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadSpace(),
      _loadCardInfo(),
      _loadNavNum(),
      _loadTopPhoto(),
      _loadInitialVideos(),
      _loadInitialSeasons(),
      _loadInitialDynamics(),
      _loadFavFolders(),
      _loadInitialBangumi(),
      _loadLikedVideos(),
    ]);
  }

  Future<void> _loadSpace() async {
    setState(() => _spaceState = LoadingState.loading());
    final res = await MemberHttp.space(mid: widget.mid);
    if (!mounted) return;
    if (res case Success(:final response)) {
      final card = response.card;
      if (card != null) {
        _relationStatus = card.relation ?? 0;
      }
    }
    _syncTabController();
    setState(() => _spaceState = res);
  }

  Future<void> _loadCardInfo() async {
    final res = await MemberHttp.memberCardInfo(mid: widget.mid);
    if (!mounted) return;
    if (res case Success(:final response)) {
      setState(() => _cardInfo = response);
    }
  }

  Future<void> _loadNavNum() async {
    final res = await MemberHttp.spaceNavNum(mid: widget.mid);
    if (!mounted) return;
    if (res case Success(:final response)) {
      _navNum = response;
      _syncTabController();
      setState(() {});
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
    _videoPage = 1;
    _videoEnd = false;
    _videoFailed = false;
    await _loadMoreVideos();
  }

  Future<void> _loadMoreVideos() async {
    if (_loadingVideos || _videoEnd || _videoFailed) return;
    setState(() => _loadingVideos = true);
    final res = await MemberHttp.spaceArchive(
      mid: widget.mid,
      pageNum: _videoPage,
      order: _videoOrder,
    );
    if (!mounted) return;
    _loadingVideos = false;
    switch (res) {
      case Success(:final response):
        _videos.addAll(response.list);
        _videoEnd = response.isEnd ?? response.list.isEmpty;
        _videoPage++;
        _videoFailed = false;
        _syncTabController();
        setState(() {});
      case Error():
        _videoFailed = true;
        _syncTabController();
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

  Future<void> _loadFavFolders() async {
    if (_loadingFav) return;
    setState(() {
      _loadingFav = true;
      _favFailed = false;
      _favError = null;
    });
    final res = await FavHttp.allFavFolders(widget.mid);
    if (!mounted) return;
    _loadingFav = false;
    switch (res) {
      case Success(:final response):
        _favFolders.clear();
        _favFolders.addAll(response.list ?? []);
        _favFailed = false;
        _favError = null;
        _syncTabController();
        setState(() {});
      case Error(:final errMsg):
        _favFailed = true;
        _favError = errMsg;
        _syncTabController();
        setState(() {});
      case Loading():
        break;
    }
  }

  Future<void> _loadInitialBangumi() async {
    _bangumiList.clear();
    _bangumiPage = 1;
    _bangumiEnd = false;
    _bangumiFailed = false;
    _bangumiError = null;
    await _loadMoreBangumi();
  }

  Future<void> _loadMoreBangumi() async {
    if (_loadingBangumi || _bangumiEnd || _bangumiFailed) return;
    setState(() => _loadingBangumi = true);
    final res = await MemberHttp.spaceBangumi(
      mid: widget.mid,
      type: _bangumiType,
      pn: _bangumiPage,
    );
    if (!mounted) return;
    _loadingBangumi = false;
    switch (res) {
      case Success(:final response):
        _bangumiList.addAll(response.list);
        _bangumiEnd = response.isEnd || response.list.isEmpty;
        _bangumiPage++;
        _bangumiFailed = false;
        _bangumiError = null;
        _syncTabController();
        setState(() {});
      case Error(:final errMsg):
        _bangumiFailed = true;
        _bangumiError = errMsg;
        _syncTabController();
        setState(() {});
      case Loading():
        break;
    }
  }

  void _switchBangumiType(int newType) {
    if (_bangumiType == newType) return;
    setState(() {
      _bangumiType = newType;
    });
    _loadInitialBangumi();
  }

  Future<void> _loadLikedVideos() async {
    if (_loadingLiked) return;
    setState(() {
      _loadingLiked = true;
      _likedFailed = false;
      _likedError = null;
    });
    final res = await MemberHttp.likedVideos(mid: widget.mid);
    if (!mounted) return;
    _loadingLiked = false;
    switch (res) {
      case Success(:final response):
        _likedVideos.clear();
        _likedVideos.addAll(response);
        _likedFailed = false;
        _likedError = null;
        _syncTabController();
        setState(() {});
      case Error(:final errMsg):
        _likedFailed = true;
        _likedError = errMsg;
        _syncTabController();
        setState(() {});
      case Loading():
        break;
    }
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
        _syncTabController();
        setState(() {});
      case Error():
        _seasonFailed = true;
        _syncTabController();
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
      showToast(context, '请先登录');
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
        final newFollowing = !isCurrentlyFollowed;
        setState(() {
          _relationStatus = newFollowing ? 2 : 0;
        });
        EventBus().emit(FollowEvent(
          mid: widget.mid,
          isFollowing: newFollowing,
        ));
        showToast(context, isCurrentlyFollowed ? '已取消关注' : '关注成功');
      case Error(:final errMsg):
        showToast(context, errMsg ?? '操作失败');
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
    // 本页自带 SliverAppBar（含返回/分享/更多操作与 330 高折叠头图）与
    // pinned Tab 栏，AppScaffold 不再预留顶部安全行与悬浮返回，避免双顶栏
    //（50px 空白 + 双返回按钮）挤压头图。
    return AppScaffold(
      reserveTopStrip: false,
      showBackButton: false,
      body: switch (_spaceState) {
        Loading() => _buildSpaceContent(null),
        Error(:final errMsg) => _buildError(errMsg, _loadAll),
        Success(:final response) => _buildSpaceContent(response),
      },
    );
  }

  Widget _buildSpaceContent(MemberSpaceData? data) {
    final card = data?.card;
    final images = data?.images;
    final tokens = AppThemeHost.of(context);
    final isOwner = Accounts.main.isLogin && Accounts.main.mid == widget.mid;

    final tabs = _availableTabs;
    _syncTabController();

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
              leading: MiuixIconButton(

                onPressed: () => Navigator.maybePop(context),

                child: AppTooltip(message: '返回', child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.black.withValues(alpha: 0.35),
                    shape: BoxShape.circle,
                  ),
                  child: AppIcon(AppIcons.back(), color: AppColors.white, size: 20),
                )),
              ),
              actions: [
                if (!isOwner)
                  MiuixIconButton(

                    onPressed: () => _copyToClipboard('https://space.bilibili.com/${widget.mid}', '主页链接已复制'),

                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.black.withValues(alpha: 0.35),
                        shape: BoxShape.circle,
                      ),
                      child: AppIcon(AppIcons.share(), color: AppColors.white, size: 20),
                    ),
                  ),
                // 阶段5d-L1：M3 冻结分支已移除
                MiuixPopupMenu(
                    title: '更多选项',
                    entries: [
                      MiuixDropdownEntry(
                        items: [
                          MiuixDropdownItem(
                            text: '复制 UID',
                            onClick: () => _copyToClipboard(
                              widget.mid.toString(),
                              'UID 已复制',
                            ),
                          ),
                          MiuixDropdownItem(
                            text: '复制主页链接',
                            onClick: () => _copyToClipboard(
                              'https://space.bilibili.com/${widget.mid}',
                              '主页链接已复制',
                            ),
                          ),
                          if (!isOwner)
                            MiuixDropdownItem(
                              text: '举报该用户',
                              onClick: () => showToast(context, '已收到举报请求'),
                            ),
                        ],
                      ),
                    ],
                    child: AppTooltip(
                      message: '更多选项',
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.black.withValues(alpha: 0.35),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          AppIcons.more(),
                          color: AppColors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: Style.sm),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: _buildHeaderBackground(context, card, images),
              ),
            ),
            SliverToBoxAdapter(
              // 演示模式：他人空间整块头部用加载态骨架替代（含头像/昵称/签名等）。
              child: _buildUserDetailCard(
                context,
                (Pref.demoMode && !isOwner) ? null : card,
                data?.silence,
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _SliverAppBarDelegate(
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  indicatorSize: TabBarIndicatorSize.label,
                  labelColor: tokens.colors.primary,
                  unselectedLabelColor: tokens.colors.onSurfaceVariant,
                  indicatorColor: tokens.colors.primary,
                  tabs: tabs.map((t) => Tab(text: _tabTitle(t))).toList(),
                ),
                tokens.colors.surface,
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: tabs.map((t) => KeyedSubtree(
            key: ValueKey(t),
            child: _buildTabContent(t, card),
          )).toList(),
        ),
      ),
    );
  }

  String _tabTitle(_SpaceTabType type) {
    switch (type) {
      case _SpaceTabType.video:
        return '投稿 (${_navNum?.video ?? _videos.length})';
      case _SpaceTabType.seasons:
        return '合集 (${_navNum?.channel ?? _seasonsSeries.length})';
      case _SpaceTabType.dynamics:
        return '动态 (${_dynamics.length})';
      case _SpaceTabType.fav:
        return '收藏 (${_navNum?.favourite ?? _favFolders.length})';
      case _SpaceTabType.bangumi:
        final count = _navNum != null ? (_navNum!.bangumi + _navNum!.cinema) : _bangumiList.length;
        return '追番 ($count)';
      case _SpaceTabType.liked:
        return '点赞 (${_likedVideos.length})';
      case _SpaceTabType.about:
        return '详细资料';
    }
  }

  Widget _buildTabContent(_SpaceTabType type, MemberCard? card) {
    final isOwner = Accounts.main.isLogin && Accounts.main.mid == widget.mid;
    final Widget content = switch (type) {
      _SpaceTabType.video => _buildVideosTab(),
      _SpaceTabType.seasons => _buildSeasonsTab(),
      _SpaceTabType.dynamics => _buildDynamicsTab(),
      _SpaceTabType.fav => _buildFavTab(),
      _SpaceTabType.bangumi => _buildBangumiTab(),
      _SpaceTabType.liked => _buildLikedTab(),
      _SpaceTabType.about => _buildAboutTab(card),
    };
    // 实机反馈#4：页签内容各自可下拉刷新（NestedScrollView 内层拖拽不会被
    // 外层指示器接住，故在内层再补一层；外层保留覆盖头图区拖拽）。
    final refreshable =
        AppRefreshIndicator(onRefresh: _loadAll, child: content);
    // 演示模式：除「自己的空间·详细资料」外，页签内容一律以骨架显示。
    if (isOwner && type == _SpaceTabType.about) return refreshable;
    return DemoMask(
      skeleton: _buildSpaceTabSkeleton,
      child: () => refreshable,
    );
  }

  /// 空间页签通用骨架（演示模式占位）。
  Widget _buildSpaceTabSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.all(Style.safeSpace),
      itemCount: 6,
      itemBuilder: (context, index) => const Padding(
        padding: EdgeInsets.only(bottom: Style.md),
        child: Skeleton(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 150, height: 84),
              SizedBox(width: Style.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonLine(width: double.infinity, height: 14),
                    SizedBox(height: 8),
                    SkeletonLine(width: 120, height: 12),
                  ],
                ),
              ),
            ],
          ),
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
    final tokens = AppThemeHost.of(context);
    // 演示模式：横幅图片（云端内容）替换为默认渐变占位。
    if (Pref.demoMode) return _defaultHeaderGradient(tokens);
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
            imageUrl: ImageUtils.thumbnailUrl(topPhoto, type: 'background'),
            fit: BoxFit.cover,
            memCacheWidth: ImageUtils.decodeClamp(
                MediaQuery.sizeOf(context).width, context,
                max: 2048),
            errorBuilder: (_, _, _) => _defaultHeaderGradient(tokens),
          )
        else
          _defaultHeaderGradient(tokens),
        // 阴影遮罩
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.black.withValues(alpha: 0.4),
                AppColors.transparent,
                tokens.colors.background.withValues(alpha: 0.8),
                tokens.colors.background,
              ],
              stops: const [0.0, 0.4, 0.85, 1.0],
            ),
          ),
        ),
      ],
    );
  }

  Widget _defaultHeaderGradient(AppTokens tokens) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            biliPink.withValues(alpha: 0.7),
            biliBlue.withValues(alpha: 0.5),
            tokens.colors.background,
          ],
        ),
      ),
    );
  }

  /// 用户详细信息卡片（头像、名字、会员、等级经验、粉丝牌、认证、签名、关注TA的人等）
  Widget _buildUserDetailCard(BuildContext context, MemberCard? card, int? silence) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    // 演示模式：VIP 类型/等级读取覆盖值（无覆盖回退真实值）。
    final realVip = (card?.vip?.isVip ?? false) ? 1 : 0;
    final isVip = (DemoOverrides.choice('profile.vipType') ?? realVip) > 0;
    final vipColor = cs.primary;
    final level = DemoOverrides.choice('profile.level') ??
        card?.level ??
        _cardInfo?.currentLevel ??
        0;
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
                          color: AppColors.black.withValues(alpha: 0.15),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Pref.demoMode
                        ? (isOwner
                            ? AppIcon(AppIcons.profile(), size: 40)
                            : const SkeletonBox())
                        : (card?.face?.isNotEmpty ?? false)
                            ? CachedNetworkImage(
                                imageUrl: ImageUtils.thumbnailUrl(card!.face,
                                    type: 'avatar'),
                                fit: BoxFit.cover,
                                memCacheWidth:
                                    ImageUtils.decodeClamp(78, context, max: 256),
                                memCacheHeight:
                                    ImageUtils.decodeClamp(78, context, max: 256),
                                placeholder: (_, _) => const SkeletonBox(),
                                errorBuilder: (_, _, _) => AppIcon(AppIcons.profile(), size: 40),
                              )
                            : (card == null
                                ? const SkeletonBox()
                                : AppIcon(AppIcons.profile(), size: 40)),
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
                              ? AppColors.amber600
                              : AppColors.blue600,
                        ),
                      ),
                    ),
                ],
              ),
              const Spacer(),
              // 操作按钮（关注 / 私信）
              if (!isOwner) ...[
                MiuixIconButton(
                  backgroundColor: cs.secondaryContainer,
                  child: AppTooltip(
                    message: '私信',
                    child: AppIcon(
                      AppIcons.mail(),
                      size: 20,
                      color: cs.onSecondaryContainer,
                    ),
                  ),
                  onPressed: () {
                    _copyToClipboard('UID: ${widget.mid}', '用户已选择');
                  },
                ),
                const SizedBox(width: Style.sm),
                MiuixButton(onPressed: _isFollowingUpdating ? null : _toggleFollow, child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isFollowingUpdating)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: AppProgressIndicator(strokeWidth: 2),
                        )
                      else ...[
                        Icon(
                          _relationStatus != 0 ? AppIcons.check() : AppIcons.add(),
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
                  )),
              ],
            ],
          ),
          const SizedBox(height: Style.md),
          // 用户昵称 + 会员标 + 等级标 + 粉丝牌
          if (card != null)
            Wrap(
              spacing: Style.sm,
              runSpacing: Style.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => _copyToClipboard(
                    Pref.demoMode ? kDemoDisplayName : (card.name ?? ''),
                    '昵称已复制',
                  ),
                  child: Text(
                    Pref.demoMode ? kDemoDisplayName : (card.name ?? '未知用户'),
                    style: tokens.text.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isVip ? vipColor : null,
                    ),
                  ),
                ),
                if (isVip)
                  PBadge(
                    text: card.vip?.labelText ?? '大会员',
                    type: PBadgeType.vip,
                  ),
                LevelBadge(level: level, isSenior: isSenior),
                if (medal != null || (isOwner && Pref.demoMode))
                  _DemoMedalEdit(
                    visible: medal != null,
                    medalName: medal?.medalName ?? '勋章',
                    level: medal?.level ?? 1,
                    backgroundColor: medal?.parsedBackgroundColor,
                    nameColor: medal?.parsedTextColor,
                  ),
              ],
            )
          else
            const Row(
              children: [
                SkeletonLine(width: 130, height: 22),
                SizedBox(width: Style.sm),
                SkeletonLine(width: 44, height: 18),
              ],
            ),
          const SizedBox(height: Style.sm),
          // 等级经验进度条
          if (card != null)
            LevelExpBar(
              level: level,
              currentExp: _cardInfo?.currentExp,
              nextExp: _cardInfo?.nextExp,
              currentMin: _cardInfo?.currentMin,
              isSenior: isSenior,
            )
          else
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: SkeletonLine(width: 180, height: 8),
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
                    color: AppColors.amber700,
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
          if (card == null) ...[
            const SizedBox(height: Style.sm),
            const SkeletonLine(width: 220, height: 14),
          ] else if (card.sign?.isNotEmpty ?? false) ...[
            const SizedBox(height: Style.sm),
            SelectableText(
              card.sign!.trim(),
              style: tokens.text.bodyMedium?.copyWith(
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
              if (Pref.demoMode && !isOwner)
                const SkeletonLine(width: 90, height: 12)
              else if (isOwner && Pref.demoMode)
                DemoEditableNumber(
                  overrideKey: 'space.uid',
                  value: widget.mid,
                  title: 'UID',
                  builder: (context, v) => Text(
                    'UID: ${v?.round() ?? widget.mid}',
                    style: TextStyle(fontSize: 12, color: cs.outline),
                  ),
                )
              else
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
          // “我关注的人也在关注”（演示模式：第三方内容隐藏）
          if (!Pref.demoMode &&
              followedUpper != null &&
              followedUpper.items.isNotEmpty) ...[
            const SizedBox(height: Style.sm),
            MiuixPressable(
              feedbackType: MiuixPressFeedbackType.sink,
              sinkAmount: 0.98,
              onPressed: () {
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
                    AppIcon(AppIcons.chevronForward(), size: 16, color: cs.outline),
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
                color: AppColors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(Style.radiusSm),
                border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  AppIcon(AppIcons.block(), size: 16, color: AppColors.red),
                  SizedBox(width: Style.sm),
                  Text('该账号当前处于封禁状态', style: TextStyle(color: AppColors.red, fontSize: 12)),
                ],
              ),
            ),
          ],
          // 统计行（关注 / 粉丝 / 获赞）
          const SizedBox(height: Style.md),
          Row(
            children: [
              _statWithDemoEdit(
                context,
                overrideKey: 'profile.following',
                title: '关注数',
                label: '关注',
                count: card?.following,
                onTap: card != null
                    ? () => showMemberRelationPage(
                          context,
                          type: RelationType.followings,
                          vmid: widget.mid,
                        )
                    : null,
              ),
              const SizedBox(width: Style.xxl),
              _statWithDemoEdit(
                context,
                overrideKey: 'profile.follower',
                title: '粉丝数',
                label: '粉丝',
                count: card?.fans ?? _cardInfo?.follower,
                onTap: card != null
                    ? () => showMemberRelationPage(
                          context,
                          type: RelationType.fans,
                          vmid: widget.mid,
                        )
                    : null,
              ),
              const SizedBox(width: Style.xxl),
              _statWithDemoEdit(
                context,
                overrideKey: 'profile.likes',
                title: '获赞数',
                label: '获赞',
                count: card?.likes?.likeNum ?? _cardInfo?.likeNum,
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
                  border: Border.all(color: AppColors.white, width: 1.5),
                ),
                clipBehavior: Clip.antiAlias,
                child: (items[i].face?.isNotEmpty ?? false)
                    ? CachedNetworkImage(
                        imageUrl: ImageUtils.thumbnailUrl(items[i].face,
                            type: 'avatar'),
                        fit: BoxFit.cover,
                        memCacheWidth:
                            ImageUtils.decodeClamp(22, context, max: 256),
                        memCacheHeight:
                            ImageUtils.decodeClamp(22, context, max: 256),
                        errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.grey),
                      )
                    : const ColoredBox(color: AppColors.grey),
              ),
            ),
        ],
      ),
    );
  }

  /// 演示模式：自己的空间统计项接入即时编辑（他人空间保持原样）。
  Widget _statWithDemoEdit(
    BuildContext context, {
    required String overrideKey,
    required String title,
    required String label,
    required int? count,
    VoidCallback? onTap,
  }) {
    final isOwner = Accounts.main.isLogin && Accounts.main.mid == widget.mid;
    if (!isOwner) {
      return _statItem(context, label: label, count: count, onTap: onTap);
    }
    return DemoEditableNumber(
      overrideKey: overrideKey,
      value: count,
      title: title,
      builder: (context, v) => _statItem(
        context,
        label: label,
        count: v?.toInt(),
        onTap: onTap,
      ),
    );
  }

  Widget _statItem(
    BuildContext context, {
    required String label,
    int? count,
    VoidCallback? onTap,
  }) {
    final tokens = AppThemeHost.of(context);
    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (count != null)
          Text(
            NumUtils.formatNum(count),
            style: tokens.text.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 2),
            child: SkeletonLine(width: 36, height: 16),
          ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: tokens.colors.onSurfaceVariant,
          ),
        ),
      ],
    );

    if (onTap != null) {
      return MiuixPressable(
        feedbackType: MiuixPressFeedbackType.sink,
        sinkAmount: 0.98,
        onPressed: onTap,
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
                  _navNum?.video != null
                      ? '共 ${_navNum!.video} 支视频'
                      : (_videos.isNotEmpty
                          ? '共 ${_videos.length} 支视频'
                          : '共 -- 支视频'),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppThemeHost.of(context).colors.outline,
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
        if (_videos.isEmpty && _loadingVideos)
          SliverPadding(
            padding: const EdgeInsets.all(Style.safeSpace),
            sliver: SliverGrid(
              gridDelegate: gridDelegate,
              delegate: SliverChildBuilderDelegate(
                (context, index) => const VideoCardVSkeleton(),
                childCount: 6,
              ),
            ),
          )
        else if (_videos.isEmpty && !_loadingVideos)
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
                    // 加载更多 - 使用 addPostFrameCallback 避免在 build 中调用 _loadMoreVideos
                    // （同 session_list_section 范式）：_loadMoreVideos 首行即 setState，
                    // 而 SliverChildBuilderDelegate 的 builder 在 layout 阶段被调用，
                    // 直接调用会触发「setState() called during build」断言（Debug 才暴露）。
                    if (!_loadingVideos && !_videoEnd && !_videoFailed) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && !_loadingVideos && !_videoEnd && !_videoFailed) {
                          _loadMoreVideos();
                        }
                      });
                    }
                  }
                  return _buildVideoCard(_videos[index]);
                },
                childCount: _videos.length,
              ),
            ),
          ),
        if (_loadingVideos && _videos.isNotEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: Style.lg),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: AppProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
        if (_videoFailed)
          SliverToBoxAdapter(
            child: Center(
              child: MiuixTextButton('加载失败，点击重试', onPressed: () {
                  setState(() => _videoFailed = false);
                  _loadMoreVideos();
                }),
            ),
          ),
      ],
    );
  }

  Widget _buildVideoCard(MemberVideoItem item) {
    final tokens = AppThemeHost.of(context);
    final shapes = tokens.shapes;
    final radius = shapes.medium;
    final bvid = item.bvid;

    return MiuixCard(
      child: MiuixPressable(
        feedbackType: MiuixPressFeedbackType.sink,
        sinkAmount: 0.98,
        onPressed: bvid == null
            ? null
            : () => Navigator.push(
                  context,
                  AppRoute(
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
                      AppIcon(AppIcons.viewCount(),
                        size: 13,
                        color: tokens.colors.outline.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        NumUtils.formatNum(item.play),
                        style: TextStyle(
                          fontSize: 11,
                          color: tokens.colors.outline.withValues(alpha: 0.8),
                        ),
                      ),
                      if (item.danmaku != null) ...[
                        const SizedBox(width: 6),
                        AppIcon(AppIcons.danmakuCount(),
                          size: 13,
                          color: tokens.colors.outline.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          NumUtils.formatNum(item.danmaku),
                          style: TextStyle(
                            fontSize: 11,
                            color: tokens.colors.outline.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                      if (item.pubdate != null) ...[
                        const Spacer(),
                        Text(
                          DateFormatUtils.dateFormat(item.pubdate!),
                          style: TextStyle(
                            fontSize: 10,
                            color: tokens.colors.outline.withValues(alpha: 0.7),
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
    if (_seasonsSeries.isEmpty && _loadingSeasons) {
      return ListView.builder(
        padding: const EdgeInsets.all(Style.safeSpace),
        itemCount: 4,
        itemBuilder: (_, _) => const Padding(
          padding: EdgeInsets.only(bottom: Style.md),
          child: VideoCardHSkeleton(coverWidth: 120, coverHeight: 75, inCard: true),
        ),
      );
    }
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
        if (_loadingSeasons && _seasonsSeries.isNotEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: Style.lg),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: AppProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
        if (_seasonFailed)
          SliverToBoxAdapter(
            child: Center(
              child: MiuixTextButton('加载失败，点击重试', onPressed: () {
                  setState(() => _seasonFailed = false);
                  _loadMoreSeasons();
                }),
            ),
          ),
      ],
    );
  }

  Widget _buildSeasonSeriesCard(SpaceSsModel model) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final meta = model.meta;
    if (meta == null) return const SizedBox.shrink();

    final isSeason = meta.isSeason;
    final total = meta.total ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: Style.md),
      decoration: ShapeDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Style.radiusMd),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.25)),
        ),
      ),
      child: MiuixPressable(
        feedbackType: MiuixPressFeedbackType.sink,
        sinkAmount: 0.98,
        onPressed: () {
          Navigator.push(
            context,
            AppRoute(
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
                      style: tokens.text.titleSmall?.copyWith(
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
              AppIcon(AppIcons.chevronForward(), size: 20, color: AppColors.grey),
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
        if (filtered.isEmpty && _loadingDynamics)
          SliverPadding(
            padding: const EdgeInsets.all(Style.safeSpace),
            sliver: SliverMasonryGrid.extent(
              maxCrossAxisExtent: 440.0,
              mainAxisSpacing: Style.cardSpace,
              crossAxisSpacing: Style.cardSpace,
              childCount: 4,
              itemBuilder: (context, index) => _buildDynamicCardSkeleton(),
            ),
          )
        else if (filtered.isEmpty && !_loadingDynamics)
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
        if (_loadingDynamics && filtered.isNotEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: Style.lg),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: AppProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
        if (_dynamicFailed)
          SliverToBoxAdapter(
            child: Center(
              child: MiuixTextButton('动态加载失败，点击重试', onPressed: () {
                  setState(() => _dynamicFailed = false);
                  _loadMoreDynamics();
                }),
            ),
          ),
      ],
    );
  }

  Widget _buildDynamicCardSkeleton() {
    return const MiuixCard(
      child: Padding(
        padding: EdgeInsets.all(Style.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SkeletonCircle(radius: 19),
                SizedBox(width: Style.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonLine(width: 80, height: 14),
                    SizedBox(height: 4),
                    SkeletonLine(width: 50, height: 10),
                  ],
                ),
              ],
            ),
            SizedBox(height: Style.md),
            SkeletonLine(width: double.infinity, height: 14),
            SizedBox(height: 6),
            SkeletonLine(width: 200, height: 14),
          ],
        ),
      ),
    );
  }

  /// 用户空间动态卡片（自适应不同动态类型的高度和内部结构）
  Widget _buildSpaceDynamicCard(DynItemModel item) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final author = item.author;

    return ClipPath(clipper: ShapeBorderClipper(shape: MiuixSquircleBorder(cornerRadius: MiuixCardDefaults.cornerRadius)), child: MiuixCard(
      child: MiuixPressable(
        feedbackType: MiuixPressFeedbackType.sink,
        sinkAmount: 0.98,
        onPressed: () {
          Navigator.push(
            context,
            AppRoute(
              builder: (_) => DynamicDetailPage(item: item),
            ),
          );
        },
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
                                style: tokens.text.titleSmall?.copyWith(
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
                    style: tokens.text.bodyMedium,
                  )
                else
                  Text(
                    item.text!,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.text.bodyMedium,
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
              // 底部互动行（转发/评论/点赞，均可交互）
              if (item.stat != null) ...[
                const SizedBox(height: Style.sm),
                const MiuixHorizontalDivider(thickness: 0.5),
                const SizedBox(height: Style.xs),
                DynActionBar(
                  item: item,
                  liked: _likedState[item.id],
                  likeCount: _likeCountState[item.id],
                  onChanged: (liked, count) {
                    _likedState[item.id] = liked;
                    _likeCountState[item.id] = count;
                  },
                  onComment: () {
                    Navigator.push(
                      context,
                      AppRoute(
                        builder: (_) => DynamicDetailPage(
                          item: item,
                          focusComment: true,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    ),
      );
  }

  Widget _buildForwardContent(BuildContext context, DynItemModel orig) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final origAuthor = orig.author;

    return MiuixPressable(
      feedbackType: MiuixPressFeedbackType.sink,
      sinkAmount: 0.98,
      onPressed: () {
        Navigator.push(
          context,
          AppRoute(
            builder: (_) => DynamicDetailPage(item: orig),
          ),
        );
      },
      borderRadius: BorderRadius.circular(Style.radiusMd),
      child: Container(
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
                      AppRoute(builder: (_) => MemberSpacePage(mid: authorMid)),
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
                style: tokens.text.bodyMedium,
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
          AppRoute(builder: (_) => VideoDetailPage(bvid: bvid, cover: archive.cover)),
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
                    colors: [AppColors.transparent, AppColors.black.withValues(alpha: 0.65)],
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
                        color: AppColors.white,
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
                            AppIcon(AppIcons.viewCount(), size: 12, color: AppColors.white70),
                            const SizedBox(width: 2),
                            Text(
                              NumUtils.formatNum(archive.play),
                              style: const TextStyle(fontSize: 11, color: AppColors.white70),
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
    final imageUrls = [
      for (final p in pics)
        if (p.src != null && p.src!.isNotEmpty) p.src!,
    ];

    if (pics.length == 1) {
      final item = pics.first;
      final w = item.width ?? 16;
      final h = item.height ?? 9;
      final aspect = (w > 0 && h > 0) ? (w / h).clamp(0.7, 2.0) : 16 / 9;
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 240),
        child: AspectRatio(
          aspectRatio: aspect,
          child: GestureDetector(
            onTap: () {
              if (imageUrls.isNotEmpty) {
                showImageGallery(
                  context,
                  imageUrls: imageUrls,
                  thumbnailUrls: imageUrls,
                  initialIndex: 0,
                );
              }
            },
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
          children: displayPics.asMap().entries.map((entry) {
            final idx = entry.key;
            final pic = entry.value;
            return GestureDetector(
              onTap: () {
                if (imageUrls.isNotEmpty) {
                  showImageGallery(
                    context,
                    imageUrls: imageUrls,
                    thumbnailUrls: imageUrls,
                    initialIndex: idx,
                  );
                }
              },
              child: SizedBox(
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
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildOpusCard(BuildContext context, DynOpus opus) {
    final tokens = AppThemeHost.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (opus.title?.isNotEmpty ?? false)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              opus.title!,
              style: tokens.text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        if (opus.summaryText?.isNotEmpty ?? false)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              opus.summaryText!,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: tokens.text.bodyMedium,
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
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final cover = article.covers.isNotEmpty ? article.covers.first : null;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Style.radiusMd),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: MiuixPressable(
        feedbackType: MiuixPressFeedbackType.sink,
        sinkAmount: 0.98,
        onPressed: () {
          final id = article.id;
          if (id != null && id > 0) {
            Navigator.push(
              context,
              AppRoute(
                builder: (_) => ArticlePage(
                  id: id.toString(),
                  title: article.title,
                  cover: cover,
                  desc: article.desc,
                ),
              ),
            );
          }
        },
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
                      style: tokens.text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
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

  Widget _buildLiveCard(BuildContext context, DynLiveRcmd live) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Style.radiusMd),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: MiuixPressable(
        feedbackType: MiuixPressFeedbackType.sink,
        sinkAmount: 0.98,
        onPressed: () {
          final roomId = live.roomId;
          if (roomId != null && roomId > 0) {
            Navigator.push(
              context,
              AppRoute(
                builder: (_) => LiveRoomPage(
                  roomId: roomId,
                  title: live.title,
                  uname: live.uname,
                  cover: live.cover,
                ),
              ),
            );
          }
        },
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
                            color: AppColors.redAccent,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            'LIVE',
                            style: TextStyle(color: AppColors.white, fontSize: 9, fontWeight: FontWeight.bold),
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
                      style: tokens.text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
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
      ),
    );
  }

  Widget _buildPgcPreview(BuildContext context, DynPgc pgc) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
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
                  style: tokens.text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
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
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;

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
                  style: tokens.text.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                ),
                if (item.price?.isNotEmpty ?? false)
                  Text(
                    item.price!,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.orange700,
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
              ImageUtils.thumbnailUrl(node.emojiUrl, type: 'emote'),
              width: 20,
              height: 20,
              cacheWidth: ImageUtils.decodeClamp(20, context, max: 128),
              cacheHeight: ImageUtils.decodeClamp(20, context, max: 128),
              errorBuilder: (_, _, _) => Text(text),
            ),
          ),
        ));
      } else if (type.contains('BV') || (node.rid?.startsWith('BV') ?? false)) {
        final bvid = node.rid ?? (text.startsWith('BV') ? text : null);
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: MiuixPressable(
            feedbackType: MiuixPressFeedbackType.sink,
            sinkAmount: 0.98,
            onPressed: () {
              if (bvid != null) {
                Navigator.push(context, AppRoute(builder: (_) => VideoDetailPage(bvid: bvid)));
              }
            },
            child: Text(text, style: TextStyle(color: primaryColor, fontWeight: FontWeight.w500)),
          ),
        ));
      } else if (type.contains('AT') || text.startsWith('@')) {
        final mid = int.tryParse(node.rid ?? '');
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: MiuixPressable(
            feedbackType: MiuixPressFeedbackType.sink,
            sinkAmount: 0.98,
            onPressed: () {
              if (mid != null && mid > 0) {
                Navigator.push(context, AppRoute(builder: (_) => MemberSpacePage(mid: mid)));
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

  /// 收藏夹 Tab
  Widget _buildFavTab() {
    final gridDelegate = Grid.videoCardVDelegate(
      mainAxisExtent: MediaQuery.textScalerOf(context).scale(76),
    );

    if (_loadingFav && _favFolders.isEmpty) {
      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(Style.safeSpace),
            sliver: SliverGrid(
              gridDelegate: gridDelegate,
              delegate: SliverChildBuilderDelegate(
                (context, index) => const VideoCardVSkeleton(),
                childCount: 4,
              ),
            ),
          ),
        ],
      );
    }
    if (_favFailed) {
      return _buildPrivacyNotice(_favError ?? '用户未公开收藏夹或暂无收藏', onRetry: _loadFavFolders);
    }
    if (_favFolders.isEmpty) {
      return const Center(child: Text('暂无公开收藏夹'));
    }

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(Style.safeSpace),
          sliver: SliverGrid(
            gridDelegate: gridDelegate,
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index >= _favFolders.length) return null;
                final item = _favFolders[index];
                return _buildFavFolderCard(item);
              },
              childCount: _favFolders.length,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFavFolderCard(FavFolderInfo item) {
    final tokens = AppThemeHost.of(context);
    final shapes = tokens.shapes;
    final radius = shapes.medium;

    return MiuixCard(
      child: MiuixPressable(
        feedbackType: MiuixPressFeedbackType.sink,
        sinkAmount: 0.98,
        onPressed: () {
          Navigator.push(
            context,
            AppRoute(
              builder: (_) => FavDetailPage(folder: item),
            ),
          );
        },
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
                    src: item.cover,
                    width: double.infinity,
                    height: double.infinity,
                    borderRadius: BorderRadius.vertical(top: radius),
                  ),
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: PBadge(
                      text: '${item.mediaCount} 支内容',
                      type: PBadgeType.duration,
                    ),
                  ),
                  if (!item.isPublic)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppIcon(AppIcons.lock(), size: 10, color: AppColors.white),
                            SizedBox(width: 2),
                            Text('私密', style: TextStyle(color: AppColors.white, fontSize: 10)),
                          ],
                        ),
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
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.intro?.isNotEmpty == true
                        ? item.intro!
                        : '创建者: ${item.upper?.name ?? ""}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: tokens.colors.outline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 追番追剧 Tab
  Widget _buildBangumiTab() {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Style.safeSpace, Style.sm, Style.safeSpace, 0),
            child: Row(
              children: [
                ChoiceChip(
                  label: Text('追番 (${_navNum?.bangumi ?? (_bangumiType == 1 ? _bangumiList.length : '')})'),
                  selected: _bangumiType == 1,
                  onSelected: (val) {
                    if (val) _switchBangumiType(1);
                  },
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: Style.sm),
                ChoiceChip(
                  label: Text('追剧 (${_navNum?.cinema ?? (_bangumiType == 2 ? _bangumiList.length : '')})'),
                  selected: _bangumiType == 2,
                  onSelected: (val) {
                    if (val) _switchBangumiType(2);
                  },
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ),
        if (_loadingBangumi && _bangumiList.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.all(Style.safeSpace),
            sliver: SliverGrid(
              gridDelegate: Grid.videoCardVDelegate(
                mainAxisExtent: MediaQuery.textScalerOf(context).scale(76),
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => const VideoCardVSkeleton(),
                childCount: 6,
              ),
            ),
          )
        else if (_bangumiFailed)
          SliverToBoxAdapter(
            child: _buildPrivacyNotice(
              _bangumiError ?? '用户隐私设置未公开追番追剧',
              onRetry: _loadInitialBangumi,
            ),
          )
        else if (_bangumiList.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 80),
              child: Center(child: Text(_bangumiType == 1 ? '暂无追番' : '暂无追剧')),
            ),
          )
        else ...[
          SliverPadding(
            padding: const EdgeInsets.all(Style.safeSpace),
            sliver: SliverGrid(
              gridDelegate: Grid.videoCardVDelegate(
                mainAxisExtent: MediaQuery.textScalerOf(context).scale(76),
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index >= _bangumiList.length) return null;
                  if (index == _bangumiList.length - 1) {
                    _loadMoreBangumi();
                  }
                  final item = _bangumiList[index];
                  return _buildBangumiCard(item);
                },
                childCount: _bangumiList.length,
              ),
            ),
          ),
          if (_loadingBangumi)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: Style.md),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: AppProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildBangumiCard(SpaceBangumiItem item) {
    final tokens = AppThemeHost.of(context);
    final shapes = tokens.shapes;
    final radius = shapes.medium;

    return MiuixCard(
      child: MiuixPressable(
        feedbackType: MiuixPressFeedbackType.sink,
        sinkAmount: 0.98,
        onPressed: () {
          Navigator.push(
            context,
            AppRoute(
              builder: (_) => BangumiDetailPage(
                seasonId: item.seasonId,
                mediaId: item.mediaId,
              ),
            ),
          );
        },
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
                    src: item.cover,
                    width: double.infinity,
                    height: double.infinity,
                    borderRadius: BorderRadius.vertical(top: radius),
                  ),
                  if (item.badge?.isNotEmpty == true)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: PBadge(
                        text: item.badge!,
                        type: PBadgeType.badge,
                      ),
                    ),
                  if (item.indexShow?.isNotEmpty == true)
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: PBadge(
                        text: item.indexShow!,
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.progress?.isNotEmpty == true
                        ? item.progress!
                        : (item.follow != null ? '${NumUtils.formatNum(item.follow)} 系列追番' : ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: tokens.colors.outline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 已点赞 Tab
  Widget _buildLikedTab() {
    final gridDelegate = Grid.videoCardVDelegate(
      mainAxisExtent: MediaQuery.textScalerOf(context).scale(86),
    );

    if (_loadingLiked && _likedVideos.isEmpty) {
      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(Style.safeSpace),
            sliver: SliverGrid(
              gridDelegate: gridDelegate,
              delegate: SliverChildBuilderDelegate(
                (context, index) => const VideoCardVSkeleton(),
                childCount: 6,
              ),
            ),
          ),
        ],
      );
    }
    if (_likedFailed) {
      return _buildPrivacyNotice(
        _likedError ?? 'UP主已设置点赞视频不公开',
        onRetry: _loadLikedVideos,
      );
    }
    if (_likedVideos.isEmpty) {
      return const Center(child: Text('暂无公开点赞视频'));
    }

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(Style.safeSpace),
          sliver: SliverGrid(
            gridDelegate: gridDelegate,
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index >= _likedVideos.length) return null;
                return _buildVideoCard(_likedVideos[index]);
              },
              childCount: _likedVideos.length,
            ),
          ),
        ),
      ],
    );
  }

  /// 隐私保护或受限占位展示卡片
  Widget _buildPrivacyNotice(String message, {VoidCallback? onRetry}) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Style.xl, vertical: Style.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(Style.lg),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: AppIcon(AppIcons.lockOutline(),
                size: 48,
                color: cs.outline,
              ),
            ),
            const SizedBox(height: Style.md),
            Text(
              message,
              style: tokens.text.titleSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Style.xs),
            Text(
              '因用户隐私设置，该内容仅空间主人可见',
              style: tokens.text.bodySmall?.copyWith(
                color: cs.outline,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: Style.md),
              MiuixButton(onPressed: onRetry, child: Row(mainAxisSize: MainAxisSize.min, children: [AppIcon(AppIcons.refresh(), size: 16), const SizedBox(width: 6), const Text('重试')])),
            ],
          ],
        ),
      ),
    );
  }

  /// 详细资料 Tab
  Widget _buildAboutTab(MemberCard? card) {
    final tokens = AppThemeHost.of(context);
    final isOwner = Accounts.main.isLogin && Accounts.main.mid == widget.mid;
    final level = DemoOverrides.choice('profile.level') ??
        card?.level ??
        _cardInfo?.currentLevel;
    final isSenior = card?.levelInfo?.isSeniorMember ?? false;

    return ListView(
      padding: const EdgeInsets.all(Style.safeSpace),
      children: [
        MiuixCard(
          child: Padding(
            padding: const EdgeInsets.all(Style.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('基本信息', style: tokens.text.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: Style.md),
                _infoRow(
                  'UID',
                  '${widget.mid}',
                  customValue: (isOwner && Pref.demoMode)
                      ? DemoEditableNumber(
                          overrideKey: 'space.uid',
                          value: widget.mid,
                          title: 'UID',
                          builder: (context, v) => SelectableText(
                            '${v?.round() ?? widget.mid}',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        )
                      : null,
                ),
                _infoRow(
                  '昵称',
                  (isOwner && Pref.demoMode) ? kDemoDisplayName : card?.name,
                ),
                _infoRow('等级', level != null ? 'Lv.$level ${isSenior ? '(硬核会员)' : ''}' : null),
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

  Widget _infoRow(String label, String? value, {Widget? customValue}) {
    final tokens = AppThemeHost.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Style.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(color: tokens.colors.onSurfaceVariant, fontSize: 13),
            ),
          ),
          Expanded(
            child: customValue ??
                (value != null
                    ? SelectableText(
                        value,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      )
                    : const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: SkeletonLine(width: 100, height: 12),
                      )),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(String text, String tip) {
    Clipboard.setData(ClipboardData(text: text));
    showToast(context, tip);
  }

  Widget _buildError(String? errMsg, VoidCallback onRetry) {
    final tokens = AppThemeHost.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AppIcon(AppIcons.spaceOffline(), size: 48, color: tokens.colors.onSurfaceVariant),
          const SizedBox(height: Style.lg),
          Text(errMsg ?? '加载失败', style: TextStyle(color: tokens.colors.onSurfaceVariant)),
          const SizedBox(height: Style.xl),
          MiuixButton(onPressed: onRetry, child: const Text('点击重试')),
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
