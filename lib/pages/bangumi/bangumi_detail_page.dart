import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/core/account/login_guard.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/pgc.dart';
import 'package:winwin/models/bangumi/bangumi_detail.dart';
import 'package:winwin/pages/bangumi/bangumi_player_page.dart';
import 'package:winwin/pages/video/detail_page.dart' show kDetailNarrowBreakpoint;
import 'package:winwin/theme/style.dart';
import 'package:winwin/utils/num_utils.dart';

/// 番剧 / 影视详情主页（对标 BiliPai `BangumiDetailScreen` 与 PiliPlus）。
///
/// 支持宽屏（>= 900）双栏分治与窄屏单列自适应响应式布局：
/// - 宽屏左栏（40%）：封面海报（3:4）、评分、播放/追番数据、主播放按钮、追番状态设置、元信息（风格/开播/声优/制作）、折叠简介；
/// - 宽屏右栏（60%）：多季切换选择器、选集控制台（正倒序、50集分页、快速跳转、16:9卡片网格）、衍生内容（花絮/预告/特典）；
/// - 点击选集或“开始播放”直接进入带有独立选集切流与评论的 [BangumiPlayerPage]。
class BangumiDetailPage extends StatefulWidget {
  const BangumiDetailPage({
    super.key,
    this.seasonId,
    this.epId,
    this.mediaId,
    this.detail,
    this.cover,
    this.title,
  });

  final int? seasonId;
  final int? epId;
  final int? mediaId;
  final BangumiDetail? detail;
  final String? cover;
  final String? title;

  @override
  State<BangumiDetailPage> createState() => _BangumiDetailPageState();
}

class _BangumiDetailPageState extends State<BangumiDetailPage> {
  LoadingState<BangumiDetail> _state = LoadingState.loading();
  BangumiDetail? _detail;

  // 选集排序与分页
  late bool _episodesDescending;
  int _selectedEpisodePage = 0;
  static const int _episodesPerPage = 50;

  // 简介展开/收起
  bool _descExpanded = false;

  // 追番状态
  bool _isFollowed = false;
  int _followStatus = 0; // 1=想看, 2=在看, 3=看过

  // 滚动控制器与最后观看剧集自动定位
  final ScrollController _leftScrollController = ScrollController();
  final ScrollController _rightScrollController = ScrollController();
  final ScrollController _narrowScrollController = ScrollController();
  final GlobalKey _lastWatchedKey = GlobalKey();
  bool _hasAutoLocated = false;

  @override
  void dispose() {
    Pref.bangumiEpisodesDescending.removeListener(_onGlobalOrderChanged);
    _leftScrollController.dispose();
    _rightScrollController.dispose();
    _narrowScrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _episodesDescending = Pref.bangumiEpisodesDescending.value;
    Pref.bangumiEpisodesDescending.addListener(_onGlobalOrderChanged);
    if (widget.detail != null) {
      _detail = widget.detail;
      _state = Success(widget.detail!);
      _syncUserStatus(widget.detail!.userStatus);
      _locateProgressEpisode(widget.detail!);
    }
    _loadDetail();
  }

  void _onGlobalOrderChanged() {
    if (!mounted) return;
    final newDesc = Pref.bangumiEpisodesDescending.value;
    if (_episodesDescending == newDesc) return;
    setState(() {
      _episodesDescending = newDesc;
      final detail = _detail;
      if (detail != null) {
        final lastEpId = detail.userStatus?.progressLastEpId;
        if (lastEpId != null && lastEpId > 0) {
          final epIdx = detail.episodes.indexWhere((e) => e.id == lastEpId);
          if (epIdx >= 0) {
            final total = detail.episodes.length;
            _selectedEpisodePage = _episodesDescending
                ? (total - 1 - epIdx).clamp(0, total - 1) ~/ _episodesPerPage
                : epIdx ~/ _episodesPerPage;
          }
        }
      }
    });
  }

