import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:winwin/common/widgets/comment/reply_content_view.dart';
import 'package:winwin/common/widgets/image/image_gallery_viewer.dart';
import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/common/widgets/p_badge.dart';
import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/http/dyn.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/video.dart';
import 'package:winwin/models/video/reply_item.dart';
import 'package:winwin/pages/article/article_page.dart';
import 'package:winwin/pages/bangumi/bangumi_detail_page.dart';
import 'package:winwin/pages/live/live_room_page.dart';
import 'package:winwin/pages/member/member_space_page.dart';
import 'package:winwin/pages/video/detail_page.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/utils/bilibili_url_parser.dart';
import 'package:winwin/utils/id_utils.dart';
import 'package:winwin/utils/image_utils.dart';
import 'package:winwin/utils/num_utils.dart';

/// 动态详情页面。
///
/// 特性：
/// - 完整展示正文富文本（支持划词选中，消除行数截断限制）；
/// - 完整渲染多图九宫格/大图，点击任意图片唤起 [showImageGallery] 全屏左右切换画廊；
/// - 深度适配转发嵌套、内嵌视频、专栏卡片、直播间直达；
/// - 自动接入 B站动态专属评论区（type: 11 / 17）。
class DynamicDetailPage extends StatefulWidget {
  const DynamicDetailPage({
    super.key,
    this.item,
    this.dynamicId,
  }) : assert(item != null || dynamicId != null, 'item 或 dynamicId 必须提供一个');

  final DynItemModel? item;
  final String? dynamicId;

  @override
  State<DynamicDetailPage> createState() => _DynamicDetailPageState();
}

class _DynamicDetailPageState extends State<DynamicDetailPage> {
  LoadingState<DynItemModel> _state = LoadingState.loading();

  final List<ReplyItemModel> _replies = [];
  bool _loadingReplies = false;
  bool _repliesLoaded = false;

  String get _effectiveId => widget.item?.id ?? widget.dynamicId ?? '';

  @override
  void initState() {
    super.initState();
    if (widget.item != null) {
      _state = Success(widget.item!);
      _loadReplies();
    } else {
      _loadDetail();
    }
  }

  Future<void> _loadDetail() async {
    setState(() => _state = LoadingState.loading());
    await ensureBootstrap();

    final res = await DynHttp.dynamicDetail(dynamicId: _effectiveId);
    if (!mounted) return;

    setState(() {
      _state = res;
    });

    if (res is Success) {
      _loadReplies();
    }
  }

