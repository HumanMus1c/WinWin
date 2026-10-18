// Phase 5 下载系统 · 批次2：断点续传下载引擎。
//
// 纯编排层：probe → 续传计划 → （并行分片 | 单流）拉取 → 校验落盘长度。
// 网络与文件句柄由 [DownloadTransport] 抽象隔离，引擎本身可离线单测。
//
// 架构决策：本仓 `pubspec.yaml` 无 ffmpeg、无 assets 二进制 ⇒ DASH 音视频
// 分离流无 muxer 可合并；离线下载走 DURL 单文件 MP4（见 `lib/http/video.dart`
// L216-219）。故引擎只负责「单文件字节流」的续传与分片，不涉及音视频合并。

import 'dart:async';
import 'dart:io';

import 'package:winwin/core/download/download_policy.dart';
import 'package:winwin/core/download/download_transport.dart';

/// 下载收尾状态。
enum DownloadFinishStatus {
  /// 完整下载并落盘（长度与预期一致）。
  completed,

  /// 被取消（保留已落盘部分，供下次续传）。
  cancelled,

  /// 失败（探测异常 / 传输异常 / 长度校验不符）。
  failed,
}

/// 下载进度快照。
class DownloadProgress {
  const DownloadProgress({
    required this.downloadedBytes,
    required this.totalBytes,
  });

  /// 已落盘字节数（含续传起点的既有字节）。
  final int downloadedBytes;

  /// 资源总字节数（0 表示未知）。
  final int totalBytes;

  /// 进度比例（总大小未知时为 0）。
  double get fraction {
    if (totalBytes <= 0) return 0;
    final value = downloadedBytes / totalBytes;
    if (value < 0) return 0;
    if (value > 1) return 1;
    return value;
  }
}

/// 下载结果。
class DownloadOutcome {
  const DownloadOutcome({
    required this.status,
    required this.downloadedBytes,
    required this.totalBytes,
    this.resumed = false,
    this.usedParallelChunks = false,
    this.error,
  });

  final DownloadFinishStatus status;

  /// 落盘字节数（失败 / 取消时为当前已写字节）。
  final int downloadedBytes;

  /// 资源总字节数（未知且成功时为实际落盘长度）。
  final int totalBytes;

  /// 是否从断点续传（存在既有部分数据）。
  final bool resumed;

  /// 是否走了并行分片路径。
  final bool usedParallelChunks;

  /// 失败原因（仅 [DownloadFinishStatus.failed] 时非空）。
  final String? error;

  bool get isCompleted => status == DownloadFinishStatus.completed;
  bool get isCancelled => status == DownloadFinishStatus.cancelled;
  bool get isFailed => status == DownloadFinishStatus.failed;
}

/// 断点续传下载引擎。
///
/// 用法：
/// ```dart
/// final engine = DownloadEngine();
/// final outcome = await engine.download(
///   url: Uri.parse(cdnUrl),
///   savePath: r'D:\downloads\video.mp4',
///   headers: DownloadRequestHeaders.buildHeaders(),
///   onProgress: (p) => print('${p.fraction}'),
/// );
/// ```
class DownloadEngine {
  DownloadEngine({
    this.transport,
    this.maxChunks = DownloadRangePolicy.defaultMaxChunks,
    this.parallelChunkThresholdBytes =
        DownloadRangePolicy.defaultParallelChunkThresholdBytes,
  });

  /// 传输实现；为 null 时须由调用方注入（生产用 `DioDownloadTransport`）。
  ///
  /// 构造时不强制创建 dio 实例，保持引擎对网络栈零硬依赖（利于单测）。
  final DownloadTransport? transport;

  /// 并行分片的最大分片数。
  final int maxChunks;

  /// 启用并行分片的最小资源字节阈值。
  final int parallelChunkThresholdBytes;