  Future<void> _loadDetail({int? seasonId, int? epId, int? mediaId}) async {
    final sid = seasonId ?? widget.seasonId;
    final eid = epId ?? widget.epId;
    final mid = mediaId ?? widget.mediaId;

    if (_detail == null) {
      setState(() => _state = LoadingState.loading());
    }

    final res = await PgcHttp.pgcInfo(
      seasonId: sid,
      epId: eid,
      mediaId: mid,
    );

    if (!mounted) return;
    switch (res) {
      case Success(:final response):
        setState(() {
          _detail = response;
          _state = Success(response);
          _syncUserStatus(response.userStatus);
        });
        _locateProgressEpisode(response);

        // 仅在 userStatus 仍为空且已登录时作为兜底查询，避免冗余网络请求风暴与频繁 setState 颠簸
        if (response.userStatus == null && response.seasonId > 0 && Accounts.main.isLogin) {
          _fetchLiveUserStatus(response.seasonId);
        }
      case Error():
        if (_detail == null) {
          setState(() => _state = res);
        }
      case Loading():
        break;
    }
  }

  void _syncUserStatus(BangumiUserStatus? us) {
    if (us != null) {
      _isFollowed = us.isFollowed;
      _followStatus = us.followStatus;
    }
  }

  /// 依据云端观看记录自动计算对应集数所在的分页区间并触发高亮与滚动定位
  void _locateProgressEpisode(BangumiDetail detail) {
    if (_hasAutoLocated) return;
    final lastEpId = detail.userStatus?.progressLastEpId;
    if (lastEpId == null || lastEpId <= 0 || detail.episodes.isEmpty) return;

    final epIdx = detail.episodes.indexWhere((e) => e.id == lastEpId);
    if (epIdx < 0) return;

    final total = detail.episodes.length;
    final targetPage = _episodesDescending
        ? (total - 1 - epIdx).clamp(0, total - 1) ~/ _episodesPerPage
        : epIdx ~/ _episodesPerPage;

    _hasAutoLocated = true;
    if (_selectedEpisodePage != targetPage) {
      setState(() {
        _selectedEpisodePage = targetPage;
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToTargetEpisode();
    });
  }

  /// 自动平滑滚动视口定位到最后观看的剧集卡片
  void _scrollToTargetEpisode() {
    if (!mounted) return;
    final targetContext = _lastWatchedKey.currentContext;
    if (targetContext != null) {
      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
        alignment: 0.25,
      );
    }
  }

  /// 实时向 B 站查询当前登录账号对该番剧的追番与观看记录（解决 CDN 缓存缺失 user_status 问题）
  Future<void> _fetchLiveUserStatus(int seasonId) async {
    if (!Accounts.main.isLogin || seasonId <= 0) return;
    final res = await PgcHttp.seasonStatus(seasonId);
    if (!mounted) return;
    if (res case Success(:final response)) {
      final follow = response['follow'] == 1 ||
          (response['follow_status'] is num && (response['follow_status'] as num) > 0);
      final followStatus = response['follow_status'] as int? ?? (follow ? 2 : 0);
      final progress = response['progress'] as Map?;
      final lastEpId = progress?['last_ep_id'] as int?;
      final lastTime = progress?['last_time'] as int?;

      setState(() {
        _isFollowed = follow;
        _followStatus = followStatus;
        if (_detail != null) {
          _detail = _detail!.copyWith(
            userStatus: BangumiUserStatus(
              follow: follow ? 1 : 0,
              followStatus: followStatus,
              pay: response['pay'] as int? ?? _detail!.userStatus?.pay ?? 0,
              progressLastEpId: lastEpId ?? _detail!.userStatus?.progressLastEpId,
              progressLastTime: lastTime ?? _detail!.userStatus?.progressLastTime,
            ),
          );
        }
      });
      if (_detail != null) {
        _locateProgressEpisode(_detail!);
      }
    }
  }

  /// 找到起始播放的分集（优先历史进度，无则从第1集开始）
  BangumiEpisode? _resolveStartEpisode(BangumiDetail detail) {
    if (detail.episodes.isEmpty) return null;
    final lastEpId = detail.userStatus?.progressLastEpId;
    if (lastEpId != null && lastEpId > 0) {
      final match = detail.episodes.cast<BangumiEpisode?>().firstWhere(
            (e) => e?.id == lastEpId,
            orElse: () => null,
          );
      if (match != null) return match;
    }
    return detail.episodes.first;
  }

