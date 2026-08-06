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

  ReplyItemModel.fromJson(Map<String, dynamic> json) {
    rpid = _asInt(json['rpid']);
    mid = _asInt(json['mid']);
    final memberJson = json['member'];
    member = memberJson is Map<String, dynamic>
        ? ReplyMember.fromJson(memberJson)
        : null;
    final contentJson = json['content'];
    content = contentJson is Map<String, dynamic>
        ? ReplyContent.fromJson(contentJson)
        : null;
    like = _asInt(json['like']);
    ctime = _asInt(json['ctime']);
    rcount = _asInt(json['rcount']);
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
