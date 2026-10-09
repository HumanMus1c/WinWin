import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter_miuix/miuix.dart' show MiuixPressable;
import 'package:material_ui/material_ui.dart';

import 'package:winwin/theme/app_colors.dart';
import 'package:winwin/common/widgets/demo_mask.dart';
import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/common/widgets/p_badge.dart';
import 'package:winwin/common/widgets/refresh_indicator.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/member.dart';
import 'package:winwin/pages/video/detail_page.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/utils/date_utils.dart';
import 'package:winwin/utils/duration_utils.dart';
import 'package:winwin/utils/image_utils.dart';
import 'package:winwin/utils/num_utils.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/core/shell/app_routes.dart';

/// 用户合集/系列视频列表详情页面。
class SeasonSeriesDetailPage extends StatefulWidget {
  const SeasonSeriesDetailPage({
    super.key,
    required this.mid,
    this.seasonId,
    this.seriesId,
    required this.title,
    this.cover,
    this.description,
    this.total,
  });

  final int mid;
  final int? seasonId;
  final int? seriesId;
  final String title;
  final String? cover;
  final String? description;
  final int? total;

  bool get isSeason => seasonId != null && seasonId! > 0;

  @override
  State<SeasonSeriesDetailPage> createState() => _SeasonSeriesDetailPageState();
}

class _SeasonSeriesDetailPageState extends State<SeasonSeriesDetailPage> {
  final List<MemberVideoItem> _videos = [];
  bool _loading = false;
  bool _isEnd = false;
  bool _failed = false;
  int _pageNum = 1;

  @override
  void initState() {
    super.initState();
    _loadVideos(refresh: true);
  }

  Future<void> _loadVideos({bool refresh = false}) async {
    if (_loading) return;
    if (refresh) {
      _pageNum = 1;
      _isEnd = false;
      _failed = false;
    }
    if (!refresh && _isEnd) return;

    setState(() => _loading = true);

    final LoadingState<MemberArchiveData> res;
    if (widget.isSeason) {
      res = await MemberHttp.seasonArchives(
        mid: widget.mid,
        seasonId: widget.seasonId!,
        pageNum: _pageNum,
      );
    } else if (widget.seriesId != null) {
      res = await MemberHttp.seriesArchives(
        mid: widget.mid,
        seriesId: widget.seriesId!,
        pn: _pageNum,
      );
    } else {
      res = const Error('缺少合集 ID');
    }

    if (!mounted) return;
    setState(() => _loading = false);

    switch (res) {
      case Success(:final response):
        if (refresh) _videos.clear();
        _videos.addAll(response.list);
        _isEnd = response.isEnd ?? false;
        _pageNum++;
        setState(() {});
      case Error():
        setState(() => _failed = true);
      case Loading():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          Pref.demoMode ? (widget.isSeason ? '合集' : '系列') : widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      body: Pref.demoMode
          ? const DemoListSkeleton()
          : AppRefreshIndicator(
        onRefresh: () => _loadVideos(refresh: true),
        child: CustomScrollView(
          slivers: [
            // 头部合集介绍卡片
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(Style.safeSpace),
                child: Container(
                  padding: const EdgeInsets.all(Style.md),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(Style.radiusMd),
                    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.cover?.isNotEmpty ?? false) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(Style.radiusSm),
                          child: CachedNetworkImage(
                            imageUrl: ImageUtils.thumbnailUrl(widget.cover,
                                width: 110, height: 70),
                            width: 110,
                            height: 70,
                            fit: BoxFit.cover,
                            memCacheWidth:
                                ImageUtils.decodeClamp(110, context, max: 1080),
                            memCacheHeight:
                                ImageUtils.decodeClamp(70, context, max: 1080),
                            errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.grey),
                          ),
                        ),
                        const SizedBox(width: Style.md),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                PBadge(
                                  text: widget.isSeason ? '合集' : '系列',
                                  type: PBadgeType.badge,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    widget.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: tokens.text.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '共 ${widget.total ?? _videos.length} 支视频',
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                            ),
                            if (widget.description?.isNotEmpty ?? false) ...[
                              const SizedBox(height: 4),
                              Text(
                                widget.description!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, color: cs.outline),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // 视频列表
            if (_videos.isEmpty && !_loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Center(child: Text('该合集暂无视频')),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: Style.safeSpace),
                sliver: SliverList.builder(
                  itemCount: _videos.length,
                  itemBuilder: (context, index) {
                    if (index == _videos.length - 1) {
                      // 加载更多 - 使用 addPostFrameCallback 避免在 build 中调用 _loadVideos
                      // （同 member_space_page / session_list_section 范式）：_loadVideos 在
                      // 首个 await 之前就 setState，而 itemBuilder 在 layout 阶段被调用，
                      // 直接调用会触发「setState() called during build」断言（Debug 才暴露）。
                      if (!_loading && !_isEnd) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && !_loading && !_isEnd) {
                            _loadVideos();
                          }
                        });
                      }
                    }
                    final item = _videos[index];
                    return _buildVideoItem(item, index + 1);
                  },
                ),
              ),
            if (_loading)
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
            if (_failed)
              SliverToBoxAdapter(
                child: Center(
                  child: TextButton(
                    onPressed: () => _loadVideos(),
                    child: const Text('加载失败，点击重试'),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: Style.xxl)),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoItem(MemberVideoItem item, int index) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final bvid = item.bvid;

    return Container(
      margin: const EdgeInsets.only(bottom: Style.sm),
      decoration: ShapeDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Style.radiusSm),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.2)),
        ),
      ),
      child: MiuixPressable(
        onPressed: bvid == null
            ? null
            : () => Navigator.push(
                  context,
                  AppRoute(
                    builder: (_) => VideoDetailPage(bvid: bvid, cover: item.pic),
                  ),
                ),
        borderRadius: BorderRadius.circular(Style.radiusSm),
        child: Padding(
          padding: const EdgeInsets.all(Style.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 序号
              SizedBox(
                width: 28,
                child: Center(
                  child: Text(
                    '$index',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // 封面
              ClipRRect(
                borderRadius: BorderRadius.circular(Style.radiusXs),
                child: Stack(
                  children: [
                    SizedBox(
                      width: 110,
                      height: 68,
                      child: NetworkImgLayer(
                        src: item.pic,
                        width: 110,
                        height: 68,
                        borderRadius: BorderRadius.circular(Style.radiusXs),
                      ),
                    ),
                    if ((item.duration ?? 0) > 0)
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: PBadge(
                          text: DurationUtils.formatDuration(item.duration),
                          type: PBadgeType.duration,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: Style.sm),
              // 标题与播放信息
              Expanded(
                child: SizedBox(
                  height: 68,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        item.title ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, height: 1.3),
                      ),
                      Row(
                        children: [
                          AppIcon(AppIcons.viewCount(), size: 12, color: cs.outline),
                          const SizedBox(width: 2),
                          Text(
                            NumUtils.formatNum(item.play),
                            style: TextStyle(fontSize: 11, color: cs.outline),
                          ),
                          if (item.pubdate != null) ...[
                            const Spacer(),
                            Text(
                              DateFormatUtils.dateFormat(item.pubdate!),
                              style: TextStyle(fontSize: 10, color: cs.outline),
                            ),
                          ],
                        ],
                      ),
                    ],
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
