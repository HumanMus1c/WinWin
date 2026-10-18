// Ported from BiliPai (Kotlin) -> WinWin (Dart)
// Original: com/android/purebilibili/feature/download/
//   DownloadQueuePolicy.kt / DownloadResumePolicy.kt
//   / DownloadAssetPolicy.kt / DownloadStoragePolicy.kt
//   / DownloadRequestHeaders.kt
//
// Phase 5 下载系统核心层策略（纯逻辑，无 IO / 网络）：
//   - 队列调度：并发上限、下一个可执行任务、陈旧地址刷新判定；
//   - 断点续传：续传计划（追加 / 从头 / 已完成）；
//   - Range 解析与分片：Content-Range 解析、并行分片区间切分；
//   - 文件命名：非法字符清洗、导出文件名与扩展名裁决；
//   - 请求头：bilibili CDN 下载所需的 User-Agent / Referer / Cookie。

import 'package:winwin/models/download/download_task.dart';

/// Range 探针：一次探测后得到的资源大小与是否支持分段。
class DownloadRangeProbe {
  /// 资源总字节数（0 表示未知）。
  final int totalBytes;

  /// 服务器是否支持 Range 分段请求。
  final bool supportsRanges;

  const DownloadRangeProbe({
    required this.totalBytes,
    required this.supportsRanges,
  });
}

/// 一个字节分片区间（闭区间 `[startBytes, endBytesInclusive]`）。
class DownloadChunkRange {
  final int index;
  final int startBytes;
  final int endBytesInclusive;

  const DownloadChunkRange({
    required this.index,
    required this.startBytes,
    required this.endBytesInclusive,
  });

  /// 分片字节长度。
  int get sizeBytes => endBytesInclusive - startBytes + 1;
}

/// 断点续传执行计划。
class ResumableDownloadPlan {
  /// 是否以「追加」方式写入（true 时从 [rangeStartBytes] 续传）。
  final bool append;

  /// 请求 Range 的起始字节。
  final int rangeStartBytes;

  /// 已落盘的字节数（续传起点）。
  final int initialDownloadedBytes;

  /// 资源总字节数（0 表示未知）。
  final int totalBytes;

  /// 是否已下载完整。
  final bool alreadyComplete;

  const ResumableDownloadPlan({
    required this.append,
    required this.rangeStartBytes,
    required this.initialDownloadedBytes,
    required this.totalBytes,
    required this.alreadyComplete,
  });
}

/// 下载队列调度策略。
abstract final class DownloadQueuePolicy {
  /// 默认并发下载数（对标 BiliPai `DEFAULT_MAX_CONCURRENT_DOWNLOADS`）。
  static const int defaultMaxConcurrentDownloads = 2;

  /// 陈旧播放地址刷新阈值：30 分钟。
  static const int staleDownloadUrlRefreshThresholdMs = 30 * 60 * 1000;

  /// 任务是否处于「活跃」态（占用并发槽位）。
  ///
  /// 活跃 = pending / downloading / merging（与 BiliPai 一致）。
  static bool isDownloadTaskActive(DownloadTask task) {
    switch (task.status) {
      case DownloadStatus.pending:
      case DownloadStatus.downloading:
      case DownloadStatus.merging:
        return true;
      case DownloadStatus.queued:
      case DownloadStatus.paused:
      case DownloadStatus.completed:
      case DownloadStatus.failed:
        return false;
    }
  }

