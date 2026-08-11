import 'dart:convert';

/// 私信消息预览解析器（移植自 BiliPai `MessagePreviewParser.kt`）。
///
/// 将会话 last_msg 的 (content, msg_type) 转为列表预览文本。
/// msg_type 取值：1=文本 2=图片 5=撤回 6=表情 7/12/13/14=卡片
/// 10=通知 11=视频卡片 18=文本提示。
abstract final class MessagePreviewParser {
  /// 解析会话预览文本。
  static String parseSessionPreview(String? content, int msgType) {
    if (content == null || content.isEmpty) return '';
    return switch (msgType) {
      1 => _parseTextContent(content),
      2 => '[图片]',
      5 => '[消息已撤回]',
      6 => '[表情]',
      7 || 12 || 13 || 14 => _parseCard(content, msgType),
      10 => '[通知]',
      11 => _parseVideoTitle(content),
      18 => _parseTextContent(content),
      _ => '[消息]',
    };
  }

  /// 文本消息：content 可能是裸文本或 `{"content":"..."}` JSON。
  static String _parseTextContent(String content) {
    final trimmed = content.trim();
    if (!trimmed.startsWith('{')) return content;
    final json = _tryJson(trimmed);
    if (json == null) return content;
    return (json['content']?.toString())?.isNotEmpty == true
        ? json['content'].toString()
        : content;
  }

  /// 卡片消息（7=分享 12=专栏 13=图片卡片 14=异形卡片）。
  static String _parseCard(String content, int msgType) {
    final json = _tryJson(content);
    if (json == null) return '[分享]';
    final kind = switch (msgType) {
      12 => '专栏',
      13 => '图片',
      _ => _shareKind(json['source']),
    };
    final title = _firstStr(json, ['title', 'headline', 'text']);
    return title.isEmpty ? '[$kind]' : '$kind：$title';
  }

  /// 视频卡片：返回 `视频：标题`，失败返回 `[视频]`。
  static String _parseVideoTitle(String content) {
    final json = _tryJson(content);
    if (json == null) return '[视频]';
    final title = _firstStr(json, ['title']);
    final bvid = _firstStr(json, ['bvid']);
    if (title.isEmpty && bvid.isEmpty) return '[视频]';
    return '视频：${title.isEmpty ? bvid : title}';
  }

  static String _shareKind(Object? source) {
    final s = source is int
        ? source
        : source is String
            ? int.tryParse(source)
            : null;
    return switch (s) {
      4 => '直播',
      5 => '视频',
      6 => '专栏',
      7 || 16 || 17 => '番剧',
      11 => '动态',
      _ => '分享',
    };
  }

  static Map<String, dynamic>? _tryJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  static String _firstStr(Map json, List<String> keys) {
    for (final k in keys) {
      final v = json[k];
      if (v != null && v.toString().isNotEmpty) return v.toString();
    }
    return '';
  }
}
