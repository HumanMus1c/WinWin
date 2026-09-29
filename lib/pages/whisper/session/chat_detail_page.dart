import 'dart:convert';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/msg.dart';
import 'package:winwin/pages/video/detail_page.dart';
import 'package:winwin/pages/whisper/session/message_preview_parser.dart';
import 'package:winwin/pages/whisper/session/session_account_resolver.dart';
import 'package:winwin/pages/whisper/session/session_settings_page.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/utils/id_utils.dart';
import 'package:winwin/utils/image_utils.dart';

/// 聊天详情入口（阶段 D）。
///
/// 蓝本：BiliPai `ChatScreen` + `ChatViewModel`。
/// sessionMsg 历史（API 返回 newest-first，reversed 为 oldest-first 存储）；
/// ListView reverse:true 渲染，首屏天然停在最新消息，向最旧端滚动分页补历史；
/// 进入即用 max_seqno 调 ackSessionMsg 标记已读；sendTextMsg 发送后刷新。
void showChatDetailPage(
  BuildContext context, {
  required int talkerId,
  int sessionType = 1,
  required String title,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ChatDetailPage(
        talkerId: talkerId,
        sessionType: sessionType,
        title: title,
      ),
    ),
  );
}

class ChatDetailPage extends StatefulWidget {
  const ChatDetailPage({
    super.key,
    required this.talkerId,
    required this.title,
    this.sessionType = 1,
  });

