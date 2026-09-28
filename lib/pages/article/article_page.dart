import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:winwin/common/widgets/comment/comment_input_bar.dart';
import 'package:winwin/common/widgets/comment/reply_content_view.dart';
import 'package:winwin/common/widgets/image/image_gallery_viewer.dart';
import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/core/account/login_guard.dart';
import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/http/article.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/video.dart';
import 'package:winwin/models/video/reply_item.dart';
import 'package:winwin/pages/member/member_space_page.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/utils/num_utils.dart';

/// 专栏文章阅读页面。
///
/// 特性：
/// - 展示专栏封面、标题、UP 主信息与阅读互动统计；
/// - 正文文本自由选中文本、小标题排版、插图渲染；
/// - 点击任意正文插图直接唤起 [showImageGallery] 多图画廊并支持左右滑动切换；
/// - 底部内嵌加载专栏专属评论流（B站 type: 12 专栏评论）。
class ArticlePage extends StatefulWidget {
  const ArticlePage({
    super.key,
    required this.id,
    this.title,
    this.cover,
    this.desc,
  });

  /// 专栏文章 ID（支持带 'cv' 或纯数字）。
  final String id;
  final String? title;
  final String? cover;
  final String? desc;

  @override
  State<ArticlePage> createState() => _ArticlePageState();
}

class _ArticlePageState extends State<ArticlePage> {
  LoadingState<ArticleDetailModel> _state = LoadingState.loading();
  final List<ReplyItemModel> _replies = [];
  bool _loadingReplies = false;
  bool _repliesLoaded = false;

  final TextEditingController _commentCtrl = TextEditingController();
  final FocusNode _commentFocus = FocusNode();
  bool _sendingComment = false;

  String get _cleanId =>
      widget.id.toLowerCase().replaceAll(RegExp(r'^cv'), '');

  @override
  void initState() {
    super.initState();
    _loadArticle();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  Future<void> _loadArticle() async {
    setState(() => _state = LoadingState.loading());
    await ensureBootstrap();

    final res = await ArticleHttp.articleView(cvId: _cleanId);
    if (!mounted) return;

    setState(() => _state = res);
    if (res is Success) {
      _loadReplies();
    }
  }

  Future<void> _loadReplies() async {
    final numericId = int.tryParse(_cleanId);
    if (numericId == null || numericId <= 0) return;

    setState(() => _loadingReplies = true);
    final res = await VideoHttp.replyMain(
      oid: numericId,
      type: 12, // 12 为 B站专栏评论区业务类型
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

  /// 发送一级评论（type=12 专栏评论）。
  Future<void> _sendComment() async {
    final message = _commentCtrl.text.trim();
    if (message.isEmpty || _sendingComment) return;
    final numericId = int.tryParse(_cleanId);
    if (numericId == null || numericId <= 0) return;
    if (!await LoginGuard.requireLogin(context)) return;
    if (!mounted) return;

    setState(() => _sendingComment = true);
    final res = await VideoHttp.replyAdd(
      oid: numericId,
      message: message,
      type: 12,
    );
    if (!mounted) return;
    setState(() => _sendingComment = false);
    switch (res) {
      case Success(:final response):
        setState(() {
          _replies.insert(0, response);
          _repliesLoaded = true;
        });
        _commentCtrl.clear();
        _toast('发送成功');
      case Error(:final errMsg):
        _toast(errMsg ?? '发送失败');
      case Loading():
        break;
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final fallbackTitle = widget.title ?? '专栏文章';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _state.dataOrNull?.title ?? fallbackTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新加载',
            onPressed: _loadArticle,
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: '复制专栏链接',
            onPressed: () {
              Clipboard.setData(
                ClipboardData(text: 'https://www.bilibili.com/read/cv$_cleanId'),
              );
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                const SnackBar(
                  content: Text('已复制专栏文章链接'),
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
                Text(errMsg ?? '专栏内容加载失败'),
                const SizedBox(height: Style.md),
                FilledButton.tonal(
                  onPressed: _loadArticle,
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        Success(:final response) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildArticleContent(response, cs, theme)),
              // 输入栏与正文居中列（maxWidth 860）对齐，不再横向撑满全屏。
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: SimpleCommentInputBar(
                    controller: _commentCtrl,
                    focusNode: _commentFocus,
                    sending: _sendingComment,
                    onSend: _sendComment,
                  ),
                ),
              ),
            ],
          ),
      },
    );
  }

