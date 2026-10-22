/// 历史记录数据模型（对应 `/x/web-interface/history/cursor`）。
///
/// 移植自 PiliPlus `lib/models_new/history/`，精简为 WinWin 所需字段。
class HistoryData {
  HistoryCursor? cursor;
  List<HistoryTab>? tab;
  List<HistoryItem>? list;

  HistoryData({this.cursor, this.tab, this.list});

  factory HistoryData.fromJson(Map<String, dynamic> json) => HistoryData(
        cursor: json['cursor'] is Map<String, dynamic>
            ? HistoryCursor.fromJson(json['cursor'] as Map<String, dynamic>)
            : null,
        tab: (json['tab'] as List<dynamic>?)
            ?.map((e) => HistoryTab.fromJson(e as Map<String, dynamic>))
            .toList(),
        list: (json['list'] as List<dynamic>?)
            ?.map((e) => HistoryItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// 历史游标（分页）。
class HistoryCursor {
  int? max;
  int? viewAt;
  String? business;
  int? ps;

  HistoryCursor({this.max, this.viewAt, this.business, this.ps});

  factory HistoryCursor.fromJson(Map<String, dynamic> json) => HistoryCursor(
        max: _asInt(json['max']),
        viewAt: _asInt(json['view_at']),
        business: json['business'] as String?,
        ps: _asInt(json['ps']),
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
  dynamic kid;
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
      ..videos = _asInt(json['videos'])
      ..authorName = json['author_name'] as String?
      ..authorMid = _asInt(json['author_mid'])
      ..viewAt = _asInt(json['view_at'])
      ..progress = _asInt(json['progress'])
      ..badge = json['badge'] as String?
      ..showTitle = json['show_title'] as String?
      ..duration = _asInt(json['duration'])
      ..isFav = _asInt(json['is_fav'])
      ..kid = json['kid']
      ..tagName = json['tag_name'] as String?
      ..liveStatus = _asInt(json['live_status']);
    return item;
  }

  /// 播放进度（毫秒），-1 表示已看完 → 重置为 0。
  int? get playbackProgress {
    final p = progress;
    if (p == null) return null;
    return p == -1 ? 0 : p * Duration.millisecondsPerSecond;
  }

  /// 删除时拼接的 kid：`business_kid`。
  String get delKid {
    final k = kid?.toString() ?? history.oid?.toString() ?? '';
    if (k.contains('_')) return k;
    final b = history.business ?? 'archive';
    return '${b}_$k';
  }

  /// 展示用封面 URL（卡片封面 / 跳转页入参的唯一取值口径）。
  ///
  /// 服务端 `cover` 字段仅用于**专栏以外的条目**；专栏（article / article-list）
  /// 条目的封面只在 `covers`（图组，数组）中下发，`cover` 恒为空。故此处统一回退
  /// 取 `covers` 首图，否则专栏分类的卡片封面会一直停在占位（对齐上游 PiliPlus
  /// history item：`cover?.isNotEmpty == true ? cover : covers?.firstOrNull`）。
  String? get coverUrl {
    if (cover?.isNotEmpty == true) return cover;
    if (covers?.isNotEmpty == true) return covers!.first;
    return null;
  }
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

int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}