  final int talkerId;
  final String title;
  final int sessionType;

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends State<ChatDetailPage> {
  final List<Map<String, dynamic>> _messages = []; // oldest-first
  final ScrollController _scrollCtrl = ScrollController();
  final TextEditingController _inputCtrl = TextEditingController();
  int? _minSeqno;
  bool _hasMore = true;
  bool _loading = true;
  bool _loadingMore = false;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _load(refresh: true);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    // 项目约定：触碰网络前等待 bootstrap（幂等），防 dio 未初始化。
    await ensureBootstrap();
    if (refresh) {
      _hasMore = true;
      _messages.clear();
      setState(() => _loading = true);
    }
    if (!_hasMore || _loadingMore) return;
    _loadingMore = true;
    final res = await MsgHttp.sessionMsg(
      talkerId: widget.talkerId,
      sessionType: widget.sessionType,
      endSeqno: refresh ? null : _minSeqno,
    );
    _loadingMore = false;
    if (!mounted) return;
    switch (res) {
      case Success(:final response):
        final raw = (response['messages'] as List?)
                ?.map((e) => (e as Map).cast<String, dynamic>())
                .toList() ??
            const [];
        // API 返回 newest-first，反转为 oldest-first 后前置更早的历史。
        final older = raw.reversed.toList();
        setState(() {
          _loading = false;
          _error = null;
          _messages.insertAll(0, older);
          _minSeqno = (response['min_seqno'] as num?)?.toInt() ?? _minSeqno;
          final max = (response['max_seqno'] as num?)?.toInt();
          if (max != null && max > 0) {
            if (refresh) MsgHttp.ackSessionMsg(talkerId: widget.talkerId, ackSeqno: max);
          }
          _hasMore = (response['has_more'] == 1) && older.isNotEmpty;
        });
        if (refresh) {
          _scrollToBottom();
        }
        // 非 refresh 时无需滚动回补：reverse 列表的 pixels 从最新端计量，
        // 旧消息插在远端（maxScrollExtent 增大），视口自然保持在原消息上。
        // 内容不满一屏时继续补旧消息，直到填满视口或到底。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_hasMore || _loadingMore) return;
          if (_scrollCtrl.hasClients &&
              _scrollCtrl.position.hasContentDimensions &&
              _scrollCtrl.position.maxScrollExtent <= 0) {
            _load();
          }
        });
      case Error(:final errMsg):
        setState(() {
          _loading = false;
          _error = errMsg ?? '加载失败';
        });
      case Loading():
        break;
    }
  }

  /// 滚动接近最旧端（reverse 列表的 maxScrollExtent）时加载更早的历史。
  void _onScroll() {
    if (!_scrollCtrl.hasClients ||
        !_scrollCtrl.position.hasContentDimensions) {
      return;
    }
    if (_loading || _loadingMore || !_hasMore) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 120) {
      _load();
    }
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final res = await MsgHttp.sendTextMsg(
      receiverId: widget.talkerId,
      text: text,
      receiverType: widget.sessionType,
    );
    if (!mounted) return;
    if (res.isSuccess) {
      _inputCtrl.clear();
      await _load(refresh: true);
    } else {
      final msg = res is Error ? (res.errMsg ?? '发送失败') : '发送失败';
      showToast(context, msg);
    }
    if (mounted) setState(() => _sending = false);
  }

  void _scrollToBottom() {
    // reverse 列表中 pixels=0 即最新消息。回调可能在 ListView 挂载前
    // 的帧执行（此时 hasClients=false），重试到挂载成功为止。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scrollCtrl.hasClients) {
        _scrollToBottom();
        return;
      }
      _scrollCtrl.jumpTo(0);
    });
  }

  bool _isMe(Map<String, dynamic> msg) {
    final sender = (msg['sender_uid'] as num?)?.toInt();
    return sender != null && sender == Accounts.main.mid;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        // 下方列表滚动时标题栏不叠加 surfaceTint 变色。
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            tooltip: '会话设置',
            onPressed: () => showSessionSettingsPage(
              context,
              talkerId: widget.talkerId,
              sessionType: widget.sessionType,
              title: widget.title,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading && _messages.isEmpty
                ? const Center(child: CircularProgressIndicator(color: biliPink))
                : _error != null && _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_error!),
                            const SizedBox(height: Style.md),
                            FilledButton(
                              onPressed: () => _load(refresh: true),
                              style: FilledButton.styleFrom(backgroundColor: biliPink),
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        // reverse：最新在底部（pixels=0），首屏天然定位到最新
                        // 消息，不依赖 post-frame jumpTo 的时序。
                        reverse: true,
                        padding: const EdgeInsets.symmetric(
                            horizontal: Style.safeSpace, vertical: Style.sm),
                        itemCount: _messages.length + (_hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          // reverse 列表：index 0 = 最新消息；
                          // 最末项（最旧端）为加载指示器。
                          if (_hasMore && index == _messages.length) {
                            return const Padding(
                              padding: EdgeInsets.all(Style.sm),
                              child: Center(
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: biliPink),
                                ),
                              ),
                            );
                          }
                          final msgIndex = _messages.length - 1 - index;
                          if (msgIndex < 0 || msgIndex >= _messages.length) {
                            return const SizedBox.shrink();
                          }
                          return _ChatBubble(
                            msg: _messages[msgIndex],
                            isMe: _isMe(_messages[msgIndex]),
                          );
                        },
                      ),
          ),
          _buildInputBar(theme),
        ],
      ),
    );
  }

  Widget _buildInputBar(ThemeData theme) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Style.safeSpace, vertical: Style.sm),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: '发送消息',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: Style.md, vertical: Style.sm),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Style.radiusFull),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
            ),
            const SizedBox(width: Style.sm),
            IconButton.filled(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.msg, required this.isMe});

  final Map<String, dynamic> msg;
  final bool isMe;

  int get _msgType => (msg['msg_type'] as num?)?.toInt() ?? 1;

  String get _text {
    final msgType = _msgType;
    final content = msg['content']?.toString();
    if ((msg['msg_status'] as num?)?.toInt() == 1) return '消息已撤回';
    if (msgType == 1) {
      // 文本：content 可能是裸文本或 {"content":"..."} JSON。
      if (content == null || content.isEmpty) return '';
      final trimmed = content.trim();
      if (!trimmed.startsWith('{')) return content;
      try {
        final j = jsonDecode(trimmed);
        if (j is Map) return j['content']?.toString() ?? content;
      } catch (_) {}
      return content;
    }
    return MessagePreviewParser.parseSessionPreview(content, msgType);
  }

  Map<String, dynamic>? get _contentJson {
    final raw = msg['content']?.toString();
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final msgType = _msgType;
    final isRevoked = (msg['msg_status'] as num?)?.toInt() == 1;
    final align = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    // 富媒体消息：图片 / 分享卡片 / 视频稿件 / 专栏，按卡片形式渲染。
    if (!isRevoked) {
      switch (msgType) {
        case 2:
          return _wrap(_buildImage(context, theme));
        case 7 || 14:
          return _wrap(_buildShareCard(context, theme));
        case 11:
          return _wrap(_buildVideoCard(context, theme));
        case 12:
          return _wrap(_buildArticleCard(theme));
      }
    }

    final text = _text;
    final bubbleColor = isMe
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;
    final textColor = isMe ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: align,
        children: [
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.72,
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: Style.md, vertical: Style.sm),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
              ),
              child: Text(
                text.isEmpty ? '[消息]' : text,
                style: theme.textTheme.bodyMedium?.copyWith(color: textColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 卡片/图片消息外层：对齐方向 + 宽度约束，样式对齐普通气泡圆角。
  Widget _wrap(Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 图片消息（msg_type=2）：content = {url, width, height}。
  Widget _buildImage(BuildContext context, ThemeData theme) {
    final json = _contentJson ?? const <String, dynamic>{};
    final url = SessionAccountResolver.normalizeAvatarUrl(json['url']?.toString());
    final imgWidth = (json['width'] as num?)?.toDouble() ?? 0;
    final imgHeight = (json['height'] as num?)?.toDouble() ?? 0;
    final width = imgWidth > 0 ? math.min(220.0, imgWidth) : 220.0;
    final ratio = imgWidth > 0 && imgHeight > 0 ? imgHeight / imgWidth : 0.75;
    return GestureDetector(
      onTap: url.isEmpty ? null : () => _previewImage(context, url),
      child: NetworkImgLayer(width: width, height: width * ratio, src: url),
    );
  }

  void _previewImage(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final size = MediaQuery.sizeOf(ctx);
        return Dialog(
          backgroundColor: Colors.transparent,
          child: InteractiveViewer(
            child: Image.network(
              url,
              cacheWidth: ImageUtils.decodeClamp(size.width, ctx, max: 2048),
              cacheHeight: ImageUtils.decodeClamp(size.height, ctx, max: 2048),
            ),
          ),
        );
      },
    );
  }

  /// 分享卡片（msg_type=7/14）：source 区分视频/专栏/动态/番剧/直播。
  /// 视频稿件（source=5）点击跳播放；其余类型仅展示封面与标题。
  Widget _buildShareCard(BuildContext context, ThemeData theme) {
    final json = _contentJson;
    if (json == null) return _fallbackText(theme);
    final source = json['source'];
    final sourceInt = source is int
        ? source
        : source is String
            ? int.tryParse(source)
            : null;
    final kind = switch (sourceInt) {
      2 => '相簿',
      5 => '视频',
      6 => '专栏',
      7 || 16 || 17 => '番剧',
      11 => '动态',
      _ => source == '直播' ? '直播' : '分享',
    };
    final cover = SessionAccountResolver.normalizeAvatarUrl(
        json['thumb']?.toString() ?? json['image']?.toString());
    final title = json['title']?.toString() ?? '';
    final author = json['author']?.toString() ?? '';
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: sourceInt == 5 ? () => _openSharedVideo(context, theme, json) : null,
        child: Padding(
          padding: const EdgeInsets.all(Style.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (cover.isNotEmpty)
                NetworkImgLayer(width: 300, height: 300 / 16 * 9, src: cover),
              const SizedBox(height: Style.sm),
              Text(
                title.isEmpty ? '[$kind]' : title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                author.isEmpty ? kind : '$author · $kind',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 视频稿件卡片（msg_type=11）：content = {bvid, title, cover, times...}。
  Widget _buildVideoCard(BuildContext context, ThemeData theme) {
    final json = _contentJson;
    if (json == null) return _fallbackText(theme);
    final bvid = json['bvid']?.toString() ?? '';
    final title = json['title']?.toString() ?? '';
    final cover = SessionAccountResolver.normalizeAvatarUrl(json['cover']?.toString());
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: bvid.isEmpty ? null : () => _openVideo(context, bvid, cover),
        child: Padding(
          padding: const EdgeInsets.all(Style.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (cover.isNotEmpty)
                NetworkImgLayer(width: 300, height: 300 / 16 * 9, src: cover),
              const SizedBox(height: Style.sm),
              Text(
                title.isEmpty ? '[视频]' : title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 专栏卡片（msg_type=12）：暂不支持专栏阅读器，仅展示图文预览。
  Widget _buildArticleCard(ThemeData theme) {
    final json = _contentJson;
    if (json == null) return _fallbackText(theme);
    final images = json['image_urls'];
    final first = images is List && images.isNotEmpty
        ? SessionAccountResolver.normalizeAvatarUrl(images.first?.toString())
        : '';
    final title = json['title']?.toString() ?? '';
    final summary = json['summary']?.toString() ?? '';
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.all(Style.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (first.isNotEmpty)
            NetworkImgLayer(width: 300, height: 300 / 16 * 9, src: first),
          const SizedBox(height: Style.sm),
          Text(
            title.isEmpty ? '[专栏]' : title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  Widget _fallbackText(ThemeData theme) {
    final text = _text;
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: Style.md, vertical: Style.sm),
      child: Text(
        text.isEmpty ? '[消息]' : text,
        style: theme.textTheme.bodyMedium,
      ),
    );
  }

  void _openSharedVideo(
      BuildContext context, ThemeData theme, Map<String, dynamic> json) {
    String? bvid = json['bvid']?.toString();
    if (bvid == null || bvid.isEmpty) {
      final aid = (json['id'] as num?)?.toInt();
      if (aid != null && aid > 0) bvid = IdUtils.av2bv(aid);
    }
    if (bvid == null || bvid.isEmpty) {
      _toast(context, '无法解析稿件信息');
      return;
    }
    _openVideo(context, bvid, json['thumb']?.toString());
  }

  void _openVideo(BuildContext context, String bvid, String? cover) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VideoDetailPage(
          bvid: bvid,
          cover: SessionAccountResolver.normalizeAvatarUrl(cover),
        ),
      ),
    );
  }

  void _toast(BuildContext context, String msg) {
    showToast(context, msg, duration: const Duration(seconds: 1));
  }
}