  /// 依据剩余并发槽位，选出下一个应执行的排队任务 id 列表。
  ///
  /// 排序规则（与 BiliPai 一致）：先 `createdAt` 升序，再 `id` 升序。
  /// 并发已满或无排队任务时返回空列表。
  static List<String> resolveNextQueuedDownloadTaskIds(
    Iterable<DownloadTask> tasks, {
    int maxConcurrent = defaultMaxConcurrentDownloads,
  }) {
    final taskList = tasks.toList();
    var active = 0;
    for (final task in taskList) {
      if (isDownloadTaskActive(task)) active++;
    }
    final slots = maxConcurrent - active;
    if (slots <= 0) return const <String>[];

    final queued = taskList
        .where((task) => task.status == DownloadStatus.queued)
        .toList()
      ..sort((a, b) {
        final byTime = a.createdAt.compareTo(b.createdAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });

    return queued.take(slots).map((task) => task.id).toList();
  }

  /// 判断入队时解析的播放地址是否已陈旧、执行前需刷新。
  ///
  /// 时间非法（`createdAtMs <= 0` 或晚于 `nowMs`）时返回 false。
  static bool shouldRefreshStaleDownloadUrls({
    required int createdAtMs,
    required int nowMs,
    int thresholdMs = staleDownloadUrlRefreshThresholdMs,
  }) {
    if (createdAtMs <= 0 || createdAtMs >= nowMs) return false;
    return (nowMs - createdAtMs) >= thresholdMs;
  }
}

/// 断点续传策略。
abstract final class DownloadResumePolicy {
  /// 依据已落盘字节、资源总大小与服务器是否支持 Range，产出续传计划。
  ///
  /// 规则（与 BiliPai `resolveResumableDownloadPlan` 一致）：
  /// 1. 已下载 >= 总大小 → 视为已完成，不追加；
  /// 2. 支持 Range 且已有部分数据 → 从断点追加续传；
  /// 3. 其余情况 → 从头开始（覆盖写入）。
  static ResumableDownloadPlan resolveResumableDownloadPlan({
    required int existingBytes,
    required int totalBytes,
    required bool acceptsRanges,
  }) {
    final safeExisting = existingBytes < 0 ? 0 : existingBytes;
    final safeTotal = totalBytes < 0 ? 0 : totalBytes;

    if (safeTotal > 0 && safeExisting >= safeTotal) {
      return ResumableDownloadPlan(
        append: false,
        rangeStartBytes: safeTotal,
        initialDownloadedBytes: safeTotal,
        totalBytes: safeTotal,
        alreadyComplete: true,
      );
    }

    if (acceptsRanges && safeExisting > 0) {
      return ResumableDownloadPlan(
        append: true,
        rangeStartBytes: safeExisting,
        initialDownloadedBytes: safeExisting,
        totalBytes: safeTotal,
        alreadyComplete: false,
      );
    }

    return ResumableDownloadPlan(
      append: false,
      rangeStartBytes: 0,
      initialDownloadedBytes: 0,
      totalBytes: safeTotal,
      alreadyComplete: false,
    );
  }
}

/// Range 解析与并行分片策略。
abstract final class DownloadRangePolicy {
  /// 启用并行分片的最小资源字节阈值：8 MiB。
  static const int defaultParallelChunkThresholdBytes = 8 * 1024 * 1024;

  /// 默认最大分片数。
  static const int defaultMaxChunks = 4;

  static final RegExp _contentRangePattern =
      RegExp(r'^bytes\s+(\d+)-(\d+)/(\d+|\*)$');

  /// 解析 `Content-Range` 响应头（如 `bytes 0-1023/4096`）。
  ///
  /// 无法解析时返回 null；总大小未知（`*`）时以本段结尾推断为 `end + 1`。
  static DownloadRangeProbe? parseContentRange(String? contentRange) {
    final trimmed = contentRange?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final match = _contentRangePattern.firstMatch(trimmed);
    if (match == null) return null;
    final end = int.tryParse(match.group(2)!);
    if (end == null) return null;
    final total = match.group(3) == '*'
        ? end + 1
        : (int.tryParse(match.group(3)!) ?? (end + 1));
    return DownloadRangeProbe(
      totalBytes: total < 0 ? 0 : total,
      supportsRanges: true,
    );
  }

  /// 是否需要并行分片下载（需同时满足支持 Range 与超过阈值）。
  static bool shouldUseParallelChunks({
    required int totalBytes,
    required bool supportsRanges,
    int thresholdBytes = defaultParallelChunkThresholdBytes,
    int maxChunks = defaultMaxChunks,
  }) {
    return supportsRanges && totalBytes >= thresholdBytes && maxChunks > 1;
  }

  /// 将 [totalBytes] 均分为至多 [maxChunks] 个闭区间分片。
  ///
  /// 无法分片（总大小 <= 0 或 maxChunks <= 1）时返回单个覆盖全量的区间；
  /// 余数字节按前段优先分配，分片之间无重叠、无空洞。
  static List<DownloadChunkRange> resolveChunkRanges({
    required int totalBytes,
    int maxChunks = defaultMaxChunks,
  }) {
    if (totalBytes <= 0 || maxChunks <= 1) {
      final end = totalBytes - 1;
      return <DownloadChunkRange>[
        DownloadChunkRange(
          index: 0,
          startBytes: 0,
          endBytesInclusive: end < 0 ? 0 : end,
        ),
      ];
    }
    final chunkCount = maxChunks > totalBytes ? totalBytes : maxChunks;
    final baseSize = totalBytes ~/ chunkCount;
    final remainder = totalBytes % chunkCount;
    var start = 0;
    final ranges = <DownloadChunkRange>[];
    for (var index = 0; index < chunkCount; index++) {
      final size = baseSize + (index < remainder ? 1 : 0);
      final end = start + size - 1;
      ranges.add(DownloadChunkRange(
        index: index,
        startBytes: start,
        endBytesInclusive: end,
      ));
      start = end + 1;
    }
    return ranges;
  }
}

/// 下载文件命名策略。
abstract final class DownloadNamingPolicy {
  static final RegExp _invalidFileNameChars = RegExp(r'[\\/:*?"<>|\n\r\t]');
  static final RegExp _multiUnderscore = RegExp('_+');
  static final RegExp _multiSpace = RegExp(r'\s+');

