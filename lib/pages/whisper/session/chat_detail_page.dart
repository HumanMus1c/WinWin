import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/msg.dart';
import 'package:winwin/pages/whisper/session/message_preview_parser.dart';
import 'package:winwin/pages/whisper/session/session_settings_page.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';

/// 聊天详情入口（阶段 D）。
///
/// 蓝本：BiliPai `ChatScreen` + `ChatViewModel`。
/// sessionMsg 历史（API 返回 newest-first，reversed 为 oldest-first 显示）；
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
  int? _maxSeqno;
  bool _hasMore = true;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(refresh: true);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    if (refresh) {
      _hasMore = true;
      _messages.clear();
      setState(() => _loading = true);
    }
    if (!_hasMore) return;
    final res = await MsgHttp.sessionMsg(
      talkerId: widget.talkerId,
      sessionType: widget.sessionType,
      endSeqno: refresh ? null : _minSeqno,
    );
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
            _maxSeqno = max;
            if (refresh) MsgHttp.ackSessionMsg(talkerId: widget.talkerId, ackSeqno: max);
          }
          _hasMore = (response['has_more'] == 1) && older.isNotEmpty;
        });
        if (refresh) _scrollToBottom();
      case Error(:final errMsg):
        setState(() {
          _loading = false;
          _error = errMsg ?? '加载失败';
        });
      case Loading():
        break;
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
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(msg)));
    }
    if (mounted) setState(() => _sending = false);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: Style.safeSpace, vertical: Style.sm),
                        itemCount: _messages.length + (_hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (_hasMore && index == 0) {
                            _load();
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
                          final msgIndex = _hasMore ? index - 1 : index;
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

  String get _text {
    final msgType = (msg['msg_type'] as num?)?.toInt() ?? 1;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = _text;
    final align = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
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
}
