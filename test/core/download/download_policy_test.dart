import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/core/download/download_policy.dart';
import 'package:winwin/models/download/download_task.dart';

DownloadTask _task({
  String bvid = 'BV',
  int cid = 1,
  DownloadStatus status = DownloadStatus.queued,
  int createdAt = 0,
  int quality = 80,
}) =>
    DownloadTask(
      bvid: bvid,
      cid: cid,
      title: 't',
      status: status,
      createdAt: createdAt,
      quality: quality,
    );

void main() {
  group('DownloadQueuePolicy.isDownloadTaskActive', () {
    test('活跃态仅 pending/downloading/merging', () {
      expect(
        DownloadQueuePolicy.isDownloadTaskActive(
          _task(status: DownloadStatus.pending),
        ),
        isTrue,
      );
      expect(
        DownloadQueuePolicy.isDownloadTaskActive(
          _task(status: DownloadStatus.downloading),
        ),
        isTrue,
      );
      expect(
        DownloadQueuePolicy.isDownloadTaskActive(
          _task(status: DownloadStatus.merging),
        ),
        isTrue,
      );
      expect(
        DownloadQueuePolicy.isDownloadTaskActive(
          _task(status: DownloadStatus.queued),
        ),
        isFalse,
      );
      expect(
        DownloadQueuePolicy.isDownloadTaskActive(
          _task(status: DownloadStatus.paused),
        ),
        isFalse,
      );
      expect(
        DownloadQueuePolicy.isDownloadTaskActive(
          _task(status: DownloadStatus.completed),
        ),
        isFalse,
      );
      expect(
        DownloadQueuePolicy.isDownloadTaskActive(
          _task(status: DownloadStatus.failed),
        ),
        isFalse,
      );
    });
  });

  group('DownloadQueuePolicy.resolveNextQueuedDownloadTaskIds', () {
    test('按剩余槽位选取，先 createdAt 再 id', () {
      final tasks = <DownloadTask>[
        _task(bvid: 'B', cid: 2, createdAt: 20),
        _task(bvid: 'A', cid: 1, createdAt: 10),
        _task(bvid: 'A', cid: 0, createdAt: 10),
        _task(bvid: 'C', cid: 3, createdAt: 30),
      ];
      final picked = DownloadQueuePolicy.resolveNextQueuedDownloadTaskIds(
        tasks,
        maxConcurrent: 3,
      );
      expect(picked, <String>['A_0_80', 'A_1_80', 'B_2_80']);
    });

    test('并发已满返回空', () {
      final tasks = <DownloadTask>[
        _task(status: DownloadStatus.downloading),
        _task(status: DownloadStatus.pending),
        _task(status: DownloadStatus.queued),
      ];
      expect(
        DownloadQueuePolicy.resolveNextQueuedDownloadTaskIds(
          tasks,
          maxConcurrent: 2,
        ),
        isEmpty,
      );
    });

    test('无排队任务返回空', () {
      final tasks = <DownloadTask>[_task(status: DownloadStatus.downloading)];
      expect(
        DownloadQueuePolicy.resolveNextQueuedDownloadTaskIds(tasks),
        isEmpty,
      );
    });
  });

  group('DownloadQueuePolicy.shouldRefreshStaleDownloadUrls', () {
    const threshold = DownloadQueuePolicy.staleDownloadUrlRefreshThresholdMs;

    test('达到阈值需刷新，差 1ms 不刷新', () {
      expect(
        DownloadQueuePolicy.shouldRefreshStaleDownloadUrls(
          createdAtMs: 1000,
          nowMs: 1000 + threshold,
        ),
        isTrue,
      );
      expect(
        DownloadQueuePolicy.shouldRefreshStaleDownloadUrls(
          createdAtMs: 1000,
          nowMs: 1000 + threshold - 1,
        ),
        isFalse,
      );
    });

    test('非法时间返回 false', () {
      expect(
        DownloadQueuePolicy.shouldRefreshStaleDownloadUrls(
          createdAtMs: 0,
          nowMs: 999999,
        ),
        isFalse,
      );
      expect(
        DownloadQueuePolicy.shouldRefreshStaleDownloadUrls(
          createdAtMs: 500,
          nowMs: 400,
        ),
        isFalse,
      );
    });
  });

  group('DownloadResumePolicy.resolveResumableDownloadPlan', () {
    test('已下载满 → alreadyComplete', () {
      final plan = DownloadResumePolicy.resolveResumableDownloadPlan(
        existingBytes: 100,
        totalBytes: 100,
        acceptsRanges: true,
      );
      expect(plan.alreadyComplete, isTrue);
      expect(plan.append, isFalse);
      expect(plan.rangeStartBytes, 100);
      expect(plan.initialDownloadedBytes, 100);
    });

    test('支持 Range 且部分已下 → 追加续传', () {
      final plan = DownloadResumePolicy.resolveResumableDownloadPlan(
        existingBytes: 40,
        totalBytes: 100,
        acceptsRanges: true,
      );
      expect(plan.append, isTrue);
      expect(plan.rangeStartBytes, 40);
      expect(plan.initialDownloadedBytes, 40);
      expect(plan.totalBytes, 100);
      expect(plan.alreadyComplete, isFalse);
    });

    test('不支持 Range → 从头开始', () {
      final plan = DownloadResumePolicy.resolveResumableDownloadPlan(
        existingBytes: 40,
        totalBytes: 100,
        acceptsRanges: false,
      );
      expect(plan.append, isFalse);
      expect(plan.rangeStartBytes, 0);
      expect(plan.initialDownloadedBytes, 0);
      expect(plan.totalBytes, 100);
    });

    test('负数被归零', () {
      final plan = DownloadResumePolicy.resolveResumableDownloadPlan(
        existingBytes: -5,
        totalBytes: -9,
        acceptsRanges: true,
      );
      expect(plan.alreadyComplete, isFalse);
      expect(plan.totalBytes, 0);
      expect(plan.rangeStartBytes, 0);
      expect(plan.append, isFalse);
    });
  });

  group('DownloadRangePolicy.parseContentRange', () {
    test('常规解析', () {
      final probe = DownloadRangePolicy.parseContentRange('bytes 0-1023/4096');
      expect(probe, isNotNull);
      expect(probe!.totalBytes, 4096);
      expect(probe.supportsRanges, isTrue);
    });

    test('含首尾空格与未知总长', () {
      final probe = DownloadRangePolicy.parseContentRange('  bytes 0-1023/*  ');
      expect(probe, isNotNull);
      expect(probe!.totalBytes, 1024);
    });

    test('无法解析返回 null', () {
      expect(DownloadRangePolicy.parseContentRange(null), isNull);
      expect(DownloadRangePolicy.parseContentRange(''), isNull);
      expect(DownloadRangePolicy.parseContentRange('garbage'), isNull);
    });
  });

  group('DownloadRangePolicy.resolveChunkRanges', () {
    test('整除均分且首尾正确', () {
      final ranges = DownloadRangePolicy.resolveChunkRanges(
        totalBytes: 400,
        maxChunks: 4,
      );
      expect(ranges.length, 4);
      expect(ranges.map((r) => r.sizeBytes).toList(), <int>[100, 100, 100, 100]);
      expect(ranges.first.startBytes, 0);
      expect(ranges.last.endBytesInclusive, 399);
    });

    test('余数前置分配，区间无重叠无空洞', () {
      final ranges = DownloadRangePolicy.resolveChunkRanges(
        totalBytes: 10,
        maxChunks: 4,
      );
      expect(ranges.map((r) => r.sizeBytes).toList(), <int>[3, 3, 2, 2]);
      var expectedStart = 0;
      for (final range in ranges) {
        expect(range.startBytes, expectedStart);
        expectedStart = range.endBytesInclusive + 1;
      }
      expect(expectedStart, 10);
    });

    test('分片数不超过总字节数', () {
      final ranges = DownloadRangePolicy.resolveChunkRanges(
        totalBytes: 2,
        maxChunks: 4,
      );
      expect(ranges.length, 2);
    });

    test('非法输入返回单区间', () {
      expect(
        DownloadRangePolicy.resolveChunkRanges(totalBytes: 0)
            .single
            .endBytesInclusive,
        0,
      );
      expect(
        DownloadRangePolicy.resolveChunkRanges(totalBytes: 5, maxChunks: 1)
            .single
            .sizeBytes,
        5,
      );
    });
  });

  group('DownloadRangePolicy.shouldUseParallelChunks', () {
    test('需同时满足支持 Range 与达到阈值', () {
      expect(
        DownloadRangePolicy.shouldUseParallelChunks(
          totalBytes: DownloadRangePolicy.defaultParallelChunkThresholdBytes,
          supportsRanges: true,
        ),
        isTrue,
      );
      expect(
        DownloadRangePolicy.shouldUseParallelChunks(
          totalBytes: DownloadRangePolicy.defaultParallelChunkThresholdBytes - 1,
          supportsRanges: true,
        ),
        isFalse,
      );
      expect(
        DownloadRangePolicy.shouldUseParallelChunks(
          totalBytes: DownloadRangePolicy.defaultParallelChunkThresholdBytes,
          supportsRanges: false,
        ),
        isFalse,
      );
    });
  });

  group('DownloadNamingPolicy', () {
    test('清洗非法字符并折叠', () {
      expect(
        DownloadNamingPolicy.sanitizeFileNamePart('a/b:c*d?e"f<g>h|i'),
        'a_b_c_d_e_f_g_h_i',
      );
      expect(DownloadNamingPolicy.sanitizeFileNamePart('  a   b__c  '), 'a b_c');
      expect(DownloadNamingPolicy.sanitizeFileNamePart('...a...'), 'a');
    });

    test('导出文件名', () {
      expect(
        DownloadNamingPolicy.buildExportFileName(title: '标题', qualityDesc: '1080P'),
        '标题_1080P.mp4',
      );
      expect(
        DownloadNamingPolicy.buildExportFileName(title: '', qualityDesc: ''),
        'video.mp4',
      );
      expect(
        DownloadNamingPolicy.buildExportFileName(
          title: 'x',
          qualityDesc: '',
          extension: '.mkv',
        ),
        'x.mkv',
      );
    });

    test('扩展名推断', () {
      expect(
        DownloadNamingPolicy.resolveVideoExtension('https://x/a/b.m4s?t=1'),
        'mp4',
      );
      expect(DownloadNamingPolicy.resolveVideoExtension('https://x/a/b.flv'), 'flv');
      expect(DownloadNamingPolicy.resolveVideoExtension('https://x/a/b'), 'mp4');
      expect(DownloadNamingPolicy.resolveVideoExtension(null), 'mp4');
      expect(DownloadNamingPolicy.resolveAudioExtension('https://x/a/b.mp3'), 'mp3');
      expect(DownloadNamingPolicy.resolveAudioExtension('https://x/a/b'), 'm4a');
    });
  });

  group('DownloadRequestHeaders', () {
    test('Cookie 头按序拼接非空项', () {
      expect(
        DownloadRequestHeaders.buildCookieHeader(
          sessData: 's',
          biliJct: 'j',
          buvid3: 'b',
        ),
        'SESSDATA=s; bili_jct=j; buvid3=b',
      );
      expect(
        DownloadRequestHeaders.buildCookieHeader(sessData: 's'),
        'SESSDATA=s',
      );
      expect(DownloadRequestHeaders.buildCookieHeader(), '');
    });

    test('请求头含 UA/Referer，Cookie 非空时写入', () {
      final withCookie =
          DownloadRequestHeaders.buildHeaders(cookieHeader: 'SESSDATA=s');
      expect(
        withCookie['User-Agent'],
        DownloadRequestHeaders.bilibiliDownloadUserAgent,
      );
      expect(withCookie['Referer'], 'https://www.bilibili.com');
      expect(withCookie['Cookie'], 'SESSDATA=s');
      expect(
        DownloadRequestHeaders.buildHeaders().containsKey('Cookie'),
        isFalse,
      );
    });
  });
}