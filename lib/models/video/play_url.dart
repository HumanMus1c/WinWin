/// 播放地址（`/x/player/wbi/playurl`，fnval=4048 DASH）简化模型。
class PlayUrlModel {
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
    quality = json['quality'] as int?;
    acceptQuality = (json['accept_quality'] as List?)
        ?.map((e) => (e as num).toInt())
        .toList();
    acceptDescription = (json['accept_description'] as List?)
        ?.map((e) => e.toString())
        .toList();
    lastPlayTime = json['last_play_time'] as int?;
    format = json['format'] as int?;
    final dashJson = json['dash'];
    dash = dashJson is Map<String, dynamic> ? Dash.fromJson(dashJson) : null;
    durl = (json['durl'] as List?)
        ?.map((e) => Durl.fromJson(e as Map<String, dynamic>))
        .toList();
    supportFormats = (json['support_formats'] as List?)
        ?.map((e) => FormatItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 选择不超过 [maxQn] 的最高清晰度视频轨（B 站 dash video 的 id 即 qn）；
  /// 若不存在满足条件的轨道，则退回最低清晰度轨道。
  DashVideo? pickVideo({int maxQn = 80}) {
    final videos = dash?.video;
    if (videos == null || videos.isEmpty) return null;
    DashVideo? result;
    for (final video in videos) {
      final qn = video.id;
      if (qn == null || qn > maxQn) continue;
      if (result == null || qn > (result.id ?? 0)) {
        result = video;
      }
    }
    if (result != null) return result;
    return videos.reduce((a, b) => (a.id ?? 0) <= (b.id ?? 0) ? a : b);
  }

  /// 选择 bandwidth 最高的音轨。
  DashAudio? pickAudio() {
    final audios = dash?.audio;
    if (audios == null || audios.isEmpty) return null;
    return audios.reduce(
      (a, b) => (b.bandwidth ?? 0) > (a.bandwidth ?? 0) ? b : a,
    );
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
    duration = json['duration'] as int?;
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
    id = json['id'] as int?;
    baseUrl = (json['baseUrl'] ?? json['base_url']) as String?;
    backupUrl = ((json['backupUrl'] ?? json['backup_url']) as List?)
        ?.map((e) => e.toString())
        .toList();
    bandwidth = (json['bandWidth'] ?? json['bandwidth']) as int?;
    width = json['width'] as int?;
    height = json['height'] as int?;
    frameRate = (json['frameRate'] ?? json['frame_rate'])?.toString();
    codecid = json['codecid'] as int?;
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
    id = json['id'] as int?;
    baseUrl = (json['baseUrl'] ?? json['base_url']) as String?;
    backupUrl = ((json['backupUrl'] ?? json['backup_url']) as List?)
        ?.map((e) => e.toString())
        .toList();
    bandwidth = (json['bandWidth'] ?? json['bandwidth']) as int?;
    codecid = json['codecid'] as int?;
    frameRate = (json['frameRate'] ?? json['frame_rate'])?.toString();
    width = json['width'] as int?;
    height = json['height'] as int?;
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
      order: json['order'] as int?,
      url: json['url'] as String?,
      length: json['length'] as int?,
      size: json['size'] as int?,
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
      quality: json['quality'] as int?,
      newDescription: json['new_description'] as String?,
      description: json['description'] as String?,
      format: json['format'] as String?,
    );
  }
}