  /// 清洗文件名片段：非法字符替换为 `_`，折叠连续空白 / 下划线，
  /// 去除首尾的 ` ` / `_` / `.`（对标 BiliPai `sanitizeFileNamePart`）。
  static String sanitizeFileNamePart(String value) {
    final replaced = value
        .replaceAll(_invalidFileNameChars, '_')
        .replaceAll(_multiSpace, ' ')
        .replaceAll(_multiUnderscore, '_');
    return _trimEdgeChars(replaced);
  }

  /// 构建导出文件名（对标 BiliPai `buildSafeExportDisplayName`）。
  ///
  /// 标题清洗后为空则回退 "video"；画质描述为空时不拼接；扩展名去掉前导点，
  /// 为空则回退 "mp4"。
  static String buildExportFileName({
    required String title,
    String qualityDesc = '',
    String extension = 'mp4',
  }) {
    var safeTitle = sanitizeFileNamePart(title);
    if (safeTitle.isEmpty) safeTitle = 'video';
    final safeQuality = sanitizeFileNamePart(qualityDesc);
    final baseName =
        safeQuality.isEmpty ? safeTitle : '${safeTitle}_$safeQuality';
    var safeExt = extension.trim();
    if (safeExt.startsWith('.')) safeExt = safeExt.substring(1);
    if (safeExt.isEmpty) safeExt = 'mp4';
    return '$baseName.$safeExt';
  }

  /// 由媒体地址推断视频文件扩展名（无法识别时回退 mp4）。
  static String resolveVideoExtension(String? url) => _resolveExtension(
        url,
        const <String, String>{
          'mp4': 'mp4',
          'flv': 'flv',
          'mkv': 'mkv',
          'mov': 'mov',
          'webm': 'webm',
          'm4s': 'mp4',
        },
        fallback: 'mp4',
      );

  /// 由媒体地址推断音频文件扩展名（无法识别时回退 m4a）。
  static String resolveAudioExtension(String? url) => _resolveExtension(
        url,
        const <String, String>{
          'm4a': 'm4a',
          'mp3': 'mp3',
          'aac': 'aac',
          'flac': 'flac',
          'mp4': 'm4a',
          'm4s': 'm4a',
        },
        fallback: 'm4a',
      );

  static String _resolveExtension(
    String? url,
    Map<String, String> map, {
    required String fallback,
  }) {
    final path = Uri.tryParse(url ?? '')?.path ?? '';
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return fallback;
    final ext = path.substring(dot + 1).toLowerCase();
    return map[ext] ?? fallback;
  }

  /// 去除首尾的空白 / 下划线 / 点号。
  static String _trimEdgeChars(String value) {
    const edgeChars = ' _.';
    var start = 0;
    var end = value.length;
    while (start < end && edgeChars.contains(value[start])) {
      start++;
    }
    while (end > start && edgeChars.contains(value[end - 1])) {
      end--;
    }
    return value.substring(start, end);
  }
}

/// bilibili CDN 下载请求头构造。
abstract final class DownloadRequestHeaders {
  /// 下载用 User-Agent（对标 BiliPai `BILIBILI_DOWNLOAD_USER_AGENT`）。
  static const String bilibiliDownloadUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  /// 默认 Referer。
  static const String defaultReferer = 'https://www.bilibili.com';

  /// 组装 Cookie 头：仅拼接非空的 SESSDATA / bili_jct / buvid3。
  static String buildCookieHeader({
    String? sessData,
    String? biliJct,
    String? buvid3,
  }) {
    final parts = <String>[];
    final sess = sessData ?? '';
    final jct = biliJct ?? '';
    final buvid = buvid3 ?? '';
    if (sess.isNotEmpty) parts.add('SESSDATA=$sess');
    if (jct.isNotEmpty) parts.add('bili_jct=$jct');
    if (buvid.isNotEmpty) parts.add('buvid3=$buvid');
    return parts.join('; ');
  }

  /// 构造下载请求头；[cookieHeader] 为空时不写入 Cookie 项。
  static Map<String, String> buildHeaders({
    String cookieHeader = '',
    String referer = defaultReferer,
  }) {
    final headers = <String, String>{
      'User-Agent': bilibiliDownloadUserAgent,
      'Referer': referer,
    };
    if (cookieHeader.isNotEmpty) headers['Cookie'] = cookieHeader;
    return headers;
  }
}