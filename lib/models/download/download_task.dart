// 下载任务数据模型（Phase 5 下载系统核心层）。
//
// 对标 BiliPai feature/download/DownloadTask.kt，仅保留 WinWin 桌面端离线
// 下载所需字段；Android 专有的 SAF 导出 URI（exportedFileUri）、分片弹幕段
// 路径（localDanmakuSegmentPaths）等不迁移。
//
// 本文件只含纯数据模型 + JSON 序列化，不含 IO / 网络：
// - 策略逻辑见 lib/core/download/download_policy.dart
// - 持久化见 lib/core/download/download_store.dart

/// 下载任务状态。
///
/// 命名遵循 Dart 约定（lowerCamelCase），与 BiliPai 的 DownloadStatus
/// （QUEUED / PENDING / DOWNLOADING / MERGING / COMPLETED / FAILED / PAUSED）
/// 逐项对应。
enum DownloadStatus {
  /// 已加入队列，等待被调度（并发已满时处于此态）。
  queued,

  /// 已就绪但尚未开始下载。
  pending,

  /// 下载中。
  downloading,

  /// 音视频合并中（DASH 双流路径；DURL 单文件路径不会进入此态）。
  merging,

  /// 已完成。
  completed,

  /// 失败。
  failed,

  /// 已暂停。
  paused;

  /// 由持久化字符串还原；未知 / 空值回退到 [pending]，保证旧数据可用。
  static DownloadStatus fromName(String? name) {
    for (final value in DownloadStatus.values) {
      if (value.name == name) return value;
    }
    return DownloadStatus.pending;
  }
}

/// 下载选项。
class DownloadOptions {
  /// 是否随视频一并下载弹幕（.xml）。
  final bool includeDanmaku;

  const DownloadOptions({this.includeDanmaku = true});

  DownloadOptions copyWith({bool? includeDanmaku}) => DownloadOptions(
        includeDanmaku: includeDanmaku ?? this.includeDanmaku,
      );

  factory DownloadOptions.fromJson(Map<String, dynamic> json) =>
      DownloadOptions(includeDanmaku: _asBool(json['includeDanmaku'], fallback: true));

  Map<String, dynamic> toJson() => <String, dynamic>{
        'includeDanmaku': includeDanmaku,
      };
}

/// 下载画质候选项（供画质选择对话框使用）。
class QualityOption {
  /// 画质 ID（对齐 bilibili qn：32/64/80/112/116/120/125/126/127）。
  final int id;

  /// 画质描述（如 "1080P"）。
  final String desc;

  /// 该画质对应的视频流地址。
  final String videoUrl;

  /// 该画质对应的音频流地址（DURL 单文件路径下为空串）。
  final String audioUrl;

  const QualityOption({
    required this.id,
    required this.desc,
    required this.videoUrl,
    required this.audioUrl,
  });
}

/// 单个离线下载任务。
///
/// [id] 是任务的稳定唯一键：
/// - 普通视频：`{bvid}_{cid}_{quality}`
/// - 仅音频（听视频 / 后台播放）：`{bvid}_{cid}_audio`
///
/// 进度不单独存储，而是由 [downloadedSize] / [fileSize] 派生（单一事实源），
/// 见 [progress]。
class DownloadTask {
  final String bvid;

  /// AV 号（0 表示未知）。
  final int aid;

  final int cid;

  final String title;

  final String cover;

  final String ownerName;

  final String ownerFace;

  /// 时长（秒）。
  final int duration;

  /// 画质 ID（对齐 bilibili qn）。
  final int quality;

  /// 画质描述（如 "1080P"）。
  final String qualityDesc;

  /// 视频流地址；DURL 单文件路径下即为完整文件地址。
  final String videoUrl;

  /// 音频流地址；DURL 单文件路径下为空串。
  final String audioUrl;

  /// 合集 / 分P 分组键（可选）。
  final String? groupKey;

  /// 合集 / 分P 分组标题（可选）。
  final String? groupTitle;

  /// 分组内排序序号。
  final int episodeSortIndex;

  /// 分组内总集数。
  final int episodeCount;

  final DownloadStatus status;

  /// 下载完成后的本地文件路径。
  final String? filePath;

  /// 文件总大小（字节；0 表示未知）。
  final int fileSize;

  /// 已下载字节数。
  final int downloadedSize;

  /// 任务创建时间（epoch 毫秒）。
  final int createdAt;

  final String? errorMessage;

  /// 是否仅下载音频（听视频 / 后台播放）。
  final bool isAudioOnly;

  final DownloadOptions options;

  const DownloadTask({
    required this.bvid,
    this.aid = 0,
    required this.cid,
    required this.title,
    this.cover = '',
    this.ownerName = '',
    this.ownerFace = '',
    this.duration = 0,
    this.quality = 80,
    this.qualityDesc = '',
    this.videoUrl = '',
    this.audioUrl = '',
    this.groupKey,
    this.groupTitle,
    this.episodeSortIndex = 0,
    this.episodeCount = 1,
    this.status = DownloadStatus.pending,
    this.filePath,
    this.fileSize = 0,
    this.downloadedSize = 0,
    this.createdAt = 0,
    this.errorMessage,
    this.isAudioOnly = false,
    this.options = const DownloadOptions(),
  });

  /// 稳定唯一键（见类文档）。
  String get id =>
      isAudioOnly ? '${bvid}_${cid}_audio' : '${bvid}_${cid}_$quality';