  Widget _buildArticleContent(
    ArticleDetailModel article,
    ColorScheme cs,
    ThemeData theme,
  ) {
    final allImages = article.imageUrls;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: SelectionArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Style.lg,
              vertical: Style.md,
            ),
            child: CustomScrollView(
              slivers: [
              // 封面大图（若有）
              if (article.bannerUrl != null && article.bannerUrl!.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: Style.lg),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Style.radiusMd),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: NetworkImgLayer(
                          src: article.bannerUrl,
                          width: double.infinity,
                          height: double.infinity,
                        ),
                      ),
                    ),
                  ),
                ),

              // 文章大标题
              SliverToBoxAdapter(
                child: Text(
                  article.title ?? widget.title ?? '',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    height: 1.35,
                  ),
                ),
              ),

              // UP 主信息与发表时间
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Style.md),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          if (article.authorMid != null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    MemberSpacePage(mid: article.authorMid!),
                              ),
                            );
                          }
                        },
                        child: NetworkImgLayer(
                          src: article.authorFace,
                          width: 40,
                          height: 40,
                          type: 'avatar',
                        ),
                      ),
                      const SizedBox(width: Style.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              article.authorName ?? 'UP 主',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (article.pubTime != null && article.pubTime! > 0)
                              Text(
                                _formatTime(article.pubTime!),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.outline,
                                ),
                              ),
                          ],
                        ),
                      ),
                      // 阅读量与点赞数
                      if (article.viewCount != null) ...[
                        Icon(Icons.remove_red_eye_outlined, size: 14, color: cs.outline),
                        const SizedBox(width: 3),
                        Text(
                          NumUtils.formatNum(article.viewCount),
                          style: TextStyle(fontSize: 12, color: cs.outline),
                        ),
                        const SizedBox(width: 12),
                      ],
                      if (article.likeCount != null) ...[
                        Icon(Icons.thumb_up_outlined, size: 14, color: cs.outline),
                        const SizedBox(width: 3),
                        Text(
                          NumUtils.formatNum(article.likeCount),
                          style: TextStyle(fontSize: 12, color: cs.outline),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SliverToBoxAdapter(
                child: Divider(height: 1, thickness: 0.5),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: Style.md)),

              // 正文段落与插图
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final p = article.paragraphs[index];
                    switch (p.type) {
                      case ArticleParagraphType.header:
                        return Padding(
                          padding: const EdgeInsets.only(top: 18, bottom: 8),
                          child: Text(
                            p.text ?? '',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      case ArticleParagraphType.image:
                        final imgUrl = p.imageUrl;
                        if (imgUrl == null || imgUrl.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Center(
                            child: GestureDetector(
                              onTap: () {
                                final initialIdx = allImages.indexOf(imgUrl);
                                showImageGallery(
                                  context,
                                  imageUrls: allImages,
                                  thumbnailUrls: allImages,
                                  initialIndex: initialIdx >= 0 ? initialIdx : 0,
                                );
                              },
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: ClipRRect(
                                  borderRadius:
                                      BorderRadius.circular(Style.radiusSm),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxHeight: 520,
                                    ),
                                    child: NetworkImgLayer(
                                      src: imgUrl,
                                      width: double.infinity,
                                      height: 360,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      case ArticleParagraphType.text:
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            p.text ?? '',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 15,
                              height: 1.8,
                              letterSpacing: 0.2,
                            ),
                          ),
                        );
                    }
                  },
                  childCount: article.paragraphs.length,
                ),
              ),

              // 底部间隔与评论区分割线
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: Style.xl),
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
                        '评论区 ${article.replyCount != null ? '(${NumUtils.formatNum(article.replyCount)})' : ''}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 评论列表
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
                      child: Text('暂无评论，来发表第一条评论吧~', style: TextStyle(color: Colors.grey)),
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
                                      builder: (_) => MemberSpacePage(mid: mid),
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
                                            color: cs.outline.withValues(alpha: 0.7),
                                          ),
                                        ),
                                      const Spacer(),
                                      if (reply.like != null && reply.like! > 0) ...[
                                        Icon(
                                          Icons.thumb_up_outlined,
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
