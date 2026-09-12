/// 播放地址（`/x/player/wbi/playurl`，fnval=4048 DASH）简化模型。
library;

import 'dart:math';

/// 安全类型转换：B站 API 部分数值字段可能返回 String（如 "1920"），
/// 直接 `as int?` 会抛 type cast 异常。此函数兼容 int / double / String。
int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

class PlayUrlModel {
  /// B站音频响度实测数据（用于 loudnorm 智能均衡）
  Volume? volume;
  /// 当前请求返回的清晰度代码（qn）
  int? quality;
  List<int>? acceptQuality;
  List<String>? acceptDescription;

  /// 上次播放进度（秒）
  int? lastPlayTime;

  /// 返回格式（0=flv/play，1=dash，2=mp4）
  int? format;

  Dash? dash;

  /// DURL 流（非 DASH 时使用，分段 MP4）
  List<Durl>? durl;

  /// 支持的格式列表
  List<FormatItem>? supportFormats;

  PlayUrlModel.fromJson(Map<String, dynamic> json) {
    quality = _asInt(json['quality']);
    acceptQuality = (json['accept_quality'] as List?)
        ?.map((e) => _asInt(e) ?? 0)
        .toList();
    acceptDescription = (json['accept_description'] as List?)
        ?.map((e) => e.toString())
        .toList();
    lastPlayTime = _asInt(json['last_play_time']);
    format = _asInt(json['format']);
    final dashJson = json['dash'];
    dash = dashJson is Map<String, dynamic> ? Dash.fromJson(dashJson) : null;
    durl = (json['durl'] as List?)
        ?.map((e) => Durl.fromJson(e as Map<String, dynamic>))
        .toList();
    final volJson = json['volume'];
    volume = volJson is Map ? Volume.fromJson(Map<String, dynamic>.from(volJson)) : null;
    supportFormats = (json['support_formats'] as List?)
        ?.map((e) => FormatItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

class Dash {
  /// 视频时长（秒）。
  int? duration;

  List<DashVideo>? video;
  List<DashAudio>? audio;

  /// 杜比全景声音轨（可能不存在）
  List<DashAudio>? dolbyAudio;

  Dash.fromJson(Map<String, dynamic> json) {
    duration = _asInt(json['duration']);
    video = (json['video'] as List?)
        ?.map((e) => DashVideo.fromJson(e as Map<String, dynamic>))
        .toList();
    audio = (json['audio'] as List?)
        ?.map((e) => DashAudio.fromJson(e as Map<String, dynamic>))
        .toList();
    dolbyAudio = (json['dolby']?['audio'] as List?)
        ?.map((e) => DashAudio.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

class DashVideo {
  /// 清晰度代码，即 qn（如 64=720P、80=1080P、127=8K）
  int? id;
  String? baseUrl;
  List<String>? backupUrl;
  int? bandwidth;
  int? width;
  int? height;
  String? frameRate;

  /// 编解码器代码（如 7=AVC、12=HEVC、13=AV1）。
  int? codecid;

  /// 编解码器标识（如 "avc1.640032"、"hev1.1.6.L120.B0"、"av01.0.08M.08"）。
  /// 由 [StreamSelectionPolicy] 用于编解码器感知选流评分。
  String? codecs;

  DashVideo.fromJson(Map<String, dynamic> json) {
    id = _asInt(json['id']);
    baseUrl = (json['baseUrl'] ?? json['base_url']) as String?;
    backupUrl = ((json['backupUrl'] ?? json['backup_url']) as List?)
        ?.map((e) => e.toString())
        .toList();
    bandwidth = _asInt(json['bandWidth'] ?? json['bandwidth']);
    width = _asInt(json['width']);
    height = _asInt(json['height']);
    frameRate = (json['frameRate'] ?? json['frame_rate'])?.toString();
    codecid = _asInt(json['codecid']);
    codecs = json['codecs'] as String?;
  }

  /// 该视频轨全部可用 CDN URL（主 + 备用，去空）。
  List<String> get playUrls => [
        if (baseUrl != null && baseUrl!.isNotEmpty) baseUrl!,
        ...?backupUrl,
      ];
}

class DashAudio {
  /// 音质代码（如 30216=64K、30232=128K、30280=192K）
  int? id;
  String? baseUrl;
  List<String>? backupUrl;
  int? bandwidth;
  int? codecid;
  String? frameRate;
  int? width;
  int? height;

  DashAudio.fromJson(Map<String, dynamic> json) {
    id = _asInt(json['id']);
    baseUrl = (json['baseUrl'] ?? json['base_url']) as String?;
    backupUrl = ((json['backupUrl'] ?? json['backup_url']) as List?)
        ?.map((e) => e.toString())
        .toList();
    bandwidth = _asInt(json['bandWidth'] ?? json['bandwidth']);
    codecid = _asInt(json['codecid']);
    frameRate = (json['frameRate'] ?? json['frame_rate'])?.toString();
    width = _asInt(json['width']);
    height = _asInt(json['height']);
  }

  /// 该音轨全部可用 CDN URL（主 + 备用，去空）。
  List<String> get playUrls => [
        if (baseUrl != null && baseUrl!.isNotEmpty) baseUrl!,
        ...?backupUrl,
      ];
}

/// 非 DASH 模式下的分段 MP4 流（durl 节点）。
class Durl {
  /// 分段序号（从 1 开始）。
  final int? order;

  /// 分段直链 URL。
  final String? url;

  /// 分段时长（毫秒）。
  final int? length;

  /// 分段大小（字节）。
  final int? size;

  /// 备用 URL 列表。
  final List<String>? backupUrl;

  Durl({this.order, this.url, this.length, this.size, this.backupUrl});

  factory Durl.fromJson(Map<String, dynamic> json) {
    return Durl(
      order: _asInt(json['order']),
      url: json['url'] as String?,
      length: _asInt(json['length']),
      size: _asInt(json['size']),
      backupUrl: (json['backup_url'] as List?)
          ?.map((e) => e.toString())
          .toList(),
    );
  }

  /// 该分段全部可用 CDN URL（主 + 备用，去空）。
  List<String> get urls => [
        if (url != null && url!.isNotEmpty) url!,
        ...?backupUrl,
      ];

  List<String> get playUrls => urls;
}

/// playurl 返回的 support_formats 节点项。
class FormatItem {
  /// 清晰度代码。
  final int? quality;

  /// 清晰度描述（如 "高清 1080P"）。
  final String? newDescription;

  /// 旧版清晰度描述（如 "1080P"）。
  final String? description;

  /// 显示用格式字符串（如 "1080P 60帧"）。
  final String? format;

  FormatItem({
    this.quality,
    this.newDescription,
    this.description,
    this.format,
  });

  factory FormatItem.fromJson(Map<String, dynamic> json) {
    return FormatItem(
      quality: _asInt(json['quality']),
      newDescription: json['new_description'] as String?,
      description: json['description'] as String?,
      format: json['format'] as String?,
    );
  }
}

/// B 站音频响度测量元数据（对标 PiliPlus Volume）。
///
/// 当 playurl 请求携带 voice_balance=1 时返回，包含视频音频的实测响度数据，
/// 用于构造高精度单动线性 FFmpeg loudnorm 滤镜参数。
class Volume {
  final num measuredI;
  final num measuredLra;
  final num measuredTp;
  final num measuredThreshold;
  final num targetOffset;
  final num targetI;
  final num targetTp;

  static const double minTpValue = -9.0;
  static const double maxTpValue = 0.0;

  Volume({
    required this.measuredI,
    required this.measuredLra,
    required this.measuredTp,
    required this.measuredThreshold,
    required this.targetOffset,
    required this.targetI,
    required this.targetTp,
  });

  factory Volume.fromJson(Map<String, dynamic> json) {
    num asNum(dynamic v) {
      if (v is num) return v;
      if (v is String) return num.tryParse(v) ?? 0;
      return 0;
    }

    return Volume(
      measuredI: asNum(json['measured_i']),
      measuredLra: asNum(json['measured_lra']),
      measuredTp: asNum(json['measured_tp']),
      measuredThreshold: asNum(json['measured_threshold']),
      targetOffset: asNum(json['target_offset']),
      targetI: asNum(json['target_i']),
      targetTp: asNum(json['target_tp']),
    );
  }

  /// 构造单动线性 FFmpeg loudnorm 滤镜字符串（对齐 PiliPlus）。
  String format(Map<String, num> config) {
    final lra = max(config['lra'] ?? 11, measuredLra);
    num i = config['i'] ?? (targetI != 0 ? targetI : -14);
    final tp = min(
      config['tp'] ?? (targetTp != 0 ? targetTp : -1.5),
      measuredTp,
    ).clamp(minTpValue, maxTpValue);
    final offset = config['offset'] ?? targetOffset;
    num measuredI = this.measuredI;
    if (measuredI > 0) {
      i -= measuredI;
      measuredI = 0;
    }
    num measuredThreshold = this.measuredThreshold;
    if (measuredThreshold > 0) {
      measuredThreshold = 0;
    }

    return 'LRA=$lra:I=$i:TP=$tp:offset=$offset:linear=true:measured_I=$measuredI:measured_LRA=$measuredLra:measured_TP=$measuredTp:measured_thresh=$measuredThreshold';
  }

  bool get isNotEmpty =>
      measuredI != 0 ||
      measuredLra != 0 ||
      measuredTp != 0 ||
      measuredThreshold != 0;
}
