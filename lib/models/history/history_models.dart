/// 历史记录数据模型（对应 `/x/web-interface/history/cursor`）。
///
/// 移植自 PiliPlus `lib/models_new/history/`，精简为 WinWin 所需字段。
class HistoryData {
  List<HistoryTab>? tab;
  List<HistoryItem>? list;

  HistoryData({this.tab, this.list});

  factory HistoryData.fromJson(Map<String, dynamic> json) => HistoryData(
        tab: (json['tab'] as List<dynamic>?)
            ?.map((e) => HistoryTab.fromJson(e as Map<String, dynamic>))
            .toList(),
        list: (json['list'] as List<dynamic>?)
            ?.map((e) => HistoryItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// 历史分类 Tab（archive/live/article...）。
class HistoryTab {
  String? type;
  String? name;

  HistoryTab({this.type, this.name});

  factory HistoryTab.fromJson(Map<String, dynamic> json) => HistoryTab(
        type: json['type'] as String?,
        name: json['name'] as String?,
      );
}

/// 单条历史记录。
class HistoryItem {
  String? title;
  String? cover;
  List<String>? covers;
  String? uri;
  late History history;
  int? videos;
  String? authorName;
  int? authorMid;
  int? viewAt;
  int? progress;
  String? badge;
  String? showTitle;
  int? duration;
  int? isFav;
  int? kid;
  String? tagName;
  int? liveStatus;

  HistoryItem();

  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    final item = HistoryItem()
      ..title = json['title'] as String?
      ..cover = json['cover'] as String?
      ..covers = (json['covers'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList()
      ..uri = json['uri'] as String?
      ..history = History.fromJson(json['history'] as Map<String, dynamic>)
      ..videos = json['videos'] as int?
      ..authorName = json['author_name'] as String?
      ..authorMid = json['author_mid'] as int?
      ..viewAt = json['view_at'] as int?
      ..progress = json['progress'] as int?
      ..badge = json['badge'] as String?
      ..showTitle = json['show_title'] as String?
      ..duration = json['duration'] as int?
      ..isFav = json['is_fav'] as int?
      ..kid = json['kid'] as int?
      ..tagName = json['tag_name'] as String?
      ..liveStatus = json['live_status'] as int?;
    return item;
  }

  /// 播放进度（毫秒），-1 表示已看完 → 重置为 0。
  int? get playbackProgress {
    final p = progress;
    if (p == null) return null;
    return p == -1 ? 0 : p * Duration.millisecondsPerSecond;
  }

  /// 删除时拼接的 kid：`business_kid`。
  String get delKid => '${history.business}_${kid}';
}

/// 历史记录跳转信息。
class History {
  int? oid;
  int? epid;
  String? bvid;
  int? page;
  int? cid;
  String? business;

  History({this.oid, this.epid, this.bvid, this.page, this.cid, this.business});

  factory History.fromJson(Map<String, dynamic> json) => History(
        oid: json['oid'] as int?,
        epid: json['epid'] as int?,
        bvid: json['bvid'] as String?,
        page: json['page'] as int?,
        cid: json['cid'] == 0 ? null : json['cid'] as int?,
        business: json['business'] as String?,
      );
}
