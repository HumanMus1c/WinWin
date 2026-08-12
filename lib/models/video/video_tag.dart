/// 稿件标签模型（对应 `/x/tag/archive/tags`）。
///
/// 对标 BiliPai `data/model/response/VideoDetailResponse.kt` 的 VideoTag，
/// 仅保留 WinWin 使用的字段。
class VideoTag {
  final int? tagId;
  final String? tagName;
  final String? cover;
  final String? content;
  final String? shortContent;
  final int? type;
  final int? state;

  const VideoTag({
    this.tagId,
    this.tagName,
    this.cover,
    this.content,
    this.shortContent,
    this.type,
    this.state,
  });

  factory VideoTag.fromJson(Map<String, dynamic> json) => VideoTag(
        tagId: json['tag_id'] as int?,
        tagName: json['tag_name'] as String?,
        cover: json['cover'] as String?,
        content: json['content'] as String?,
        shortContent: json['short_content'] as String?,
        type: json['type'] as int?,
        state: json['state'] as int?,
      );
}
