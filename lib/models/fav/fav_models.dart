import 'package:winwin/models/common/owner.dart';

/// 收藏夹列表响应（`/x/v3/fav/folder/created/list`）。
class FavFolderData {
  int? count;
  List<FavFolderInfo>? list;
  bool? hasMore;

  FavFolderData({this.count, this.list, this.hasMore});

  factory FavFolderData.fromJson(Map<String, dynamic> json) => FavFolderData(
        count: json['count'] as int?,
        list: (json['list'] as List<dynamic>?)
            ?.map((e) => FavFolderInfo.fromJson(e as Map<String, dynamic>))
            .toList(),
        hasMore: json['has_more'] as bool?,
      );
}

/// 单个收藏夹信息。
///
/// [id] 即 media_id，所有收藏夹操作的主键。
/// [favState] == 1 表示当前视频已收藏到此夹（面板勾选状态）。
class FavFolderInfo {
  int id;
  int? fid;
  int mid;
  int attr;
  String title;
  String cover;
  Owner? upper;
  String? intro;
  int? favState;
  int mediaCount;

  FavFolderInfo({
    this.id = 0,
    this.fid,
    this.mid = 0,
    this.attr = -1,
    this.title = '',
    this.cover = '',
    this.upper,
    this.intro,
    this.favState,
    this.mediaCount = 0,
  });

  factory FavFolderInfo.fromJson(Map<String, dynamic> json) => FavFolderInfo(
        id: json['id'] as int? ?? 0,
        fid: json['fid'] as int?,
        mid: json['mid'] as int? ?? 0,
        attr: json['attr'] as int? ?? 0,
        title: json['title'] as String? ?? '',
        cover: json['cover'] as String? ?? '',
        upper: json['upper'] == null
            ? null
            : Owner.fromJson(json['upper'] as Map<String, dynamic>),
        intro: json['intro'] as String?,
        favState: json['fav_state'] as int?,
        mediaCount: json['media_count'] as int? ?? 0,
      );

  /// attr 第 1 位为 0 表示公开夹。
  bool get isPublic => (attr & 1) == 0;

  /// attr 第 2 位为 1 表示默认收藏夹。
  bool get isDefault => (attr & 2) == 2;
}

/// 收藏夹详情响应（`/x/v3/fav/resource/list`）。
class FavDetailData {
  FavFolderInfo? info;
  List<FavDetailItem>? medias;
  bool? hasMore;

  FavDetailData({this.info, this.medias, this.hasMore});

  factory FavDetailData.fromJson(Map<String, dynamic> json) => FavDetailData(
        info: json['info'] == null
            ? null
            : FavFolderInfo.fromJson(json['info'] as Map<String, dynamic>),
        medias: (json['medias'] as List<dynamic>?)
            ?.map((e) => FavDetailItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        hasMore: json['has_more'] as bool?,
      );
}

/// 收藏夹内视频项。
class FavDetailItem {
  int? id;
  int? type;
  String? title;
  String? cover;
  String? intro;
  int? duration;
  Owner? upper;
  int? attr;
  CntInfo? cntInfo;
  int? favTime;
  String? bvid;
  int? cid;

  FavDetailItem({
    this.id,
    this.type,
    this.title,
    this.cover,
    this.intro,
    this.duration,
    this.upper,
    this.attr,
    this.cntInfo,
    this.favTime,
    this.bvid,
    this.cid,
  });

  factory FavDetailItem.fromJson(Map<String, dynamic> json) => FavDetailItem(
        id: json['id'] as int?,
        type: json['type'] as int?,
        title: json['title'] as String?,
        cover: json['cover'] as String?,
        intro: json['intro'] as String?,
        duration: json['duration'] as int?,
        upper: json['upper'] == null
            ? null
            : Owner.fromJson(json['upper'] as Map<String, dynamic>),
        attr: json['attr'] as int?,
        cntInfo: json['cnt_info'] == null
            ? null
            : CntInfo.fromJson(json['cnt_info'] as Map<String, dynamic>),
        favTime: json['fav_time'] as int?,
        bvid: json['bvid'] ?? json['bv_id'],
        cid: json['ugc']?['first_cid'] as int?,
      );
}

class CntInfo {
  int? play;
  int? danmaku;

  CntInfo({this.play, this.danmaku});

  factory CntInfo.fromJson(Map<String, dynamic> json) => CntInfo(
        play: json['play'] as int?,
        danmaku: json['danmaku'] as int?,
      );
}
