// Phase 5 下载系统 · 批次3：下载队列调度单测。
//
// 通过「假传输 + 内存存储」注入，验证入队调度 / 并发上限 / 暂停恢复 / 失败 /
// 移除 / 重启复位，全程无网络。

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:winwin/core/download/download_engine.dart';
import 'package:winwin/core/download/download_policy.dart';
import 'package:winwin/core/download/download_queue.dart';
import 'package:winwin/core/download/download_store.dart';
import 'package:winwin/core/download/download_transport.dart';
import 'package:winwin/models/download/download_task.dart';

import 'download_store_test.dart' show MemoryDownloadTaskStorage;

/// 确定性字节：第 i 字节为 `i % 251`。
List<int> makeContent(int length) =>
    List<int>.generate(length, (index) => index % 251);

/// 正常运行到结束的假传输。
class FakeTransport implements DownloadTransport {
  FakeTransport({required this.content, int? declaredTotal, this.probeError})
      : declaredTotal = declaredTotal ?? content.length;

  final List<int> content;
  final int declaredTotal;
  final Object? probeError;

  @override
  Future<DownloadRangeProbe> probe({
    required Uri url,
    required Map<String, String> headers,
  }) async {
    final error = probeError;
    if (error != null) throw error;
    return DownloadRangeProbe(totalBytes: declaredTotal, supportsRanges: true);
  }

  @override
  Future<void> fetchRange({
    required Uri url,
    required Map<String, String> headers,
    int? startBytes,
    int? endBytesInclusive,
    required Future<void> Function(List<int> data, int absoluteOffset) onChunk,
    bool Function()? isCancelled,
  }) async {
    var offset = startBytes ?? 0;
    final end = math.min(endBytesInclusive ?? content.length - 1, content.length - 1);
    const chunk = 8;
    while (offset <= end) {
      if (isCancelled?.call() ?? false) {
        throw const DownloadCancelledException();
      }
      final span = math.min(chunk, end - offset + 1);
      await onChunk(content.sublist(offset, offset + span), offset);
      offset += span;
    }
  }

  @override
  void close() {}
}

/// 阻塞式假传输：永远不完成，仅响应取消。用于稳定观察「下载中」态。
class BlockingTransport implements DownloadTransport {
  @override
  Future<DownloadRangeProbe> probe({
    required Uri url,
    required Map<String, String> headers,
  }) async =>
      const DownloadRangeProbe(totalBytes: 100, supportsRanges: true);

  @override
  Future<void> fetchRange({
    required Uri url,
    required Map<String, String> headers,
    int? startBytes,
    int? endBytesInclusive,
    required Future<void> Function(List<int> data, int absoluteOffset) onChunk,
    bool Function()? isCancelled,
  }) async {
    while (true) {
      if (isCancelled?.call() ?? false) {
        throw const DownloadCancelledException();
      }
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  @override
  void close() {}
}

DownloadTask buildTask({
  required String bvid,
  required int cid,
  int createdAt = 0,
}) =>
    DownloadTask(
      bvid: bvid,
      cid: cid,
      title: '标题 $bvid',
      quality: 80,
      createdAt: createdAt,
      videoUrl: 'https://cdn.example.com/$bvid.mp4',
    );

/// 轮询等待条件成立（纯 dart 异步，无 widget pump）。
Future<void> waitUntil(
  bool Function() condition, {
  String reason = 'condition',
  int maxTries = 1000,
}) async {
  for (var i = 0; i < maxTries; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 3));
  }
  throw StateError('waitUntil 超时：$reason');
}

