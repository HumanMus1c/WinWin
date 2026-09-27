/// 评论（web 端 `/x/v2/reply/main`）简化模型。
class ReplyItemModel {
  int? rpid;

  /// 评论者 mid（与 member.mid 等效，接口顶层字段）
  int? mid;
  ReplyMember? member;
  ReplyContent? content;
  int? like;

  /// 发布时间（Unix 时间戳，秒）
  int? ctime;

  /// 楼中楼回复数
  int? rcount;

  /// 点赞状态：0=未操作，1=已点赞，2=已点踩。
  /// B 站评论接口返回顶层 action，同时兼容容错 reply_control.action。
  int? action;

  /// UP 主互动标记（UP 主点赞/UP 主回复）。
  ReplyUpAction? upAction;

  ReplyItemModel({
    this.rpid,
    this.mid,
    this.member,
    this.content,
    this.like,
    this.ctime,
    this.rcount,
    this.action,
    this.upAction,
  });

  ReplyItemModel.fromJson(Map<String, dynamic> json)
      : this(
          rpid: _asInt(json['rpid']),
          mid: _asInt(json['mid']),
          member: json['member'] is Map
              ? ReplyMember.fromJson((json['member'] as Map).cast<String, dynamic>())
              : null,
          content: json['content'] is Map
              ? ReplyContent.fromJson((json['content'] as Map).cast<String, dynamic>())
              : null,
          like: _asInt(json['like']),
          ctime: _asInt(json['ctime']),
          rcount: _asInt(json['rcount']),
          action: _asInt(json['action'] ??
                  (json['reply_control'] is Map
                      ? (json['reply_control'] as Map)['action']
                      : null)) ??
              0,
          upAction: json['up_action'] is Map
              ? ReplyUpAction.fromJson(
                  (json['up_action'] as Map).cast<String, dynamic>(),
                )
              : null,
        );

  /// 是否已点赞。
  bool get isLiked => action == 1;

  /// 是否已点踩。
  bool get isDisliked => action == 2;

  ReplyItemModel copyWith({
    int? like,
    int? action,
    ReplyUpAction? upAction,
  }) =>
      ReplyItemModel(
        rpid: rpid,
        mid: mid,
        member: member,
        content: content,
        like: like ?? this.like,
        ctime: ctime,
        rcount: rcount,
        action: action ?? this.action,
        upAction: upAction ?? this.upAction,
      );
}

/// UP 主对评论的互动标记（点赞/回复）。
class ReplyUpAction {
  final bool like;
  final bool reply;

  const ReplyUpAction({this.like = false, this.reply = false});

  factory ReplyUpAction.fromJson(Map<String, dynamic> json) {
    return ReplyUpAction(
      like: json['like'] == true || json['like'] == 1,
      reply: json['reply'] == true || json['reply'] == 1,
    );
  }
}

class ReplyMember {
  /// 接口返回的是字符串形式的 mid
  int? mid;
  String? uname;
  String? avatar;
  String? sex;

  /// 用户等级（位于 member.level_info.current_level）
  int? level;

  ReplyMember.fromJson(Map<String, dynamic> json) {
    mid = _asInt(json['mid']);
    uname = json['uname'] as String?;
    avatar = json['avatar'] as String?;
    sex = json['sex'] as String?;
    level = _asInt(json['level_info'] is Map
        ? (json['level_info'] as Map)['current_level']
        : json['level']);
  }
}

class ReplyContent {
  String? message;

  /// 评论正文表情转义映射（键为 `[xxx]` 表情代码，评论无表情则不下发）。
  Map<String, ReplyEmote>? emote;

  /// 评论附带图片列表（含 GIF 动图）。
  List<ReplyPicture>? pictures;

  /// 图片展示倍率（1.5 表示大图模式）。
  double? pictureScale;

