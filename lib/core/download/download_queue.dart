// Phase 5 下载系统 · 批次3：下载队列调度。
//
// 编排层：把 [DownloadStore]（持久化）、[DownloadEngine]（传输）与
// [DownloadQueuePolicy]（并发 / 选队策略）串成一个可暂停 / 恢复 / 重试的调度器。
//
// 引擎经工厂注入、存储经抽象注入，故调度器可在无网络 + 内存存储下完整单测
// （与批次2「传输抽象」、批次3「存储抽象」一脉相承）。
//
// 生命周期：restore() 载入持久化任务，并把上次中断的 downloading / merging
// 复位为 queued（保留已落盘字节，交由引擎续传）；是否立即开跑由调用方 pump() 决定，
// 避免启动即静默下载。

import 'dart:async';

import 'package:winwin/core/download/download_engine.dart';
import 'package:winwin/core/download/download_policy.dart';
import 'package:winwin/core/download/download_store.dart';
import 'package:winwin/models/download/download_task.dart';

/// 由任务解析落盘绝对路径（生产由设置 `downloadPath` + 命名策略给出）。
typedef DownloadSavePathResolver = String Function(DownloadTask task);

/// 由任务解析下载请求头（生产注入 Cookie / Referer）。
typedef DownloadHeadersResolver = Map<String, String> Function(DownloadTask task);

