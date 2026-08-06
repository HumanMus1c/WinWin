/// 搜索结果数据模型。
///
/// 移植自 PiliPlus 的 `models/search/result.dart`，精简为桌面端需要的字段。
/// 去除了 Em 高亮解析（改为纯文本），保留视频/用户/直播/番剧/专栏五大类。

/// 搜索结果基类。
abstract class SearchNumData<T> {
  int? numResults;
  List<T>? list;

  SearchNumData({this.numResults, this.list});
}

/// 解析时长字符串（如 "12:34"）为秒数。
int _parseDuration(dynamic duration) {
  if (duration == null) return 0;
  final str = duration.toString();
  final parts = str.split(':');
  if (parts.length == 2) {
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }
  if (parts.length == 3) {
    return (int.tryParse(parts[0]) ?? 0) * 3600 +
        (int.tryParse(parts[1]) ?? 0) * 60 +
        (int.tryParse(parts[2]) ?? 0);
  }
  return int.tryParse(str) ?? 0;
}

// ─────────────────────────── 视频 ───────────────────────────

class SearchVideoData extends SearchNumData<SearchVideoItemModel> {
  SearchVideoData.fromJson(Map<String, dynamic> json) {
    numResults = _asInt(json['numResults']);
    list = (json['result'] as List?)
        ?.map((e) => SearchVideoItemModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

class SearchVideoItemModel {
  int? aid;
  String? bvid;
  String? title;
  String? desc;
  String? cover;
  int? pubdate;
  int? duration;
  String? author;
  int? mid;
  String? face;
  int? play;
  int? danmaku;
  int? like;
  int? favorite;
  int? reply;
  String? badge;
  bool isLive = false;
  int? roomId;

  SearchVideoItemModel.fromJson(Map<String, dynamic> json) {
    aid = _asInt(json['aid']);
    bvid = json['bvid'] as String?;
    title = _stripEm(json['title']);
    desc = json['description'] as String?;
    cover = _http2https(json['pic'] as String?);
    pubdate = _asInt(json['pubdate']);
    duration = _parseDuration(json['duration']);
    author = json['author'] as String?;
    mid = _asInt(json['mid']);
    face = _http2https(json['upic'] as String?);
    play = _asInt(json['play']);
    danmaku = _asInt(json['danmaku']);
    like = _asInt(json['like']);
    favorite = _asInt(json['favorite']);
    reply = _asInt(json['review']);
    switch (json['type']) {
      case 'ketang':
        badge = '课堂';
      case 'live_room':
        badge = '直播';
        isLive = true;
        roomId = _asInt(json['roomid']);
      default:
        if (json['is_union_video'] == 1) badge = '合作';
    }
  }
}

// ─────────────────────────── 用户 ───────────────────────────

class SearchUserData extends SearchNumData<SearchUserItemModel> {
  SearchUserData.fromJson(Map<String, dynamic> json) {
    numResults = _asInt(json['numResults']);
    list = (json['result'] as List?)
        ?.map((e) => SearchUserItemModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

class SearchUserItemModel {
  int? mid;
  String? uname;
  String? usign;
  int? fans;
  int? videos;
  String? upic;
  String? verifyInfo;
  int? level;
  int? isUpUser;
  int? isLive;
  int? roomId;
  int? isSeniorMember;

  SearchUserItemModel.fromJson(Map<String, dynamic> json)
      : mid = _asInt(json['mid']),
        uname = json['uname'] as String?,
        usign = json['usign'] as String?,
        fans = _asInt(json['fans']),
        videos = _asInt(json['videos']),
        upic = _http2https(json['upic'] as String?),
        verifyInfo = json['verify_info'] as String?,
        level = _asInt(json['level']),
        isUpUser = _asInt(json['is_upuser']),
        isLive = _asInt(json['is_live']),
        roomId = _asInt(json['room_id']),
        isSeniorMember = _asInt(json['is_senior_member']);
}

// ─────────────────────────── 直播 ───────────────────────────

class SearchLiveData extends SearchNumData<SearchLiveItemModel> {
  SearchLiveData.fromJson(Map<String, dynamic> json) {
    numResults = _asInt(json['numResults']);
    list = (json['result'] as List?)
        ?.map((e) => SearchLiveItemModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

class SearchLiveItemModel {
  int? uid;
  String? uname;
  String? uface;
  String? title;
  String? cover;
  int? online;
  int? roomid;
  String? cateName;
  String? tags;

  SearchLiveItemModel.fromJson(Map<String, dynamic> json)
      : uid = _asInt(json['uid']),
        uname = json['uname'] as String?,
        uface = _http2https(json['uface'] as String?),
        title = _stripEm(json['title']),
        cover = json['cover'] as String?,
        online = _asInt(json['online']),
        roomid = _asInt(json['roomid']),
        cateName = json['cate_name'] as String?,
        tags = json['tags'] as String?;
}

// ─────────────────────────── 番剧/影视 ───────────────────────────

class SearchPgcData extends SearchNumData<SearchPgcItemModel> {
  SearchPgcData.fromJson(Map<String, dynamic> json) {
    numResults = _asInt(json['numResults']);
    list = (json['result'] as List?)
        ?.map((e) => SearchPgcItemModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

class SearchPgcItemModel {
  int? mediaId;
  String? title;
  String? orgTitle;
  int? mediaType;
  String? cv;
  String? staff;
  int? seasonId;
  int? seasonType;
  String? seasonTypeName;
  String? cover;
  String? areas;
  String? styles;
  String? desc;
  int? pubtime;
  String? indexShow;
  String? buttonText;

  SearchPgcItemModel.fromJson(Map<String, dynamic> json)
      : mediaId = _asInt(json['media_id']),
        title = _stripEm(json['title']),
        orgTitle = json['org_title'] as String?,
        mediaType = _asInt(json['media_type']),
        cv = json['cv'] as String?,
        staff = json['staff'] as String?,
        seasonId = _asInt(json['season_id']),
        seasonType = _asInt(json['season_type']),
        seasonTypeName = json['season_type_name'] as String?,
        cover = json['cover'] as String?,
        areas = json['areas'] as String?,
        styles = json['styles'] as String?,
        desc = json['desc'] as String?,
        pubtime = _asInt(json['pubtime']),
        indexShow = json['index_show'] as String?,
        buttonText = json['button_text'] as String?;
}

// ─────────────────────────── 专栏 ───────────────────────────

class SearchArticleData extends SearchNumData<SearchArticleItemModel> {
  SearchArticleData.fromJson(Map<String, dynamic> json) {
    numResults = _asInt(json['numResults']);
    list = (json['result'] as List?)
        ?.map((e) => SearchArticleItemModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

class SearchArticleItemModel {
  int? id;
  String? title;
  String? desc;
  int? mid;
  String? categoryName;
  int? view;
  int? reply;
  int? like;
  int? pubTime;
  List<String>? imageUrls;

  SearchArticleItemModel.fromJson(Map<String, dynamic> json)
      : id = _asInt(json['id']),
        title = _stripEm(json['title']),
        desc = json['desc'] as String?,
        mid = _asInt(json['mid']),
        categoryName = json['category_name'] as String?,
        view = _asInt(json['view']),
        reply = _asInt(json['reply']),
        like = _asInt(json['like']),
        pubTime = _asInt(json['pub_time']),
        imageUrls = (json['image_urls'] as List?)
            ?.map((e) => e as String)
            .toList();
}

// ─────────────────────────── 热搜 ───────────────────────────

class SearchTrendingItemModel {
  final String? keyword;
  final String? icon;
  final String? recommendReason;

  SearchTrendingItemModel({this.keyword, this.icon, this.recommendReason});

  SearchTrendingItemModel.fromJson(Map<String, dynamic> json)
      : keyword = json['keyword'] as String?,
        icon = json['icon'] as String?,
        recommendReason = (json['recommend_reason'] as String?)?.replaceFirst('·', ' ');
}

class SearchTrendingData {
  final List<SearchTrendingItemModel>? list;

  SearchTrendingData({this.list});

  SearchTrendingData.fromJson(Map<String, dynamic> json)
      : list = (json['list'] as List?)
            ?.map((e) =>
                SearchTrendingItemModel.fromJson(e as Map<String, dynamic>))
            .toList();
}

// ─────────────────────────── 辅助函数 ───────────────────────────

/// 去除搜索结果中的 <em>高亮</em> 标签，返回纯文本。
String? _stripEm(dynamic title) {
  if (title == null) return null;
  return title
      .toString()
      .replaceAll('<em class="keyword">', '')
      .replaceAll('</em>', '');
}

/// http 协议封面图升级为 https。
String? _http2https(String? url) {
  if (url == null || url.isEmpty) return null;
  if (url.startsWith('//')) return 'https:$url';
  if (url.startsWith('http://')) return 'https://${url.substring(7)}';
  return url;
}

/// 数字字段容忍解析。
int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}