  DownloadTransport _resolveTransport() {
    final resolved = transport;
    if (resolved == null) {
      throw StateError(
        'DownloadEngine 需要注入 DownloadTransport（生产用 DioDownloadTransport）。',
      );
    }
    return resolved;
  }

  /// 执行下载（自动续传）。
  ///
  /// - [url]：CDN 直链；[savePath]：目标文件绝对路径（父目录会自动创建）；
  /// - [headers]：下载请求头（见 [DownloadRequestHeaders]）；
  /// - [onProgress]：进度回调（含续传起点字节）；
  /// - [isCancelled]：返回 true 时尽快中止，已写字节保留。
  Future<DownloadOutcome> download({
    required Uri url,
    required String savePath,
    Map<String, String> headers = const <String, String>{},
    void Function(DownloadProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    bool cancelled() => isCancelled?.call() ?? false;

    if (cancelled()) {
      return const DownloadOutcome(
        status: DownloadFinishStatus.cancelled,
        downloadedBytes: 0,
        totalBytes: 0,
      );
    }

    // 传输实例在探测前解析：未注入属配置错误，应直接抛出（而非被下述
    // 探测 try/catch 吞成 failed）。
    final transport = _resolveTransport();

    DownloadRangeProbe probe;
    try {
      probe = await transport.probe(url: url, headers: headers);
    } catch (error) {
      return DownloadOutcome(
        status: DownloadFinishStatus.failed,
        downloadedBytes: 0,
        totalBytes: 0,
        error: '探测失败：$error',
      );
    }

    final file = File(savePath);
    await file.parent.create(recursive: true);

    final existingBytes = await file.exists() ? await file.length() : 0;
    final plan = DownloadResumePolicy.resolveResumableDownloadPlan(
      existingBytes: existingBytes,
      totalBytes: probe.totalBytes,
      acceptsRanges: probe.supportsRanges,
    );

    if (plan.alreadyComplete) {
      onProgress?.call(
        DownloadProgress(
          downloadedBytes: plan.totalBytes,
          totalBytes: plan.totalBytes,
        ),
      );
      return DownloadOutcome(
        status: DownloadFinishStatus.completed,
        downloadedBytes: plan.totalBytes,
        totalBytes: plan.totalBytes,
        resumed: existingBytes > 0,
      );
    }

    final useParallelChunks = plan.rangeStartBytes == 0 &&
        DownloadRangePolicy.shouldUseParallelChunks(
          totalBytes: probe.totalBytes,
          supportsRanges: probe.supportsRanges,
          thresholdBytes: parallelChunkThresholdBytes,
          maxChunks: maxChunks,
        );

    try {
      final written = useParallelChunks
          ? await _downloadChunked(
              url: url,
              file: file,
              headers: headers,
              totalBytes: probe.totalBytes,
              onProgress: onProgress,
              cancelled: cancelled,
            )
          : await _downloadSingleStream(
              url: url,
              file: file,
              headers: headers,
              plan: plan,
              onProgress: onProgress,
              cancelled: cancelled,
            );

      if (cancelled()) {
        return DownloadOutcome(
          status: DownloadFinishStatus.cancelled,
          downloadedBytes: written,
          totalBytes: probe.totalBytes,
          resumed: plan.append,
          usedParallelChunks: useParallelChunks,
        );
      }

      final actualBytes = await file.length();
      final expectedBytes = probe.totalBytes > 0 ? probe.totalBytes : actualBytes;
      if (probe.totalBytes > 0 && actualBytes != probe.totalBytes) {
        return DownloadOutcome(
          status: DownloadFinishStatus.failed,
          downloadedBytes: actualBytes,
          totalBytes: probe.totalBytes,
          resumed: plan.append,
          usedParallelChunks: useParallelChunks,
          error: '长度校验不符：期望 ${probe.totalBytes}，实际 $actualBytes',
        );
      }

      onProgress?.call(
        DownloadProgress(
          downloadedBytes: expectedBytes,
          totalBytes: expectedBytes,
        ),
      );
      return DownloadOutcome(
        status: DownloadFinishStatus.completed,
        downloadedBytes: expectedBytes,
        totalBytes: expectedBytes,
        resumed: plan.append,
        usedParallelChunks: useParallelChunks,
      );
    } on DownloadCancelledException {
      final actualBytes = await file.exists() ? await file.length() : 0;
      return DownloadOutcome(
        status: DownloadFinishStatus.cancelled,
        downloadedBytes: actualBytes,
        totalBytes: probe.totalBytes,
        resumed: plan.append,
        usedParallelChunks: useParallelChunks,
      );
    } catch (error) {
      final actualBytes = await file.exists() ? await file.length() : 0;
      return DownloadOutcome(
        status: DownloadFinishStatus.failed,
        downloadedBytes: actualBytes,
        totalBytes: probe.totalBytes,
        resumed: plan.append,
        usedParallelChunks: useParallelChunks,
        error: '$error',
      );
    }
  }

  /// 单流路径：从续传起点顺序拉取到文件结尾。
  Future<int> _downloadSingleStream({
    required Uri url,
    required File file,
    required Map<String, String> headers,
    required ResumableDownloadPlan plan,
    void Function(DownloadProgress progress)? onProgress,
    required bool Function() cancelled,
  }) async {
    final raf = await file.open(
      mode: plan.append ? FileMode.append : FileMode.write,
    );
    var written = plan.initialDownloadedBytes;
    try {
      await _resolveTransport().fetchRange(
        url: url,
        headers: headers,
        startBytes: plan.append ? plan.rangeStartBytes : null,
        onChunk: (data, _) async {
          await raf.writeFrom(data);
          written += data.length;
          onProgress?.call(
            DownloadProgress(downloadedBytes: written, totalBytes: plan.totalBytes),
          );
        },
        isCancelled: cancelled,
      );
    } finally {
      await raf.close();
    }
    return written;
  }

  /// 并行分片路径：按 [DownloadRangePolicy] 切分区间并并发拉取。
  ///
  /// 文件先按总大小预分配；各分片的写入通过互斥锁串行化到同一句柄，
  /// 保证按绝对偏移写入且不互相覆盖（网络并发、落盘串行）。
  Future<int> _downloadChunked({
    required Uri url,
    required File file,
    required Map<String, String> headers,
    required int totalBytes,
    void Function(DownloadProgress progress)? onProgress,
    required bool Function() cancelled,
  }) async {
    final ranges = DownloadRangePolicy.resolveChunkRanges(
      totalBytes: totalBytes,
      maxChunks: maxChunks,
    );

    // 以 FileMode.write 打开（截断为空）；分片按绝对偏移写入，
    // 跨越 EOF 的写入会自动扩展文件，无需预分配。
    final raf = await file.open(mode: FileMode.write);
    final mutex = _WriteMutex();
    var written = 0;

    try {
      await Future.wait(
        ranges.map(
          (range) => _resolveTransport().fetchRange(
            url: url,
            headers: headers,
            startBytes: range.startBytes,
            endBytesInclusive: range.endBytesInclusive,
            isCancelled: cancelled,
            onChunk: (data, offset) async {
              await mutex.run(() async {
                await raf.setPosition(offset);
                await raf.writeFrom(data);
              });
              written += data.length;
              onProgress?.call(
                DownloadProgress(downloadedBytes: written, totalBytes: totalBytes),
              );
            },
          ),
        ),
      );
    } finally {
      await raf.close();
    }
    return written;
  }
}

/// 极简异步互斥锁：把并发的文件写入串行化。
class _WriteMutex {
  Future<void> _tail = Future<void>.value();

  Future<void> run(Future<void> Function() action) {
    final completer = Completer<void>();
    final previous = _tail;
    _tail = previous.then((_) async {
      try {
        await action();
        completer.complete();
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }
}