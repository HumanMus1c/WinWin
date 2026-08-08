// PlayInfo 模型 — `/x/player/wbi/v2` 响应。
//
// 该接口一次返回多项数据，服务多个 Phase：
//  - last_play_time / last_play_cid：Phase 4.2 历史进度恢复
//  - subtitle.subtitles：Phase 4.4 字幕列表加载
//  - view_points：Phase 4.5 章节标记
//
// 仅保留 WinWin 实际使用的字段，其余字段忽略。

/// `/x/player/wbi/v2` 响应数据。
class PlayInfoModel {
  /// 上次播放时间（unix 秒），0 表示无记录。
  final int lastPlayTime;
  /// 上次播放的 cid。
  final int? lastPlayCid;
  /// 章节标记列表（view_points）。
  final List<ViewPoint> viewPoints;
  /// 字幕信息。
  final SubtitleInfo? subtitle;

  const PlayInfoModel({
    required this.lastPlayTime,
    this.lastPlayCid,
    this.viewPoints = const [],
    this.subtitle,
  });

  factory PlayInfoModel.fromJson(Map<String, dynamic> json) {
    final viewPointsJson = json['view_points'];
    final subtitleJson = json['subtitle'];
    return PlayInfoModel(
      lastPlayTime: _asInt(json['last_play_time']) ?? 0,
      lastPlayCid: _asInt(json['last_play_cid']),
      viewPoints: viewPointsJson is List
          ? viewPointsJson
              .whereType<Map>()
              .map((e) => ViewPoint.fromJson(e.cast<String, dynamic>()))
              .where((v) => v.to > v.from)
              .toList()
          : const [],
      subtitle: subtitleJson is Map
          ? SubtitleInfo.fromJson(subtitleJson.cast<String, dynamic>())
          : null,
    );
  }
}

/// 章节标记（view_points 节点）。
class ViewPoint {
  /// 起始时间（秒）。
  final double from;
  /// 结束时间（秒）。
  final double to;
  /// 章节标题。
  final String title;
  /// 章节类型（如 "chapter"）。
  final String type;

  const ViewPoint({
    required this.from,
    required this.to,
    required this.title,
    required this.type,
  });

  /// 章节时长（秒）。
  double get duration => to - from;

  /// 判断 [positionSec] 是否在章节内。
  bool contains(double positionSec) =>
      positionSec >= from && positionSec < to;

  factory ViewPoint.fromJson(Map<String, dynamic> json) {
    return ViewPoint(
      from: _asDouble(json['from']) ?? 0,
      to: _asDouble(json['to']) ?? 0,
      title: json['title']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
    );
  }
}

/// 字幕信息（subtitle 节点）。
class SubtitleInfo {
  /// 可用字幕列表。
  final List<SubtitleItem> subtitles;

  const SubtitleInfo({this.subtitles = const []});

  factory SubtitleInfo.fromJson(Map<String, dynamic> json) {
    final list = json['subtitles'];
    return SubtitleInfo(
      subtitles: list is List
          ? list
              .whereType<Map>()
              .map((e) => SubtitleItem.fromJson(e.cast<String, dynamic>()))
              .toList()
          : const [],
    );
  }
}

/// 单条字幕信息。
class SubtitleItem {
  /// 字幕 id（用于加载字幕内容）。
  final int id;
  /// 语言代码（如 "zh-CN"）。
  final String lan;
  /// 语言中文名（如 "中文字幕"）。
  final String lanDoc;
  /// 字幕 URL（可能以 // 开头，需补 https:）。
  final String subtitleUrl;
  /// AI 字幕类型（0=非AI，1=AI，2=AI转人工校对）。
  final int aiType;

  const SubtitleItem({
    required this.id,
    required this.lan,
    required this.lanDoc,
    required this.subtitleUrl,
    required this.aiType,
  });

  /// 是否为 AI 生成字幕。
  bool get isAi => aiType > 0;

  /// 补全后的字幕 URL（加 https: 前缀）。
  String get fullUrl {
    if (subtitleUrl.isEmpty) return subtitleUrl;
    if (subtitleUrl.startsWith('http')) return subtitleUrl;
    if (subtitleUrl.startsWith('//')) return 'https:$subtitleUrl';
    return 'https://$subtitleUrl';
  }

  factory SubtitleItem.fromJson(Map<String, dynamic> json) {
    return SubtitleItem(
      id: _asInt(json['id']) ?? 0,
      lan: json['lan']?.toString() ?? '',
      lanDoc: json['lan_doc']?.toString() ?? '',
      subtitleUrl: json['subtitle_url']?.toString() ?? '',
      aiType: _asInt(json['ai_type']) ?? 0,
    );
  }
}

/// VTT/WebVTT 字幕解析后的单条字幕行。
class SubtitleCue {
  /// 起始时间。
  final Duration start;
  /// 结束时间。
  final Duration end;
  /// 字幕文本（可能含多行，用 \n 分隔）。
  final String text;

  const SubtitleCue({required this.start, required this.end, required this.text});

  /// 判断 [position] 是否在字幕时间段内。
  bool contains(Duration position) =>
      position >= start && position < end;

  /// 导出为 SRT 格式行（index 由调用方维护）。
  String toSrt(int index) {
    return '${index + 1}\n'
        '${_formatSrtTime(start)} --> ${_formatSrtTime(end)}\n'
        '$text\n';
  }

  /// 导出为 VTT 格式行。
  String toVtt() {
    return '${_formatVttTime(start)} --> ${_formatVttTime(end)}\n'
        '$text\n';
  }

  static String _formatSrtTime(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    final ms = d.inMilliseconds.remainder(1000);
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')},'
        '${ms.toString().padLeft(3, '0')}';
  }

  static String _formatVttTime(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    final ms = d.inMilliseconds.remainder(1000);
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}.'
        '${ms.toString().padLeft(3, '0')}';
  }
}

int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

double? _asDouble(Object? value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