  ReplyContent.fromJson(Map<String, dynamic> json) {
    message = json['message']?.toString();

    final emoteJson = json['emote'];
    if (emoteJson is Map && emoteJson.isNotEmpty) {
      final emoteMap = <String, ReplyEmote>{};
      emoteJson.forEach((key, value) {
        if (value is Map) {
          emoteMap[key.toString()] =
              ReplyEmote.fromJson(value.cast<String, dynamic>());
        }
      });
      if (emoteMap.isNotEmpty) emote = emoteMap;
    }

    final picturesJson = json['pictures'];
    if (picturesJson is List && picturesJson.isNotEmpty) {
      final picList = picturesJson
          .whereType<Map>()
          .map((e) => ReplyPicture.fromJson(e.cast<String, dynamic>()))
          .where((p) => p.imgSrc?.isNotEmpty == true)
          .toList();
      if (picList.isNotEmpty) pictures = picList;
    }

    final scale = json['picture_scale'];
    pictureScale = scale is num ? scale.toDouble() : null;
  }
}

/// 评论正文表情（`content.emote` 中单个表情代码的渲染信息）。
class ReplyEmote {
  /// 表情转义符（如 `[doge]`）。
  final String? text;

  /// 静态表情图 URL。
  final String? url;

  /// 动图版本 URL（部分表情下发，优先使用）。
  final String? gifUrl;

  /// 表情尺寸档位（meta.size：1=小，2=大）。
  final int size;

  const ReplyEmote({
    this.text,
    this.url,
    this.gifUrl,
    this.size = 1,
  });

  factory ReplyEmote.fromJson(Map<String, dynamic> json) {
    final meta = json['meta'];
    return ReplyEmote(
      text: json['text']?.toString(),
      url: json['url']?.toString(),
      gifUrl: json['gif_url']?.toString(),
      size: _asInt(meta is Map ? meta['size'] : null) ?? 1,
    );
  }

  /// 优先使用动图版本，回退静态图。
  String? get displayUrl => gifUrl?.isNotEmpty == true ? gifUrl : url;
}

/// 评论附带图片（`content.pictures`，含 GIF 动图）。
class ReplyPicture {
  final String? imgSrc;
  final double? imgWidth;
  final double? imgHeight;

  /// 图片体积（KB）。
  final double? imgSize;

  /// 右上角角标图片 URL（如"大专属"标记）。
  final String? topRightIcon;

  /// 是否以动图形式播放缩略图（B 站评论 GIF 标记）。
  final bool playGifThumbnail;

  const ReplyPicture({
    this.imgSrc,
    this.imgWidth,
    this.imgHeight,
    this.imgSize,
    this.topRightIcon,
    this.playGifThumbnail = false,
  });

  factory ReplyPicture.fromJson(Map<String, dynamic> json) => ReplyPicture(
        imgSrc: json['img_src']?.toString(),
        imgWidth: json['img_width'] is num
            ? (json['img_width'] as num).toDouble()
            : null,
        imgHeight: json['img_height'] is num
            ? (json['img_height'] as num).toDouble()
            : null,
        imgSize:
            json['img_size'] is num ? (json['img_size'] as num).toDouble() : null,
        topRightIcon: json['top_right_icon']?.toString(),
        playGifThumbnail: json['play_gif_thumbnail'] == true,
      );
}

class ReplyCursor {
  bool? isEnd;

  /// 下一页偏移（next_offset，字符串）
  String? nextOffset;

  ReplyCursor.fromJson(Map<String, dynamic> json) {
    final rawEnd = json['is_end'] ?? json['isEnd'];
    if (rawEnd is bool) {
      isEnd = rawEnd;
    } else if (rawEnd is num) {
      isEnd = rawEnd != 0;
    }
    final pagination = json['pagination_reply'];
    if (pagination is Map) {
      nextOffset = pagination['next_offset']?.toString();
    } else {
      nextOffset = json['next_offset']?.toString();
    }
  }
}

class ReplyMainData {
  final List<ReplyItemModel> replies;
  ReplyCursor? cursor;

  ReplyMainData.fromJson(Map<String, dynamic> json)
      : replies = (json['replies'] as List?)
            ?.whereType<Map>()
            .map((e) => ReplyItemModel.fromJson(e.cast<String, dynamic>()))
            .toList() ??
            <ReplyItemModel>[] {
    final cursorJson = json['cursor'];
    cursor = cursorJson is Map
        ? ReplyCursor.fromJson(cursorJson.cast<String, dynamic>())
        : null;
  }
}

/// 数字字段容忍解析：int/num/数字字符串均可。
int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}
