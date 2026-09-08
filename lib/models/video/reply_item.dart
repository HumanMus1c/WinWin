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
          member: json['member'] is Map<String, dynamic>
              ? ReplyMember.fromJson(json['member'])
              : null,
          content: json['content'] is Map<String, dynamic>
              ? ReplyContent.fromJson(json['content'])
              : null,
          like: _asInt(json['like']),
          ctime: _asInt(json['ctime']),
          rcount: _asInt(json['rcount']),
          action: _asInt(json['action'] ?? json['reply_control']?['action']) ?? 0,
          upAction: json['up_action'] is Map<String, dynamic>
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
    level = _asInt(json['level_info']?['current_level'] ?? json['level']);
  }
}

class ReplyContent {
  String? message;

  ReplyContent.fromJson(Map<String, dynamic> json) {
    message = json['message'] as String?;
  }
}

class ReplyCursor {
  bool? isEnd;

  /// 下一页偏移（next_offset，字符串）
  String? nextOffset;

  ReplyCursor.fromJson(Map<String, dynamic> json) {
    isEnd = (json['is_end'] ?? json['isEnd']) as bool?;
    nextOffset = json['next_offset']?.toString();
  }
}

class ReplyMainData {
  final List<ReplyItemModel> replies;
  ReplyCursor? cursor;

  ReplyMainData.fromJson(Map<String, dynamic> json)
      : replies = (json['replies'] as List?)
            ?.map((e) => ReplyItemModel.fromJson(e as Map<String, dynamic>))
            .toList() ??
            <ReplyItemModel>[] {
    final cursorJson = json['cursor'];
    cursor = cursorJson is Map<String, dynamic>
        ? ReplyCursor.fromJson(cursorJson)
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
