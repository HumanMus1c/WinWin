/// 稿件与当前用户的互动/关系状态（`/x/web-interface/archive/relation`）。
class VideoRelationModel {
  /// 是否已点赞
  final bool like;

  /// 是否已点踩
  final bool dislike;

  /// 已投硬币数量（0, 1, 2）
  final int coin;

  /// 是否已收藏
  final bool favorite;

  /// 合集是否已收藏
  final bool seasonFav;

  /// 是否已关注稿件作者
  final bool attention;

  const VideoRelationModel({
    this.like = false,
    this.dislike = false,
    this.coin = 0,
    this.favorite = false,
    this.seasonFav = false,
    this.attention = false,
  });

  factory VideoRelationModel.fromJson(Map<String, dynamic> json) {
    return VideoRelationModel(
      like: _asBool(json['like']),
      dislike: _asBool(json['dislike']),
      coin: _asInt(json['coin']) ?? 0,
      favorite: _asBool(json['favorite']),
      seasonFav: _asBool(json['season_fav']),
      attention: _asBool(json['attention']),
    );
  }

  VideoRelationModel copyWith({
    bool? like,
    bool? dislike,
    int? coin,
    bool? favorite,
    bool? seasonFav,
    bool? attention,
  }) {
    return VideoRelationModel(
      like: like ?? this.like,
      dislike: dislike ?? this.dislike,
      coin: coin ?? this.coin,
      favorite: favorite ?? this.favorite,
      seasonFav: seasonFav ?? this.seasonFav,
      attention: attention ?? this.attention,
    );
  }
}

bool _asBool(Object? value) {
  if (value == null) return false;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final str = value.toString().toLowerCase().trim();
  return str == 'true' || str == '1';
}

int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}