/// 释放调度器并等待在途下载**真正收尾**。
///
/// `dispose()` 只是同步**请求**取消（立即返回）：引擎要等下一次取消轮询
/// （`BlockingTransport` 每 2ms 一次）才发现取消，随后才在 `finally` 里
/// `raf.close()` 释放文件句柄。Windows 下若在句柄关闭前删除临时目录，会抛
/// `PathAccessException ... errno = 32`（共享冲突）—— 这正是本文件此前
/// 概率性失败（本地约 1/3、云端稳定撞上）的根因；Linux/macOS 允许 unlink
/// 已打开文件，故不暴露。
///
/// 收尾闸门取 `hasActiveDownloads` 归零：它在 `_run` 的 `finally` 里移除，
/// 而该处晚于引擎 `download()` 返回（其内部 `finally` 已 await 关闭句柄）。
Future<void> disposeAndSettle(DownloadQueueCoordinator coordinator) async {
  coordinator.dispose();
  await waitUntil(
    () => !coordinator.hasActiveDownloads,
    reason: '在途下载收尾（文件句柄释放）',
  );
}

void main() {
  late Directory tempDir;
  late MemoryDownloadTaskStorage storage;
  late DownloadStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('winwin_dl_queue_');
    storage = MemoryDownloadTaskStorage();
    store = DownloadStore(storage: storage);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  DownloadQueueCoordinator coordinatorWith({
    required DownloadTransport Function() transportFactory,
    int maxConcurrent = DownloadQueuePolicy.defaultMaxConcurrentDownloads,
  }) =>
      DownloadQueueCoordinator(
        store: store,
        engineFactory: () => DownloadEngine(transport: transportFactory()),
        resolveSavePath: (task) =>
            '${tempDir.path}${Platform.pathSeparator}${task.id}.mp4',
        maxConcurrentDownloads: maxConcurrent,
      );

  group('DownloadQueueCoordinator', () {
    test('入队后自动调度并完成下载', () async {
      final content = makeContent(96);
      final coordinator =
          coordinatorWith(transportFactory: () => FakeTransport(content: content));

      final task = buildTask(bvid: 'BV1', cid: 1);
      await coordinator.enqueue(task);

      await waitUntil(
        () => coordinator.taskOf(task.id)?.status == DownloadStatus.completed,
        reason: '任务完成',
      );

      final done = coordinator.taskOf(task.id)!;
      expect(done.isComplete, isTrue);
      expect(done.downloadedSize, 96);
      expect(done.fileSize, 96);
      expect(done.filePath, isNotNull);
      expect(await File(done.filePath!).readAsBytes(), content);

      // 完成后已落盘到 store。
      expect(store.getById(task.id)!.status, DownloadStatus.completed);
    });

    test('并发上限内仅调度允许数量的任务', () async {
      final coordinator = coordinatorWith(
        transportFactory: () => BlockingTransport(),
        maxConcurrent: 1,
      );

      final a = buildTask(bvid: 'BVA', cid: 1, createdAt: 1);
      final b = buildTask(bvid: 'BVB', cid: 1, createdAt: 2);
      final c = buildTask(bvid: 'BVC', cid: 1, createdAt: 3);
      await coordinator.enqueue(a);
      await coordinator.enqueue(b);
      await coordinator.enqueue(c);

      // A 抢占唯一槽位并阻塞在「下载中」，B/C 保持排队。
      await waitUntil(
        () => coordinator.taskOf(a.id)?.status == DownloadStatus.downloading,
        reason: 'A 开始下载',
      );
      expect(coordinator.taskOf(b.id)!.status, DownloadStatus.queued);
      expect(coordinator.taskOf(c.id)!.status, DownloadStatus.queued);
      expect(coordinator.hasActiveDownloads, isTrue);

      await disposeAndSettle(coordinator);
    });

    test('暂停运行中任务后槽位释放给下一个', () async {
      final coordinator = coordinatorWith(
        transportFactory: () => BlockingTransport(),
        maxConcurrent: 1,
      );

      final a = buildTask(bvid: 'BVA', cid: 1, createdAt: 1);
      final b = buildTask(bvid: 'BVB', cid: 1, createdAt: 2);
      await coordinator.enqueue(a);
      await coordinator.enqueue(b);

      await waitUntil(
        () => coordinator.taskOf(a.id)?.status == DownloadStatus.downloading,
        reason: 'A 开始下载',
      );

      await coordinator.pause(a.id);

      await waitUntil(
        () => coordinator.taskOf(a.id)?.status == DownloadStatus.paused,
        reason: 'A 转为暂停',
      );
      await waitUntil(
        () => coordinator.taskOf(b.id)?.status == DownloadStatus.downloading,
        reason: 'B 被调度',
      );
      expect(store.getById(a.id)!.status, DownloadStatus.paused);

      await disposeAndSettle(coordinator);
    });

    test('恢复暂停任务重新入队（保留续传字节）', () async {
      final coordinator = coordinatorWith(
        transportFactory: () => BlockingTransport(),
        maxConcurrent: 1,
      );

      final a = buildTask(bvid: 'BVA', cid: 1);
      await coordinator.enqueue(a);
      await waitUntil(
        () => coordinator.taskOf(a.id)?.status == DownloadStatus.downloading,
        reason: 'A 开始下载',
      );
      await coordinator.pause(a.id);
      await waitUntil(
        () => coordinator.taskOf(a.id)?.status == DownloadStatus.paused,
        reason: 'A 转为暂停',
      );

      await coordinator.resume(a.id);
      await waitUntil(
        () => coordinator.taskOf(a.id)?.status == DownloadStatus.downloading,
        reason: 'A 恢复下载',
      );

      await disposeAndSettle(coordinator);
    });

    test('探测失败时任务标记 failed 并记录原因', () async {
      final coordinator = coordinatorWith(
        transportFactory: () =>
            FakeTransport(content: makeContent(10), probeError: StateError('boom')),
      );

      final task = buildTask(bvid: 'BV1', cid: 1);
      await coordinator.enqueue(task);

      await waitUntil(
        () => coordinator.taskOf(task.id)?.status == DownloadStatus.failed,
        reason: '任务失败',
      );

      final failed = coordinator.taskOf(task.id)!;
      expect(failed.isFailed, isTrue);
      expect(failed.errorMessage, isNotNull);
      expect(failed.errorMessage, contains('探测失败'));

      // 失败后重试应清空旧错误并回到队列。
      await coordinator.retry(task.id);
      final retried = coordinator.taskOf(task.id)!;
      expect(retried.status, isNot(DownloadStatus.failed));
      expect(retried.errorMessage, isNull);
    });

    test('remove 移除任务记录', () async {
      final coordinator = coordinatorWith(
        transportFactory: () => BlockingTransport(),
      );

      final a = buildTask(bvid: 'BVA', cid: 1);
      await coordinator.enqueue(a);
      await waitUntil(
        () => coordinator.taskOf(a.id)?.status == DownloadStatus.downloading,
        reason: 'A 开始下载',
      );

      await coordinator.remove(a.id);
      expect(coordinator.taskOf(a.id), isNull);
      expect(store.getById(a.id), isNull);

      await disposeAndSettle(coordinator);
    });

    test('restore 把上次中断的 downloading 复位为 queued', () async {
      final interrupted =
          buildTask(bvid: 'BV1', cid: 1).copyWith(status: DownloadStatus.downloading);
      await store.save(interrupted);

      final coordinator = coordinatorWith(
        transportFactory: () => BlockingTransport(),
      );
      coordinator.restore();

      expect(coordinator.taskOf(interrupted.id)!.status, DownloadStatus.queued);
    });

    test('restore 保留 completed / paused 原态', () async {
      await store.save(
        buildTask(bvid: 'BV1', cid: 1).copyWith(status: DownloadStatus.completed),
      );
      await store.save(
        buildTask(bvid: 'BV2', cid: 2).copyWith(status: DownloadStatus.paused),
      );

      final coordinator =
          coordinatorWith(transportFactory: () => BlockingTransport());
      coordinator.restore();

      expect(coordinator.taskOf('BV1_1_80')!.status, DownloadStatus.completed);
      expect(coordinator.taskOf('BV2_2_80')!.status, DownloadStatus.paused);
    });
  });
}