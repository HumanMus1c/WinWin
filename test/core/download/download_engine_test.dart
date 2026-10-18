// Phase 5 下载系统 · 批次2：断点续传下载引擎单测。
//
// 通过 FakeTransport 注入确定性字节流，在无网络条件下验证：
// 续传 / 从头覆盖 / 已完成短路 / 并行分片 / 进度 / 取消 / 长度校验。

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:winwin/core/download/download_engine.dart';
import 'package:winwin/core/download/download_policy.dart';
import 'package:winwin/core/download/download_transport.dart';

/// 确定性字节内容：第 i 字节为 `i % 251`。
List<int> makeContent(int length) =>
    List<int>.generate(length, (index) => index % 251);

/// 假传输：按绝对偏移提供 [content]，可声明不同总大小以模拟校验失败。
class FakeTransport implements DownloadTransport {
  FakeTransport({
    required this.content,
    int? declaredTotal,
    this.supportsRanges = true,
    this.chunkSize = 8,
    this.probeError,
  }) : declaredTotal = declaredTotal ?? content.length;

  final List<int> content;
  final int declaredTotal;
  final bool supportsRanges;
  final int chunkSize;
  final Object? probeError;

  final List<String> fetchCalls = <String>[];
  int probeCount = 0;

  @override
  Future<DownloadRangeProbe> probe({
    required Uri url,
    required Map<String, String> headers,
  }) async {
    probeCount++;
    final error = probeError;
    if (error != null) throw error;
    return DownloadRangeProbe(
      totalBytes: declaredTotal,
      supportsRanges: supportsRanges,
    );
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
    final start = startBytes ?? 0;
    final lastIndex = content.length - 1;
    var end = endBytesInclusive ?? lastIndex;
    if (end > lastIndex) end = lastIndex;
    fetchCalls.add('$start-$end');

    var offset = start;
    while (offset <= end) {
      if (isCancelled?.call() ?? false) {
        throw const DownloadCancelledException();
      }
      final span = math.min(chunkSize, end - offset + 1);
      final data = content.sublist(offset, offset + span);
      await onChunk(data, offset);
      offset += span;
    }
  }

