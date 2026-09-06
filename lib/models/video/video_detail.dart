// 注意：VideoDetailData 有名为 `dynamic` 的字段，会在类作用域内遮蔽
// 内建类型 `dynamic`，故此处用 typedef 避免在类内书写 Map<String, dynamic>。
typedef _Json = Map<String, dynamic>;

/// 视频详情（`/x/web-interface/view`）简化模型。
///
/// fromJson 对缺省字段保持容忍，所有字段均可为 null。
class VideoDetailData {
  String? bvid;
  int? aid;
  int? cid;
  String? title;
  String? desc;
  String? pic;

  /// 发布时间（Unix 时间戳，秒）
  int? pubdate;

  /// 视频总时长（秒）
  int? duration;

  /// up 发布时填写的动态/简介文案
  String? dynamic;

  VideoOwner? owner;
  VideoStat? stat;
  List<VideoPage>? pages;

  /// 当前登录用户对该稿件的互动状态（仅登录态返回）。
  VideoReqUser? reqUser;

  VideoDetailData.fromJson(Map<String, Object?> json) {
    bvid = json['bvid'] as String?;
    aid = _asInt(json['aid']);
    cid = _asInt(json['cid']);
    title = json['title'] as String?;
    desc = json['desc'] as String?;
    pic = json['pic'] as String?;
    pubdate = _asInt(json['pubdate']);
    duration = _asInt(json['duration']);
    dynamic = json['dynamic'] as String?;
    final ownerJson = json['owner'];
    owner = ownerJson is _Json ? VideoOwner.fromJson(ownerJson) : null;
    final statJson = json['stat'];
    stat = statJson is _Json ? VideoStat.fromJson(statJson) : null;
    pages = (json['pages'] as List?)
        ?.map((e) => VideoPage.fromJson(e as _Json))
        .toList();
    final reqUserJson = json['req_user'];
    reqUser = reqUserJson is _Json
        ? VideoReqUser.fromJson(reqUserJson)
        : null;
  }
}

/// 当前登录用户对稿件的互动状态（`req_user`，对标 BiliPai
/// VideoInteractionUseCase.checkInteractionStatus 的初始态来源）。
class VideoReqUser {
  /// 是否已收藏
  bool? favorite;

  /// 是否已点赞
  bool? like;

  /// 已投币数量
  int? coin;

  /// 是否已关注UP主（0=未关注 1=已关注）
  int? follow;

  VideoReqUser.fromJson(Map<String, dynamic> json) {
    favorite = json['favorite'] == true;
    like = json['like'] == true;
    coin = _asInt(json['coin']);
    follow = _asInt(json['follow']);
  }
}

class VideoOwner {
  int? mid;
  String? name;
  String? face;

  VideoOwner.fromJson(Map<String, dynamic> json) {
    mid = _asInt(json['mid']);
    name = json['name'] as String?;
    face = json['face'] as String?;
  }
}

class VideoStat {
  int? view;
  int? danmaku;
  int? like;
  int? coin;
  int? favorite;
  int? reply;
  int? share;
  int? follow;

  VideoStat({
    this.view,
    this.danmaku,
    this.like,
    this.coin,
    this.favorite,
    this.reply,
    this.share,
    this.follow,
  });

  VideoStat.fromJson(Map<String, dynamic> json) {
    view = _asInt(json['view']);
    danmaku = _asInt(json['danmaku']);
    like = _asInt(json['like']);
    coin = _asInt(json['coin']);
    favorite = _asInt(json['favorite']);
    reply = _asInt(json['reply']);
    share = _asInt(json['share']);
    follow = _asInt(json['follow']);
  }
}

/// 分P信息
class VideoPage {
  int? cid;
  int? page;
  String? part;

  /// 该分P时长（秒）
  int? duration;

  VideoPage.fromJson(Map<String, dynamic> json) {
    cid = _asInt(json['cid']);
    page = _asInt(json['page']);
    part = json['part'] as String?;
    duration = _asInt(json['duration']);
  }
}

class VideoDetailResponse {
  int? code;
  String? message;
  VideoDetailData? data;

  VideoDetailResponse.fromJson(Map<String, dynamic> json) {
    code = _asInt(json['code']);
    message = json['message'] as String?;
    final dataJson = json['data'];
    data = dataJson is Map<String, dynamic>
        ? VideoDetailData.fromJson(dataJson)
        : null;
  }
}

/// 一键三连结果（`/x/web-interface/archive/like/triple`）。
class UgcTriple {
  bool like;
  bool coin;
  bool fav;

  /// 实际投币数（三连为 2）
  int multiply;

  UgcTriple({
    this.like = false,
    this.coin = false,
    this.fav = false,
    this.multiply = 0,
  });

  bool get allSuccess => like && coin && fav;

  UgcTriple.fromJson(Map<String, dynamic> json)
    : like = json['like'] == true,
      coin = json['coin'] == true,
      fav = json['fav'] == true || json['favorite'] == true,
      multiply = _asInt(json['multiply']) ?? 0;
}

/// 数字字段容忍解析：int/num/数字字符串均可。
int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}