  /// 进入播放页
  void _openPlayer(BangumiDetail detail, BangumiEpisode episode) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BangumiPlayerPage(
          detail: detail,
          initialEpisode: episode,
          allEpisodes: detail.episodes,
        ),
      ),
    );
  }

  // ─────────────────────────── 追番交互 ───────────────────────────

  Future<void> _followBangumi() async {
    if (!await LoginGuard.requireLogin(context)) return;
    final detail = _detail;
    if (detail == null) return;

    final res = await PgcHttp.followBangumi(seasonId: detail.seasonId);
    if (!mounted) return;
    if (res case Success()) {
      setState(() {
        _isFollowed = true;
        _followStatus = 2; // 默认“在看”
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('已开始追番')),
      );
    } else if (res case Error(:final errMsg)) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(errMsg ?? '追番失败')),
      );
    }
  }

  Future<void> _unfollowBangumi() async {
    if (!await LoginGuard.requireLogin(context)) return;
    final detail = _detail;
    if (detail == null) return;

    final res = await PgcHttp.unfollowBangumi(seasonId: detail.seasonId);
    if (!mounted) return;
    if (res case Success()) {
      setState(() {
        _isFollowed = false;
        _followStatus = 0;
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('已取消追番')),
      );
    } else if (res case Error(:final errMsg)) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(errMsg ?? '取消追番失败')),
      );
    }
  }

  Future<void> _updateFollowStatus(int status) async {
    if (!await LoginGuard.requireLogin(context)) return;
    final detail = _detail;
    if (detail == null) return;

    final res = await PgcHttp.updateFollowStatus(
      seasonId: detail.seasonId,
      status: status,
    );
    if (!mounted) return;
    if (res case Success()) {
      final label = switch (status) {
        1 => '想看',
        2 => '在看',
        3 => '看过',
        _ => '已更新',
      };
      setState(() {
        _isFollowed = true;
        _followStatus = status;
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('已更新为“$label”')),
      );
    } else if (res case Error(:final errMsg)) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(errMsg ?? '更新追番状态失败')),
      );
    }
  }

  void _showFollowStatusDialog(BangumiDetail detail) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('追番状态设置'),
        children: [
          _buildDialogStatusOption(ctx, detail, 1, '想看'),
          _buildDialogStatusOption(ctx, detail, 2, '在看'),
          _buildDialogStatusOption(ctx, detail, 3, '看过'),
          const Divider(),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              _unfollowBangumi();
            },
            child: const Text('取消追番', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogStatusOption(
    BuildContext ctx,
    BangumiDetail detail,
    int status,
    String label,
  ) {
    final selected = _isFollowed && _followStatus == status;
    return SimpleDialogOption(
      onPressed: () {
        Navigator.pop(ctx);
        _updateFollowStatus(status);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          if (selected) const Icon(Icons.check, size: 18, color: Colors.blue),
        ],
      ),
    );
  }

  // ─────────────────────────── 精准跳转对话框 ───────────────────────────

  void _showJumpDialog(List<BangumiEpisode> episodes) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('跳转到集数'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '输入集数 (1 - ${episodes.length})',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final val = int.tryParse(ctrl.text.trim());
              if (val != null && val >= 1) {
                BangumiEpisode? targetEp = episodes.cast<BangumiEpisode?>().firstWhere(
                      (e) => e?.title.trim() == val.toString(),
                      orElse: () => null,
                    );
                if (targetEp == null && val <= episodes.length) {
                  targetEp = episodes[val - 1];
                }

                if (targetEp != null) {
                  Navigator.pop(ctx);
                  final epIdx = episodes.indexOf(targetEp);
                  final total = episodes.length;
                  final targetPage = _episodesDescending
                      ? (total - 1 - epIdx).clamp(0, total - 1) ~/ _episodesPerPage
                      : epIdx ~/ _episodesPerPage;
                  setState(() {
                    _selectedEpisodePage = targetPage;
                  });
                  if (_detail != null) {
                    _openPlayer(_detail!, targetEp);
                  }
                  return;
                }
              }
              ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
                const SnackBar(content: Text('未找到对应集数')),
              );
            },
            child: const Text('跳转播放'),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── UI 构建 ───────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _detail?.title ?? widget.title ?? '番剧详情',
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: () => _loadDetail(),
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: '分享',
            onPressed: () {
              final sid = _detail?.seasonId ?? widget.seasonId;
              if (sid != null && sid > 0) {
                Clipboard.setData(
                  ClipboardData(text: 'https://www.bilibili.com/bangumi/play/ss$sid'),
                );
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  const SnackBar(content: Text('番剧链接已复制到剪贴板')),
                );
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: switch (_state) {
        Loading() => _buildSkeleton(cs),
        Error(:final errMsg) => _buildError(errMsg),
        Success(:final response) => LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= kDetailNarrowBreakpoint;
              return isWide
                  ? _buildWideLayout(response, cs)
                  : _buildNarrowLayout(response, cs);
            },
          ),
      },
    );
  }

  /// 骨架屏
  Widget _buildSkeleton(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(Style.safeSpace),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 160,
            height: 220,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(Style.radiusMd),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 260,
                  height: 24,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: 140,
                  height: 16,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: 200,
                  height: 16,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 错误提示视图
  Widget _buildError(String? msg) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(msg ?? '加载番剧详情失败'),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () => _loadDetail(),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── 宽屏双栏布局 ───────────────────────────

  Widget _buildWideLayout(BangumiDetail detail, ColorScheme cs) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左栏：海报、数据、行动按钮、元信息、简介（40%）
        Expanded(
          flex: 4,
          child: Scrollbar(
            controller: _leftScrollController,
            child: SingleChildScrollView(
              controller: _leftScrollController,
              padding: const EdgeInsets.all(Style.safeSpace),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeaderInfo(detail, cs),
                  const SizedBox(height: 16),
                  _buildActionButtons(detail, cs),
                  const SizedBox(height: 18),
                  _buildMetaSection(detail, cs),
                  const SizedBox(height: 18),
                  _buildEvaluateSection(detail, cs),
                ],
              ),
            ),
          ),
        ),
        // 分割线
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: cs.outlineVariant.withValues(alpha: 0.3),
        ),
        // 右栏：多季切换、选集网格、花絮特典（60%）- 采用 CustomScrollView 虚拟化高性能渲染
        Expanded(
          flex: 6,
          child: Scrollbar(
            controller: _rightScrollController,
            child: CustomScrollView(
              controller: _rightScrollController,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(Style.safeSpace),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (detail.seasons.length > 1) ...[
                          _buildSeasonSelector(detail, cs),
                          const SizedBox(height: 18),
                        ],
                        _buildEpisodeControlHeader(detail, cs),
                      ],
                    ),
                  ),
                ),
                ..._buildEpisodeGridSlivers(detail, cs),
                if (detail.sections.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      Style.safeSpace,
                      12,
                      Style.safeSpace,
                      Style.safeSpace,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _buildExtraSections(detail, cs),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────── 窄屏单列布局 ───────────────────────────

  Widget _buildNarrowLayout(BangumiDetail detail, ColorScheme cs) {
    return Scrollbar(
      controller: _narrowScrollController,
      child: CustomScrollView(
        controller: _narrowScrollController,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(Style.safeSpace),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeaderInfo(detail, cs),
                  const SizedBox(height: 16),
                  _buildActionButtons(detail, cs),
                  const SizedBox(height: 16),
                  if (detail.seasons.length > 1) ...[
                    _buildSeasonSelector(detail, cs),
                    const SizedBox(height: 16),
                  ],
                  _buildEpisodeControlHeader(detail, cs),
                ],
              ),
            ),
          ),
          ..._buildEpisodeGridSlivers(detail, cs),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              Style.safeSpace,
              12,
              Style.safeSpace,
              Style.safeSpace,
            ),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMetaSection(detail, cs),
                  const SizedBox(height: 18),
                  _buildEvaluateSection(detail, cs),
                  if (detail.sections.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _buildExtraSections(detail, cs),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── 左栏组件 ───────────────────────────

  /// 海报、标题、评分、统计
  Widget _buildHeaderInfo(BangumiDetail detail, ColorScheme cs) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 3:4 海报封面
        ClipRRect(
          borderRadius: BorderRadius.circular(Style.radiusMd),
          child: SizedBox(
            width: 130,
            height: 173,
            child: Stack(
              fit: StackFit.expand,
              children: [
                NetworkImgLayer(
                  src: detail.cover ?? widget.cover,
                  width: 130,
                  height: 173,
                ),
                if (detail.newEp?.desc.isNotEmpty == true)
                  Positioned(
                    left: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        detail.newEp!.desc,
                        style: const TextStyle(fontSize: 10, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        // 标题与评分
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                detail.title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
              ),
              if (detail.subtitle?.isNotEmpty == true ||
                  detail.seasonTitle?.isNotEmpty == true) ...[
                const SizedBox(height: 4),
                Text(
                  detail.seasonTitle ?? detail.subtitle ?? '',
                  style: TextStyle(fontSize: 12, color: cs.outline),
                ),
              ],
              const SizedBox(height: 8),
              // 评分行
              if (detail.rating != null && detail.rating!.score > 0)
                Row(
                  children: [
                    const Icon(Icons.star_rounded, color: Colors.amber, size: 20),
                    const SizedBox(width: 4),
                    Text(
                      detail.rating!.score.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '(${NumUtils.formatNum(detail.rating!.count)}人评分)',
                      style: TextStyle(fontSize: 11, color: cs.outline),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              // 播放/追番数据
              if (detail.stat != null) ...[
                Text(
                  '${NumUtils.formatNum(detail.stat!.views)} 播放  ·  ${NumUtils.formatNum(detail.stat!.favorites)} 追番',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                Text(
                  '${NumUtils.formatNum(detail.stat!.danmakus)} 弹幕  ·  ${NumUtils.formatNum(detail.stat!.coins)} 投币',
                  style: TextStyle(fontSize: 11, color: cs.outline),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 操作按钮组（开始播放、追番、分享）
  Widget _buildActionButtons(BangumiDetail detail, ColorScheme cs) {
    final startEp = _resolveStartEpisode(detail);
    final hasProgress = detail.userStatus?.progressLastEpId != null;

    final playLabel = hasProgress ? '继续观看' : '开始播放';

    return Row(
      children: [
        // 主行动按钮：播放
        Expanded(
          flex: 3,
          child: FilledButton.icon(
            onPressed: startEp != null ? () => _openPlayer(detail, startEp) : null,
            icon: const Icon(Icons.play_arrow_rounded, size: 22),
            label: Text(
              playLabel,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Style.radiusSm),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // 追番按钮
        Expanded(
          flex: 2,
          child: _FollowButton(
            isFollowed: _isFollowed,
            followStatus: _followStatus,
            onFollow: _followBangumi,
            onUnfollow: _unfollowBangumi,
            onShowStatusMenu: () {
              if (_detail != null) _showFollowStatusDialog(_detail!);
            },
          ),
        ),
      ],
    );
  }

  /// 元信息栏（风格标签、开播、声优、制作）
  Widget _buildMetaSection(BangumiDetail detail, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 风格标签
        if (detail.styles.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: detail.styles.map((st) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  st,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              );
            }).toList(),
          ),
        const SizedBox(height: 12),
        // 开播时间与地区
        if (detail.publish?.releaseDateShow?.isNotEmpty == true ||
            detail.areas.isNotEmpty) ...[
          _buildMetaRow(
            '开播',
            [
              if (detail.publish?.releaseDateShow != null)
                detail.publish!.releaseDateShow!,
              if (detail.areas.isNotEmpty)
                detail.areas.map((a) => a.name).join(' / '),
            ].join('  ·  '),
            cs,
          ),
          const SizedBox(height: 6),
        ],
        // 声优
        if (detail.actors.isNotEmpty) ...[
          _buildMetaRow('声优', detail.actors, cs),
          const SizedBox(height: 6),
        ],
        // 制作
        if (detail.staff.isNotEmpty) ...[
          _buildMetaRow('制作', detail.staff, cs),
        ],
      ],
    );
  }

  Widget _buildMetaRow(String label, String value, ColorScheme cs) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 42,
          child: Text(
            label,
            style: TextStyle(fontSize: 11.5, color: cs.outline),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: TextStyle(
              fontSize: 11.5,
              color: cs.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  /// 简介（支持折叠展开）
  Widget _buildEvaluateSection(BangumiDetail detail, ColorScheme cs) {
    if (detail.evaluate.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '简介',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        SelectableText(
          detail.evaluate,
          maxLines: _descExpanded ? null : 4,
          style: TextStyle(
            fontSize: 12.5,
            color: cs.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        if (detail.evaluate.length > 80)
          InkWell(
            onTap: () => setState(() => _descExpanded = !_descExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                _descExpanded ? '收起简介' : '展开全部简介',
                style: TextStyle(
                  fontSize: 11.5,
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ─────────────────────────── 右栏组件 ───────────────────────────

  /// 关联季度切换选择器
  Widget _buildSeasonSelector(BangumiDetail detail, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '相关季度',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: detail.seasons.map((s) {
              final isCurrent = s.seasonId == detail.seasonId;
              final label = s.seasonTitle.isNotEmpty ? s.seasonTitle : s.title;

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(label),
                  selected: isCurrent,
                  onSelected: (selected) {
                    if (!isCurrent) {
                      _loadDetail(seasonId: s.seasonId);
                    }
                  },
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  /// 选集控制栏（选集标题、正倒序、快速跳转、分页ChoiceChip选择器）
  Widget _buildEpisodeControlHeader(BangumiDetail detail, ColorScheme cs) {
    final all = detail.episodes;
    final totalCount = all.length;
    final pageCount = (totalCount / _episodesPerPage).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 头部控制栏
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '选集 ($totalCount话)',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                // 正倒序切换
                TextButton.icon(
                  onPressed: () {
                    Pref.setBangumiEpisodesDescending(!_episodesDescending);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _scrollToTargetEpisode();
                    });
                  },
                  icon: Icon(
                    _episodesDescending ? Icons.arrow_downward : Icons.arrow_upward,
                    size: 15,
                  ),
                  label: Text(_episodesDescending ? '倒序' : '正序'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 4),
                // 精准跳转
                TextButton.icon(
                  onPressed: () => _showJumpDialog(all),
                  icon: const Icon(Icons.near_me_outlined, size: 15),
                  label: const Text('跳转'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
        // 50集翻页选择器（正序 1-50, 51-100...；倒序 120-71, 70-21, 20-1...）
        if (pageCount > 1) ...[
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(pageCount, (p) {
                final isSelected = p == _selectedEpisodePage;
                final String chipLabel;
                if (!_episodesDescending) {
                  final pStart = p * _episodesPerPage + 1;
                  final pEnd = ((p + 1) * _episodesPerPage).clamp(1, totalCount);
                  chipLabel = '$pStart-$pEnd';
                } else {
                  final high = totalCount - p * _episodesPerPage;
                  final low = (totalCount - (p + 1) * _episodesPerPage + 1)
                      .clamp(1, totalCount);
                  chipLabel = '$high-$low';
                }
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(chipLabel),
                    selected: isSelected,
                    onSelected: (val) {
                      if (val) {
                        setState(() => _selectedEpisodePage = p);
                      }
                    },
                  ),
                );
              }),
            ),
          ),
        ],
      ],
    );
  }

  /// 虚拟化剧集网格 Sliver 构建器（仅在视口内的卡片才实例化与解码图片，杜绝主线程卡死）
  List<Widget> _buildEpisodeGridSlivers(BangumiDetail detail, ColorScheme cs) {
    final all = detail.episodes;
    if (all.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('暂无剧集数据', style: TextStyle(color: cs.outline)),
            ),
          ),
        ),
      ];
    }

    final totalCount = all.length;
    final pageCount = (totalCount / _episodesPerPage).ceil();

    if (_selectedEpisodePage >= pageCount) {
      _selectedEpisodePage = 0;
    }

    // 根据正倒序计算当前分页的剧集列表
    final List<BangumiEpisode> displayed;
    if (!_episodesDescending) {
      final startIdx = _selectedEpisodePage * _episodesPerPage;
      final endIdx = (startIdx + _episodesPerPage).clamp(0, totalCount);
      displayed = all.sublist(startIdx, endIdx);
    } else {
      final high = totalCount - _selectedEpisodePage * _episodesPerPage;
      final low = (totalCount - (_selectedEpisodePage + 1) * _episodesPerPage + 1)
          .clamp(1, totalCount);
      displayed = all.sublist(low - 1, high).reversed.toList();
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: Style.safeSpace),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.18,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final ep = displayed[index];
              return _buildEpisodeCard(detail, ep, cs);
            },
            childCount: displayed.length,
          ),
        ),
      ),
    ];
  }

  /// 单个选集卡片（16:9，封面、集数、标题、时长、气泡角标严格对齐更改前剧集标题字体大小 11.5）
  Widget _buildEpisodeCard(
    BangumiDetail detail,
    BangumiEpisode ep,
    ColorScheme cs, {
    double? customWidth,
  }) {
    final isLastWatched = detail.userStatus?.progressLastEpId == ep.id;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = customWidth ?? constraints.maxWidth;
        final height = width * 9 / 16;

        // 更改前剧集标题基准字号为 11.5；胶囊、角标、气泡字体大小严格对齐该字号，不缩小
        final titleFontSize = (width * 0.075).clamp(11.5, 12.5);
        final badgeFontSize = titleFontSize; // 严格对齐剧集标题字体大小（11.5），绝不缩小
        final horizontalPadding = (titleFontSize * 0.45).clamp(5.0, 7.0);
        final verticalPadding = (titleFontSize * 0.18).clamp(2.0, 3.5);
        final badgeRadius = (titleFontSize * 0.32).clamp(3.5, 5.0);
        final badgeOffset = 4.0;

        return InkWell(
          key: isLastWatched ? _lastWatchedKey : null,
          borderRadius: BorderRadius.circular(Style.radiusSm),
          onTap: () => _openPlayer(detail, ep),
          child: Container(
            width: customWidth,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(Style.radiusSm),
              border: isLastWatched
                  ? Border.all(color: cs.primary, width: 1.5)
                  : Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 16:9 封面区
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      NetworkImgLayer(
                        src: ep.cover ?? detail.cover,
                        width: width,
                        height: height,
                      ),
                      // 底部渐变黑底
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: 24,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black87],
                            ),
                          ),
                        ),
                      ),
                      // 时长气泡（右下角，字体大小对齐标题字号 11.5，带半透明背景气泡）
                      if (ep.duration != null && ep.duration! > 0)
                        Positioned(
                          right: badgeOffset,
                          bottom: badgeOffset,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: horizontalPadding * 0.75,
                              vertical: verticalPadding * 0.7,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(badgeRadius * 0.75),
                            ),
                            child: Text(
                              ep.formattedDuration,
                              style: TextStyle(
                                fontSize: badgeFontSize,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                                height: 1.1,
                              ),
                            ),
                          ),
                        ),
                      // 状态角标（会员、预告、限免，右上角，字体大小对齐标题字号 11.5）
                      if (ep.badge?.isNotEmpty == true)
                        Positioned(
                          right: badgeOffset,
                          top: badgeOffset,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: horizontalPadding,
                              vertical: verticalPadding,
                            ),
                            decoration: BoxDecoration(
                              color: ep.badge!.contains('会员')
                                  ? Colors.orange.shade800
                                  : (ep.badge == '预告'
                                      ? Colors.black.withValues(alpha: 0.65)
                                      : Colors.pink.shade600),
                              borderRadius: BorderRadius.circular(badgeRadius),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 3,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Text(
                              ep.badge!,
                              style: TextStyle(
                                fontSize: badgeFontSize,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                height: 1.1,
                              ),
                            ),
                          ),
                        ),
                      // 上次观看标记（左上角，字体大小对齐标题字号 11.5）
                      if (isLastWatched)
                        Positioned(
                          left: badgeOffset,
                          top: badgeOffset,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: horizontalPadding,
                              vertical: verticalPadding,
                            ),
                            decoration: BoxDecoration(
                              color: cs.primary,
                              borderRadius: BorderRadius.circular(badgeRadius),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  blurRadius: 3,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.history_rounded,
                                  size: badgeFontSize * 1.15,
                                  color: Colors.white,
                                ),
                                SizedBox(width: titleFontSize * 0.2),
                                Text(
                                  '上次看到',
                                  style: TextStyle(
                                    fontSize: badgeFontSize,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    height: 1.1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // 标题文本区
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  child: Text(
                    ep.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: titleFontSize,
                      fontWeight: isLastWatched ? FontWeight.bold : FontWeight.normal,
                      color: isLastWatched ? cs.primary : cs.onSurface,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 衍生内容分区（花絮、PV、预告、特典等，横向虚拟化加载，共享全局正倒序状态）
  Widget _buildExtraSections(BangumiDetail detail, ColorScheme cs) {
    final visibleSections = detail.sections;

    if (visibleSections.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: visibleSections.map((sec) {
        if (sec.episodes.isEmpty) return const SizedBox.shrink();
        final displayedEpisodes = _episodesDescending
            ? sec.episodes.reversed.toList()
            : sec.episodes;

        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${sec.title} (${sec.episodes.length})',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _episodesDescending ? '倒序' : '正序',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: cs.outline,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 155,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: displayedEpisodes.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final ep = displayedEpisodes[index];
                    return SizedBox(
                      width: 150,
                      child: _buildEpisodeCard(detail, ep, cs, customWidth: 150),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// 多状态追番按钮：
/// - 未追番状态：默认显示“追番”，鼠标悬浮显示“开始追番”，点击触发追番。
/// - 已追番状态：默认显示“正在追番”，鼠标悬浮显示“取消追番”，点击取消追番。
/// - 支持右键/长按调出状态切换面板（想看/在看/看过）。
class _FollowButton extends StatefulWidget {
  final bool isFollowed;
  final int followStatus;
  final VoidCallback onFollow;
  final VoidCallback onUnfollow;
  final VoidCallback onShowStatusMenu;

  const _FollowButton({
    required this.isFollowed,
    required this.followStatus,
    required this.onFollow,
    required this.onUnfollow,
    required this.onShowStatusMenu,
  });

  @override
  State<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<_FollowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // 动态状态判定
    final String label;
    final IconData icon;
    final Color? color;

    if (!widget.isFollowed) {
      label = _isHovered ? '开始追番' : '追番';
      icon = _isHovered ? Icons.favorite : Icons.favorite_border;
      color = _isHovered ? cs.primary : null;
    } else {
      if (_isHovered) {
        label = '取消追番';
        icon = Icons.heart_broken_outlined;
        color = Colors.red;
      } else {
        label = '正在追番';
        icon = Icons.favorite;
        color = Colors.pink;
      }
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Tooltip(
        message: widget.isFollowed ? '点击取消追番，右键/长按更改追番状态' : '点击追番',
        child: GestureDetector(
          onSecondaryTap: widget.isFollowed ? widget.onShowStatusMenu : null,
          child: OutlinedButton.icon(
            onPressed: () {
              if (widget.isFollowed) {
                widget.onUnfollow();
              } else {
                widget.onFollow();
              }
            },
            onLongPress: widget.isFollowed ? widget.onShowStatusMenu : null,
            icon: Icon(icon, size: 18, color: color),
            label: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: color,
                fontWeight: widget.isFollowed ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: color != null
                  ? BorderSide(color: color.withValues(alpha: 0.6))
                  : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Style.radiusSm),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