  @override
  void close() {}
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('winwin_dl_engine_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  String pathOf(String name) => '${tempDir.path}${Platform.pathSeparator}$name';

  DownloadEngine engineWith(
    FakeTransport transport, {
    int maxChunks = DownloadRangePolicy.defaultMaxChunks,
    int threshold = DownloadRangePolicy.defaultParallelChunkThresholdBytes,
  }) =>
      DownloadEngine(
        transport: transport,
        maxChunks: maxChunks,
        parallelChunkThresholdBytes: threshold,
      );

  group('DownloadEngine 下载', () {
    test('无既有数据时完整下载到文件', () async {
      final content = makeContent(100);
      final transport = FakeTransport(content: content);
      final engine = engineWith(transport);
      final path = pathOf('full.mp4');

      final outcome = await engine.download(
        url: Uri.parse('https://cdn.example.com/v.mp4'),
        savePath: path,
      );

      expect(outcome.status, DownloadFinishStatus.completed);
      expect(outcome.isCompleted, isTrue);
      expect(outcome.totalBytes, 100);
      expect(outcome.downloadedBytes, 100);
      expect(outcome.resumed, isFalse);
      expect(outcome.usedParallelChunks, isFalse);
      expect(await File(path).readAsBytes(), content);
      expect(transport.fetchCalls, <String>['0-99']);
    });

    test('支持 Range 时从断点续传，仅请求剩余区间', () async {
      final content = makeContent(120);
      final path = pathOf('resume.mp4');
      await File(path).writeAsBytes(content.sublist(0, 45));

      final transport = FakeTransport(content: content);
      final engine = engineWith(transport);

      final outcome = await engine.download(
        url: Uri.parse('https://cdn.example.com/resume.mp4'),
        savePath: path,
      );

      expect(outcome.status, DownloadFinishStatus.completed);
      expect(outcome.resumed, isTrue);
      expect(transport.fetchCalls, <String>['45-119']);
      expect(await File(path).readAsBytes(), content);
    });

    test('已下载完整时短路，不再发起请求', () async {
      final content = makeContent(80);
      final path = pathOf('done.mp4');
      await File(path).writeAsBytes(content);

      final transport = FakeTransport(content: content);
      final engine = engineWith(transport);

      final outcome = await engine.download(
        url: Uri.parse('https://cdn.example.com/done.mp4'),
        savePath: path,
      );

      expect(outcome.status, DownloadFinishStatus.completed);
      expect(outcome.resumed, isTrue);
      expect(transport.probeCount, 1);
      expect(transport.fetchCalls, isEmpty);
    });

    test('服务器不支持 Range 时忽略既有数据并从头覆盖', () async {
      final content = makeContent(90);
      final path = pathOf('overwrite.mp4');
      await File(path).writeAsBytes(content.sublist(0, 30));

      final transport = FakeTransport(content: content, supportsRanges: false);
      final engine = engineWith(transport);

      final outcome = await engine.download(
        url: Uri.parse('https://cdn.example.com/overwrite.mp4'),
        savePath: path,
      );

      expect(outcome.status, DownloadFinishStatus.completed);
      expect(outcome.resumed, isFalse);
      expect(transport.fetchCalls, <String>['0-89']);
      expect(await File(path).readAsBytes(), content);
    });

    test('大资源走并行分片，按绝对偏移正确拼装', () async {
      final content = makeContent(40);
      final transport = FakeTransport(content: content, chunkSize: 5);
      final engine = engineWith(transport, maxChunks: 4, threshold: 16);
      final path = pathOf('chunked.mp4');

      final outcome = await engine.download(
        url: Uri.parse('https://cdn.example.com/chunked.mp4'),
        savePath: path,
      );

      expect(outcome.status, DownloadFinishStatus.completed);
      expect(outcome.usedParallelChunks, isTrue);
      expect(transport.fetchCalls.length, 4);
      expect(transport.fetchCalls.toSet(), <String>{'0-9', '10-19', '20-29', '30-39'});
      expect(await File(path).readAsBytes(), content);
    });

    test('进度回调单调递增并以总大小收尾', () async {
      final content = makeContent(50);
      final transport = FakeTransport(content: content, chunkSize: 7);
      final engine = engineWith(transport);
      final path = pathOf('progress.mp4');
      final progress = <DownloadProgress>[];

      final outcome = await engine.download(
        url: Uri.parse('https://cdn.example.com/progress.mp4'),
        savePath: path,
        onProgress: progress.add,
      );

      expect(outcome.status, DownloadFinishStatus.completed);
      expect(progress, isNotEmpty);
      expect(progress.first.downloadedBytes, greaterThan(0));
      expect(progress.last.downloadedBytes, 50);
      expect(progress.last.totalBytes, 50);
      expect(progress.last.fraction, 1);
      for (var i = 1; i < progress.length; i++) {
        expect(
          progress[i].downloadedBytes,
          greaterThanOrEqualTo(progress[i - 1].downloadedBytes),
        );
      }
    });

    test('总大小未知时顺序下载并以实际落盘长度为准', () async {
      final content = makeContent(64);
      final transport = FakeTransport(
        content: content,
        declaredTotal: 0,
        supportsRanges: false,
      );
      final engine = engineWith(transport);
      final path = pathOf('unknown.mp4');

      final outcome = await engine.download(
        url: Uri.parse('https://cdn.example.com/unknown.mp4'),
        savePath: path,
      );

      expect(outcome.status, DownloadFinishStatus.completed);
      expect(outcome.totalBytes, 64);
      expect(outcome.usedParallelChunks, isFalse);
      expect(await File(path).readAsBytes(), content);
    });

    test('取消后返回 cancelled 并保留已落盘部分', () async {
      final content = makeContent(100);
      final transport = FakeTransport(content: content, chunkSize: 10);
      final engine = engineWith(transport);
      final path = pathOf('cancel.mp4');
      var progressCalls = 0;

      final outcome = await engine.download(
        url: Uri.parse('https://cdn.example.com/cancel.mp4'),
        savePath: path,
        onProgress: (_) => progressCalls++,
        isCancelled: () => progressCalls >= 2,
      );

      expect(outcome.status, DownloadFinishStatus.cancelled);
      expect(outcome.isCancelled, isTrue);
      final saved = await File(path).readAsBytes();
      expect(saved.length, 20);
      expect(saved, content.sublist(0, 20));
    });

    test('启动前即取消则不发起探测', () async {
      final transport = FakeTransport(content: makeContent(20));
      final engine = engineWith(transport);

      final outcome = await engine.download(
        url: Uri.parse('https://cdn.example.com/x.mp4'),
        savePath: pathOf('precancel.mp4'),
        isCancelled: () => true,
      );

      expect(outcome.status, DownloadFinishStatus.cancelled);
      expect(outcome.downloadedBytes, 0);
      expect(transport.probeCount, 0);
    });

    test('探测抛错时返回 failed 并携带原因', () async {
      final transport = FakeTransport(
        content: makeContent(20),
        probeError: StateError('boom'),
      );
      final engine = engineWith(transport);

      final outcome = await engine.download(
        url: Uri.parse('https://cdn.example.com/err.mp4'),
        savePath: pathOf('err.mp4'),
      );

      expect(outcome.status, DownloadFinishStatus.failed);
      expect(outcome.isFailed, isTrue);
      expect(outcome.error, contains('探测失败'));
    });

    test('落盘长度与声明不符时判定失败', () async {
      final content = makeContent(60);
      final transport = FakeTransport(
        content: content,
        declaredTotal: 100,
        supportsRanges: false,
      );
      final engine = engineWith(transport);
      final path = pathOf('mismatch.mp4');

      final outcome = await engine.download(
        url: Uri.parse('https://cdn.example.com/mismatch.mp4'),
        savePath: path,
      );

      expect(outcome.status, DownloadFinishStatus.failed);
      expect(outcome.error, contains('长度校验不符'));
      expect(outcome.downloadedBytes, 60);
    });

    test('自动创建目标文件的父目录', () async {
      final content = makeContent(30);
      final transport = FakeTransport(content: content);
      final engine = engineWith(transport);
      final path =
          '${tempDir.path}${Platform.pathSeparator}a${Platform.pathSeparator}b${Platform.pathSeparator}leaf.mp4';

      final outcome = await engine.download(
        url: Uri.parse('https://cdn.example.com/nested.mp4'),
        savePath: path,
      );

      expect(outcome.status, DownloadFinishStatus.completed);
      expect(await File(path).readAsBytes(), content);
    });

    test('未注入传输实现时抛 StateError', () async {
      final engine = DownloadEngine();

      await expectLater(
        engine.download(
          url: Uri.parse('https://cdn.example.com/n.mp4'),
          savePath: pathOf('none.mp4'),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('DownloadProgress', () {
    test('总大小未知时 fraction 为 0', () {
      const progress = DownloadProgress(downloadedBytes: 10, totalBytes: 0);
      expect(progress.fraction, 0);
    });

    test('超出总大小时 fraction 收敛到 1', () {
      const progress = DownloadProgress(downloadedBytes: 120, totalBytes: 100);
      expect(progress.fraction, 1);
    });
  });
}