  Future<void> _loadReplies() async {
    final numericId = int.tryParse(_effectiveId);
    if (numericId == null || numericId <= 0) return;

    setState(() => _loadingReplies = true);
    // B站动态评论区 type 一般为 11（图文/文字）或 17
    final res = await VideoHttp.replyMain(
      oid: numericId,
      type: 11,
    );

    if (!mounted) return;
    if (res case Success(:final response)) {
      setState(() {
        _replies.addAll(response.replies);
        _repliesLoaded = true;
        _loadingReplies = false;
      });
    } else {
      setState(() {
        _repliesLoaded = true;
        _loadingReplies = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('动态详情', style: TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            icon: Icon(AppIcons.refresh(context)),
            tooltip: '重新加载',
            onPressed: _loadDetail,
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: '复制动态链接',
            onPressed: () {
              Clipboard.setData(
                ClipboardData(text: 'https://t.bilibili.com/$_effectiveId'),
              );
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                const SnackBar(
                  content: Text('已复制动态链接'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: switch (_state) {
        Loading() => const Center(child: CircularProgressIndicator()),
        Error(:final errMsg) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(errMsg ?? '动态加载失败'),
                const SizedBox(height: Style.md),
                FilledButton.tonal(
                  onPressed: _loadDetail,
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        Success(:final response) => _buildDetailContent(response, cs, theme),
      },
    );
  }

  Widget _buildDetailContent(
    DynItemModel item,
    ColorScheme cs,
    ThemeData theme,
  ) {
    final author = item.author;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: SelectionArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Style.lg,
              vertical: Style.md,
            ),
            child: CustomScrollView(
              slivers: [
                // 作者信息头部
                SliverToBoxAdapter(
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          if (author?.mid != null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    MemberSpacePage(mid: author!.mid!),
                              ),
                            );
                          }
                        },
                        child: NetworkImgLayer(
                          src: author?.face,
                          width: 44,
                          height: 44,
                          type: 'avatar',
                        ),
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
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (author?.pubAction != null &&
                                    author!.pubAction!.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    author.pubAction!,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: cs.outline,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (item.pubTs != null)
                              Text(
                                _formatTime(item.pubTs!),
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

                const SliverToBoxAdapter(child: SizedBox(height: Style.md)),

                // 完整正文（富文本）
                if (item.text != null && item.text!.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: Style.md),
                      child: item.richTextNodes.isNotEmpty
                          ? SelectableText.rich(
                              TextSpan(
                                children: _buildRichSpans(
                                  context,
                                  item.richTextNodes,
                                  cs.primary,
                                ),
                              ),
                              style: theme.textTheme.bodyLarge?.copyWith(
                                height: 1.6,
                                letterSpacing: 0.2,
                              ),
                            )
                          : SelectableText(
                              item.text!,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                height: 1.6,
                                letterSpacing: 0.2,
                              ),
                            ),
                    ),
                  ),

                // 动态主体：图文多图九宫格
                if (item.draw != null && item.draw!.items.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: Style.md),
                      child: _buildDrawGrid(context, item.draw!.items),
                    ),
                  ),

                // Opus 卡片
                if (item.opus != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: Style.md),
                      child: _buildOpusSection(context, item.opus!),
                    ),
                  ),

                // 视频卡片
                if (item.isVideo &&
                    item.archive != null &&
                    (item.archive!.bvid != null || item.archive!.title != null))
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: Style.md),
                      child: _buildVideoPreview(context, item.archive!),
                    ),
                  ),

                // 追番剧集卡片
                if (item.isPgc && item.pgc != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: Style.md),
                      child: _buildPgcPreview(context, item.pgc!),
                    ),
                  ),

                // 专栏卡片
                if (item.article != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: Style.md),
                      child: _buildArticlePreview(context, item.article!),
                    ),
                  ),

                // 直播卡片
                if (item.live != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: Style.md),
                      child: _buildLivePreview(context, item.live!),
                    ),
                  ),

                // 转发原动态
                if (item.isForward && item.orig != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: Style.md),
                      child: _buildForwardSection(context, item.orig!),
                    ),
                  ),

                // 互动统计行
                if (item.stat != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Style.sm),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatItem(
                            AppIcons.reply(context),
                            item.stat!.repost ?? 0,
                            cs.outline,
                          ),
                          _buildStatItem(
                            AppIcons.whisper(context),
                            item.stat!.comment ?? 0,
                            cs.outline,
                          ),
                          _buildStatItem(
                            AppIcons.like(context),
                            item.stat!.like ?? 0,
                            cs.outline,
                          ),
                        ],
                      ),
                    ),
                  ),

                // 分割线
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: Style.md),
                    child: Divider(thickness: 1),
                  ),
                ),

                // 评论区标题
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: Style.md),
                    child: Row(
                      children: [
                        const Icon(Icons.chat_bubble_outline, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          '全部评论 ${item.stat?.comment != null ? '(${NumUtils.formatNum(item.stat!.comment)})' : ''}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 评论流
                if (_loadingReplies)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(Style.lg),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  )
                else if (_replies.isEmpty && _repliesLoaded)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(Style.xl),
                      child: Center(
                        child: Text(
                          '暂无评论，来发表第一条评论吧~',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final reply = _replies[index];
                        final member = reply.member;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: Style.sm),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  final mid = member?.mid;
                                  if (mid != null && mid > 0) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            MemberSpacePage(mid: mid),
                                      ),
                                    );
                                  }
                                },
                                child: NetworkImgLayer(
                                  src: member?.avatar,
                                  width: 34,
                                  height: 34,
                                  type: 'avatar',
                                ),
                              ),
                              const SizedBox(width: Style.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      member?.uname ?? 'B站用户',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: cs.outline,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    ReplyContentView(
                                      content: reply.content,
                                      textStyle: theme.textTheme.bodyMedium?.copyWith(
                                        height: 1.4,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        if (reply.ctime != null)
                                          Text(
                                            _formatTime(reply.ctime!),
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: cs.outline
                                                  .withValues(alpha: 0.7),
                                            ),
                                          ),
                                        const Spacer(),
                                        if (reply.like != null &&
                                            reply.like! > 0) ...[
                                          Icon(
                                            AppIcons.like(context),
                                            size: 12,
                                            color: cs.outline,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            NumUtils.formatNum(reply.like),
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: cs.outline,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    const Divider(height: 1, thickness: 0.3),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                      childCount: _replies.length,
                    ),
                  ),

                const SliverToBoxAdapter(child: SizedBox(height: 60)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 图文九宫格图片渲染（点击直接进入多图画廊）
  Widget _buildDrawGrid(BuildContext context, List<DynDrawItem> pics) {
    if (pics.isEmpty) return const SizedBox.shrink();
    final imageUrls = pics.map((p) => p.src).whereType<String>().toList();

    if (pics.length == 1) {
      final item = pics.first;
      final w = item.width ?? 16;
      final h = item.height ?? 9;
      final aspect = (w > 0 && h > 0) ? (w / h).clamp(0.7, 2.0) : 16 / 9;

      return GestureDetector(
        onTap: () => showImageGallery(
          context,
          imageUrls: imageUrls,
          thumbnailUrls: imageUrls,
          initialIndex: 0,
        ),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 380),
            child: AspectRatio(
              aspectRatio: aspect,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Style.radiusSm),
                child: NetworkImgLayer(
                  src: item.src,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final crossAxisCount = pics.length == 4 ? 2 : (pics.length >= 3 ? 3 : 2);

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 500.0;
        const spacing = 6.0;
        final rawItemWidth =
            (totalWidth - spacing * (crossAxisCount - 1)) / crossAxisCount;
        final itemWidth = rawItemWidth.clamp(70.0, 180.0);

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: pics.asMap().entries.map((entry) {
            final idx = entry.key;
            final pic = entry.value;

            return GestureDetector(
              onTap: () => showImageGallery(
                context,
                imageUrls: imageUrls,
                thumbnailUrls: imageUrls,
                initialIndex: idx,
              ),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: SizedBox(
                  width: itemWidth,
                  height: itemWidth,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Style.radiusSm),
                    child: NetworkImgLayer(
                      src: pic.src,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  /// Opus 区域
  Widget _buildOpusSection(BuildContext context, DynOpus opus) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (opus.title != null && opus.title!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              opus.title!,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        if (opus.summaryText != null && opus.summaryText!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              opus.summaryText!,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ),
        if (opus.pics.isNotEmpty) _buildDrawGrid(context, opus.pics),
        if (opus.video != null && opus.video!.bvid != null) ...[
          const SizedBox(height: Style.sm),
          _buildVideoPreview(context, opus.video!),
        ],
      ],
    );
  }

  /// 视频预览卡片
  Widget _buildVideoPreview(BuildContext context, DynArchive archive) {
    return GestureDetector(
      onTap: () {
        final bvid = archive.bvid;
        if (bvid == null) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VideoDetailPage(bvid: bvid, cover: archive.cover),
          ),
        );
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
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
                ),
              ),
              if (archive.badge != null && archive.badge!.isNotEmpty)
                Positioned(
                  right: 6,
                  top: 6,
                  child: PBadge(text: archive.badge!, type: PBadgeType.badge),
                ),
              Positioned.fill(
                child: Container(
                  alignment: Alignment.bottomLeft,
                  padding: const EdgeInsets.all(Style.sm),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.75),
                      ],
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
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (archive.durationText != null ||
                          archive.play != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (archive.durationText != null)
                              PBadge(
                                text: archive.durationText,
                                type: PBadgeType.duration,
                              ),
                            if (archive.play != null) ...[
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.play_circle_outlined,
                                size: 12,
                                color: Colors.white70,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                NumUtils.formatNum(archive.play),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white70,
                                ),
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
      ),
    );
  }

  /// 追番剧集卡片
  Widget _buildPgcPreview(BuildContext context, DynPgc pgc) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cover = pgc.cover;

    return InkWell(
      onTap: () {
        if (pgc.jumpUrl != null && pgc.jumpUrl!.isNotEmpty) {
          _handleJumpUrl(context, pgc.jumpUrl!);
        }
      },
      borderRadius: BorderRadius.circular(Style.radiusSm),
      child: Container(
        padding: const EdgeInsets.all(Style.sm),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(Style.radiusSm),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            if (cover != null && cover.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(Style.radiusXs),
                child: SizedBox(
                  width: 100,
                  height: 65,
                  child: NetworkImgLayer(
                    src: cover,
                    width: 100,
                    height: 65,
                  ),
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
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
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

  /// 专栏卡片预览（点击进入专栏页面）
  Widget _buildArticlePreview(BuildContext context, DynArticle article) {
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
      child: InkWell(
        onTap: () {
          final id = article.id;
          if (id != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
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
        borderRadius: BorderRadius.circular(Style.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(Style.md),
          child: Row(
            children: [
              if (cover != null && cover.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(Style.radiusSm),
                  child: SizedBox(
                    width: 110,
                    height: 75,
                    child: NetworkImgLayer(
                      src: cover,
                      width: 110,
                      height: 75,
                    ),
                  ),
                ),
                const SizedBox(width: Style.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      article.title ?? '专栏文章',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (article.desc != null && article.desc!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        article.desc!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.outline,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 直播卡片预览（点击直达直播间）
  Widget _buildLivePreview(BuildContext context, DynLive live) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isLiving = live.liveStatus == 1 || live.badge == '直播中';

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Style.radiusMd),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        onTap: () {
          var roomId = live.roomId;
          if ((roomId == null || roomId <= 0) &&
              live.jumpUrl != null &&
              live.jumpUrl!.isNotEmpty) {
            roomId = BilibiliUrlParser.parse(live.jumpUrl!).roomId;
          }
          if (roomId != null && roomId > 0) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => LiveRoomPage(
                  roomId: roomId!,
                  title: live.title,
                  uname: live.uname,
                  cover: live.cover,
                ),
              ),
            );
          } else if (live.jumpUrl != null && live.jumpUrl!.isNotEmpty) {
            _handleJumpUrl(context, live.jumpUrl!);
          }
        },
        borderRadius: BorderRadius.circular(Style.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(Style.md),
          child: Row(
            children: [
              if (live.cover != null && live.cover!.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(Style.radiusSm),
                  child: SizedBox(
                    width: 120,
                    height: 75,
                    child: NetworkImgLayer(
                      src: live.cover,
                      width: 120,
                      height: 75,
                    ),
                  ),
                ),
                const SizedBox(width: Style.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      live.title ?? (isLiving ? '正在直播' : '直播已结束'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isLiving ? '● 正在直播中' : '已结束',
                      style: TextStyle(
                        fontSize: 12,
                        color: isLiving ? Colors.redAccent : cs.outline,
                        fontWeight: FontWeight.bold,
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

  /// 转发动态区域
  Widget _buildForwardSection(BuildContext context, DynItemModel orig) {
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
          if (origAuthor != null && origAuthor.name != null)
            GestureDetector(
              onTap: () {
                if (origAuthor.mid != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MemberSpacePage(mid: origAuthor.mid!),
                    ),
                  );
                }
              },
              child: Text(
                '@${origAuthor.name}',
                style: TextStyle(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          if (orig.text != null && orig.text!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              orig.text!,
              style: theme.textTheme.bodyMedium,
            ),
          ],
          if (orig.draw != null && orig.draw!.items.isNotEmpty) ...[
            const SizedBox(height: Style.sm),
            _buildDrawGrid(context, orig.draw!.items),
          ] else if (orig.isVideo && orig.archive != null) ...[
            const SizedBox(height: Style.sm),
            _buildVideoPreview(context, orig.archive!),
          ] else if (orig.article != null) ...[
            const SizedBox(height: Style.sm),
            _buildArticlePreview(context, orig.article!),
          ],
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, int count, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          count > 0 ? NumUtils.formatNum(count) : '0',
          style: TextStyle(fontSize: 13, color: color),
        ),
      ],
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

      if (node.emojiUrl != null && node.emojiUrl!.isNotEmpty) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Image.network(
              ImageUtils.thumbnailUrl(node.emojiUrl, type: 'emote'),
              width: 20,
              height: 20,
              cacheWidth: 64,
              cacheHeight: 64,
              errorBuilder: (_, _, _) => Text(text),
            ),
          ),
        ));
      } else if (type.contains('BV') ||
          (node.rid != null && node.rid!.startsWith('BV'))) {
        final bvid = node.rid ?? (text.startsWith('BV') ? text : null);
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: InkWell(
            onTap: () {
              if (bvid != null && bvid.isNotEmpty) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => VideoDetailPage(bvid: bvid)),
                );
              }
            },
            child: Text(
              text,
              style: TextStyle(color: primaryColor, fontWeight: FontWeight.w500),
            ),
          ),
        ));
      } else if (type.contains('AT') || text.startsWith('@')) {
        final mid = int.tryParse(node.rid ?? '');
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: InkWell(
            onTap: () {
              if (mid != null && mid > 0) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => MemberSpacePage(mid: mid)),
                );
              }
            },
            child: Text(
              text,
              style: TextStyle(color: primaryColor, fontWeight: FontWeight.w500),
            ),
          ),
        ));
      } else if (node.jumpUrl != null && node.jumpUrl!.isNotEmpty) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: InkWell(
            onTap: () => _handleJumpUrl(context, node.jumpUrl!),
            child: Text(
              text,
              style: TextStyle(
                color: primaryColor,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ));
      } else {
        spans.add(TextSpan(text: text));
      }
    }
    return spans;
  }

  void _handleJumpUrl(BuildContext context, String url) {
    final result = BilibiliUrlParser.parseDeepLink(url);
    if (result.isLive && result.roomId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LiveRoomPage(roomId: result.roomId!),
        ),
      );
      return;
    }
    if (result.isArticle && result.articleId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ArticlePage(id: result.articleId!.toString()),
        ),
      );
      return;
    }
    if (result.dynamicId != null && result.dynamicId != _effectiveId) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DynamicDetailPage(dynamicId: result.dynamicId!),
        ),
      );
      return;
    }
    if (result.isBangumi) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BangumiDetailPage(
            seasonId: result.seasonId,
            epId: result.epId,
            mediaId: result.mediaId,
          ),
        ),
      );
      return;
    }
    if (result.bvid != null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => VideoDetailPage(bvid: result.bvid!)),
      );
      return;
    }
    if (result.aid != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoDetailPage(bvid: IdUtils.av2bv(result.aid!)),
        ),
      );
      return;
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('链接：$url')),
    );
  }

  static String _formatTime(int ts) {
    if (ts <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.isNegative || diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 30) return '${diff.inDays}天前';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