/// 下载队列调度器。
class DownloadQueueCoordinator {
  DownloadQueueCoordinator({
    required this.store,
    required this.engineFactory,
    required this.resolveSavePath,
    this.resolveHeaders,
    this.maxConcurrentDownloads =
        DownloadQueuePolicy.defaultMaxConcurrentDownloads,
    this.progressPersistIntervalMs = 1000,
    int Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final DownloadStore store;

  /// 每次执行下载时创建引擎实例（生产：`DownloadEngine(transport: DioDownloadTransport())`）。
  final DownloadEngine Function() engineFactory;

  final DownloadSavePathResolver resolveSavePath;

  /// 可选请求头解析器；为空时不附带额外请求头。
  final DownloadHeadersResolver? resolveHeaders;

  final int maxConcurrentDownloads;

  /// 进度落盘节流窗口（毫秒），避免高频回调抖动 Hive。
  final int progressPersistIntervalMs;

  final int Function() _clock;

  final Map<String, DownloadTask> _tasks = <String, DownloadTask>{};
  final Set<String> _running = <String>{};
  final Set<String> _cancelRequested = <String>{};
  final Map<String, int> _lastPersistMs = <String, int>{};

  bool _disposed = false;

  /// 载入持久化任务，并复位上次中断的进行中任务为 queued。
  ///
  /// 不自动开跑：需要续跑时调用方随后显式 [pump]。
  void restore() {
    _tasks.clear();
    for (final task in store.loadAll()) {
      _tasks[task.id] = _normalizeAfterRestore(task);
    }
  }

  /// 任务快照（按 `createdAt` 升序、`id` 升序）。
  List<DownloadTask> get tasks {
    final list = _tasks.values.toList()..sort((a, b) {
        final byTime = a.createdAt.compareTo(b.createdAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    return list;
  }

  /// 是否存在活跃下载（用于 UI 展示 / 退出提示）。
  bool get hasActiveDownloads => _running.isNotEmpty;

  /// 按 id 取任务当前态。
  DownloadTask? taskOf(String id) => _tasks[id];

  /// 入队（新增或覆盖同 id 任务）并尝试调度。
  Future<void> enqueue(DownloadTask task) async {
    final queued = task.copyWith(
      status: DownloadStatus.queued,
      clearErrorMessage: true,
    );
    _tasks[queued.id] = queued;
    await store.save(queued);
    await pump();
  }

  /// 暂停：运行中的请求取消（收尾转 paused），静止的直接置 paused。
  Future<void> pause(String id) async {
    final task = _tasks[id];
    if (task == null) return;
    if (_running.contains(id)) {
      _cancelRequested.add(id);
      return;
    }
    if (task.status == DownloadStatus.paused) return;
    final updated = task.copyWith(status: DownloadStatus.paused);
    _tasks[id] = updated;
    await store.save(updated);
  }

  /// 恢复（paused / failed → queued）并尝试调度。
  Future<void> resume(String id) async {
    final task = _tasks[id];
    if (task == null) return;
    if (task.status != DownloadStatus.paused &&
        task.status != DownloadStatus.failed) {
      return;
    }
    _cancelRequested.remove(id);
    final updated = task.copyWith(
      status: DownloadStatus.queued,
      clearErrorMessage: true,
    );
    _tasks[id] = updated;
    await store.save(updated);
    await pump();
  }

  /// 重试（failed → queued），语义同 [resume]。
  Future<void> retry(String id) => resume(id);

  /// 移除任务记录（不删除已落盘文件）；运行中会请求取消。
  Future<void> remove(String id) async {
    if (_tasks.remove(id) == null && !_running.contains(id)) return;
    if (_running.contains(id)) _cancelRequested.add(id);
    await store.remove(id);
  }

  /// 清空全部任务记录（不删除已落盘文件）。
  Future<void> clear() async {
    _cancelRequested.addAll(_running);
    _tasks.clear();
    await store.clear();
  }

  /// 依据剩余并发槽位，启动下一批排队任务。
  Future<void> pump() async {
    if (_disposed) return;
    final ids = DownloadQueuePolicy.resolveNextQueuedDownloadTaskIds(
      _tasks.values,
      maxConcurrent: maxConcurrentDownloads,
    );
    for (final id in ids) {
      if (_running.contains(id)) continue;
      _running.add(id);
      unawaited(_run(id));
    }
  }

  /// 释放调度器：不再调度新任务，并请求已运行任务取消。
  void dispose() {
    _disposed = true;
    _cancelRequested.addAll(_running);
  }

  Future<void> _run(String id) async {
    var task = _tasks[id];
    if (task == null) {
      _running.remove(id);
      return;
    }

    _cancelRequested.remove(id);
    task = task.copyWith(
      status: DownloadStatus.downloading,
      clearErrorMessage: true,
    );
    _tasks[id] = task;

    var savePath = task.filePath ?? '';
    try {
      await store.save(task);
      savePath = resolveSavePath(task);
      final outcome = await engineFactory().download(
        url: Uri.parse(task.videoUrl),
        savePath: savePath,
        headers: resolveHeaders?.call(task) ?? const <String, String>{},
        onProgress: (progress) => _onProgress(id, progress),
        isCancelled: () => _cancelRequested.contains(id),
      );
      _applyOutcome(id, savePath, outcome);
    } catch (error) {
      _applyOutcome(
        id,
        savePath,
        DownloadOutcome(
          status: DownloadFinishStatus.failed,
          downloadedBytes: 0,
          totalBytes: 0,
          error: '$error',
        ),
      );
    } finally {
      _running.remove(id);
      _cancelRequested.remove(id);
      _lastPersistMs.remove(id);
    }

    final current = _tasks[id];
    if (current != null) await store.save(current);
    await pump();
  }

  void _onProgress(String id, DownloadProgress progress) {
    final task = _tasks[id];
    if (task == null) return;
    final updated = task.copyWith(
      downloadedSize: progress.downloadedBytes,
      fileSize: progress.totalBytes > 0 ? progress.totalBytes : task.fileSize,
    );
    _tasks[id] = updated;

    final now = _clock();
    final last = _lastPersistMs[id] ?? 0;
    if (now - last >= progressPersistIntervalMs) {
      _lastPersistMs[id] = now;
      unawaited(store.save(updated));
    }
  }

  void _applyOutcome(String id, String savePath, DownloadOutcome outcome) {
    final task = _tasks[id];
    if (task == null) return;
    DownloadTask updated;
    switch (outcome.status) {
      case DownloadFinishStatus.completed:
        final size =
            outcome.totalBytes > 0 ? outcome.totalBytes : outcome.downloadedBytes;
        updated = task.copyWith(
          status: DownloadStatus.completed,
          filePath: savePath,
          fileSize: size,
          downloadedSize: size,
          clearErrorMessage: true,
        );
        break;
      case DownloadFinishStatus.cancelled:
        updated = task.copyWith(
          status: DownloadStatus.paused,
          downloadedSize: outcome.downloadedBytes,
          fileSize: outcome.totalBytes > 0 ? outcome.totalBytes : task.fileSize,
        );
        break;
      case DownloadFinishStatus.failed:
        updated = task.copyWith(
          status: DownloadStatus.failed,
          downloadedSize: outcome.downloadedBytes,
          fileSize: outcome.totalBytes > 0 ? outcome.totalBytes : task.fileSize,
          errorMessage: outcome.error ?? '下载失败',
        );
        break;
    }
    _tasks[id] = updated;
  }

  /// 复位：上次中断的 downloading / merging 回到 queued（保留已落盘字节）。
  static DownloadTask _normalizeAfterRestore(DownloadTask task) {
    if (task.status == DownloadStatus.downloading ||
        task.status == DownloadStatus.merging) {
      return task.copyWith(status: DownloadStatus.queued);
    }
    return task;
  }
}