  /// 是否已完成。
  bool get isComplete => status == DownloadStatus.completed;

  /// 是否处于「进行中」（下载或合并）。
  bool get isDownloading =>
      status == DownloadStatus.downloading || status == DownloadStatus.merging;

  /// 是否可续传（暂停或失败后）。
  bool get canResume =>
      status == DownloadStatus.paused || status == DownloadStatus.failed;

  /// 是否失败。
  bool get isFailed => status == DownloadStatus.failed;

  /// 进度 0.0 ~ 1.0，由 [downloadedSize] / [fileSize] 派生。
  ///
  /// 总大小未知（[fileSize] <= 0）时返回 0.0；超出范围时裁剪到边界。
  double get progress {
    if (fileSize <= 0) return 0.0;
    return (downloadedSize / fileSize).clamp(0.0, 1.0);
  }

  /// 字段级覆盖；未传入的字段沿用旧值（[groupKey] / [groupTitle] /
  /// [filePath] / [errorMessage] 无法通过本方法清空为 null）。
  DownloadTask copyWith({
    String? bvid,
    int? aid,
    int? cid,
    String? title,
    String? cover,
    String? ownerName,
    String? ownerFace,
    int? duration,
    int? quality,
    String? qualityDesc,
    String? videoUrl,
    String? audioUrl,
    String? groupKey,
    String? groupTitle,
    int? episodeSortIndex,
    int? episodeCount,
    DownloadStatus? status,
    String? filePath,
    int? fileSize,
    int? downloadedSize,
    int? createdAt,
    String? errorMessage,
    bool? isAudioOnly,
    DownloadOptions? options,
  }) {
    return DownloadTask(
      bvid: bvid ?? this.bvid,
      aid: aid ?? this.aid,
      cid: cid ?? this.cid,
      title: title ?? this.title,
      cover: cover ?? this.cover,
      ownerName: ownerName ?? this.ownerName,
      ownerFace: ownerFace ?? this.ownerFace,
      duration: duration ?? this.duration,
      quality: quality ?? this.quality,
      qualityDesc: qualityDesc ?? this.qualityDesc,
      videoUrl: videoUrl ?? this.videoUrl,
      audioUrl: audioUrl ?? this.audioUrl,
      groupKey: groupKey ?? this.groupKey,
      groupTitle: groupTitle ?? this.groupTitle,
      episodeSortIndex: episodeSortIndex ?? this.episodeSortIndex,
      episodeCount: episodeCount ?? this.episodeCount,
      status: status ?? this.status,
      filePath: filePath ?? this.filePath,
      fileSize: fileSize ?? this.fileSize,
      downloadedSize: downloadedSize ?? this.downloadedSize,
      createdAt: createdAt ?? this.createdAt,
      errorMessage: errorMessage ?? this.errorMessage,
      isAudioOnly: isAudioOnly ?? this.isAudioOnly,
      options: options ?? this.options,
    );
  }

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    return DownloadTask(
      bvid: json['bvid'] as String? ?? '',
      aid: _asInt(json['aid']),
      cid: _asInt(json['cid']),
      title: json['title'] as String? ?? '',
      cover: json['cover'] as String? ?? '',
      ownerName: json['ownerName'] as String? ?? '',
      ownerFace: json['ownerFace'] as String? ?? '',
      duration: _asInt(json['duration']),
      quality: _asInt(json['quality'], fallback: 80),
      qualityDesc: json['qualityDesc'] as String? ?? '',
      videoUrl: json['videoUrl'] as String? ?? '',
      audioUrl: json['audioUrl'] as String? ?? '',
      groupKey: json['groupKey'] as String?,
      groupTitle: json['groupTitle'] as String?,
      episodeSortIndex: _asInt(json['episodeSortIndex']),
      episodeCount: _asInt(json['episodeCount'], fallback: 1),
      status: DownloadStatus.fromName(json['status'] as String?),
      filePath: json['filePath'] as String?,
      fileSize: _asInt(json['fileSize']),
      downloadedSize: _asInt(json['downloadedSize']),
      createdAt: _asInt(json['createdAt']),
      errorMessage: json['errorMessage'] as String?,
      isAudioOnly: _asBool(json['isAudioOnly']),
      options: rawOptions is Map
          ? DownloadOptions.fromJson(Map<String, dynamic>.from(rawOptions))
          : const DownloadOptions(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'bvid': bvid,
        'aid': aid,
        'cid': cid,
        'title': title,
        'cover': cover,
        'ownerName': ownerName,
        'ownerFace': ownerFace,
        'duration': duration,
        'quality': quality,
        'qualityDesc': qualityDesc,
        'videoUrl': videoUrl,
        'audioUrl': audioUrl,
        'groupKey': groupKey,
        'groupTitle': groupTitle,
        'episodeSortIndex': episodeSortIndex,
        'episodeCount': episodeCount,
        'status': status.name,
        'filePath': filePath,
        'fileSize': fileSize,
        'downloadedSize': downloadedSize,
        'createdAt': createdAt,
        'errorMessage': errorMessage,
        'isAudioOnly': isAudioOnly,
        'options': options.toJson(),
      };
}

/// 容错整数转换（int / num / 数字字符串），无法解析时返回 [fallback]。
int _asInt(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

/// 容错布尔转换（bool / num / "true"），无法解析时返回 [fallback]。
bool _asBool(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) return value == 'true';
  return fallback;
}