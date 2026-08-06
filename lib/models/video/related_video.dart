/// 相关视频条目（`/x/web-interface/archive/related`）。
class RelatedVideoItem {
  String? bvid;
  int? aid;
  String? pic;
  String? title;

  /// 发布时间（Unix 时间戳，秒）
  int? pubdate;

  /// 时长（秒）。接口可能返回 int 秒，也可能返回 "mm:ss"/"hh:mm:ss" 字符串。
  int? duration;

  RelatedVideoOwner? owner;
  RelatedVideoStat? stat;

  RelatedVideoItem.fromJson(Map<String, dynamic> json) {
    bvid = json['bvid'] as String?;
    aid = _asInt(json['aid']);
    pic = json['pic'] as String?;
    title = json['title'] as String?;
    pubdate = _asInt(json['pubdate']);
    duration = _parseDuration(json['duration']);
    final ownerJson = json['owner'];
    owner = ownerJson is Map<String, dynamic>
        ? RelatedVideoOwner.fromJson(ownerJson)
        : null;
    final statJson = json['stat'];
    stat = statJson is Map<String, dynamic>
        ? RelatedVideoStat.fromJson(statJson)
        : null;
  }
}

class RelatedVideoOwner {
  int? mid;
  String? name;
  String? face;

  RelatedVideoOwner.fromJson(Map<String, dynamic> json) {
    mid = _asInt(json['mid']);
    name = json['name'] as String?;
    face = json['face'] as String?;
  }
}

class RelatedVideoStat {
  int? view;
  int? danmaku;

  RelatedVideoStat.fromJson(Map<String, dynamic> json) {
    view = _asInt(json['view']);
    danmaku = _asInt(json['danmaku']);
  }
}

/// 数字字段容忍解析：int/num/数字字符串均可。
int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

/// 时长兼容解析：既接受 int 秒（或数字字符串），
/// 也接受 "mm:ss"/"hh:mm:ss" 形式的字符串。
int? _parseDuration(Object? value) {
  final seconds = _asInt(value);
  if (seconds != null) return seconds;
  final text = value?.toString().trim() ?? '';
  if (!text.contains(':')) return null;
  int result = 0;
  for (final part in text.split(':')) {
    final v = int.tryParse(part);
    if (v == null) return null;
    result = result * 60 + v;
  }
  return result;
}
