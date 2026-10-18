import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/models/download/download_task.dart';

void main() {
  group('DownloadStatus.fromName', () {
    test('命中已知状态名', () {
      expect(DownloadStatus.fromName('downloading'), DownloadStatus.downloading);
      expect(DownloadStatus.fromName('completed'), DownloadStatus.completed);
      expect(DownloadStatus.fromName('merging'), DownloadStatus.merging);
    });

    test('未知 / 空值回退 pending', () {
      expect(DownloadStatus.fromName('mystery'), DownloadStatus.pending);
      expect(DownloadStatus.fromName(null), DownloadStatus.pending);
    });
  });

  group('DownloadTask.id', () {
    test('普通视频 id 含画质', () {
      const task = DownloadTask(bvid: 'BV1', cid: 2, title: 't', quality: 80);
      expect(task.id, 'BV1_2_80');
    });

    test('仅音频 id 固定后缀', () {
      const task = DownloadTask(
        bvid: 'BV1',
        cid: 2,
        title: 't',
        quality: 80,
        isAudioOnly: true,
      );
      expect(task.id, 'BV1_2_audio');
    });
  });

  group('派生状态', () {
    DownloadTask taskWith(DownloadStatus status) =>
        DownloadTask(bvid: 'BV1', cid: 1, title: 't', status: status);

    test('isComplete / isDownloading / canResume / isFailed', () {
      expect(taskWith(DownloadStatus.completed).isComplete, isTrue);
      expect(taskWith(DownloadStatus.downloading).isDownloading, isTrue);
      expect(taskWith(DownloadStatus.merging).isDownloading, isTrue);
      expect(taskWith(DownloadStatus.paused).canResume, isTrue);
      expect(taskWith(DownloadStatus.failed).canResume, isTrue);
      expect(taskWith(DownloadStatus.failed).isFailed, isTrue);
      expect(taskWith(DownloadStatus.pending).isDownloading, isFalse);
      expect(taskWith(DownloadStatus.queued).isComplete, isFalse);
    });
  });

  group('progress（由 downloadedSize/fileSize 派生）', () {
    test('正常比例', () {
      const task = DownloadTask(
        bvid: 'BV1',
        cid: 1,
        title: 't',
        fileSize: 200,
        downloadedSize: 50,
      );
      expect(task.progress, 0.25);
    });

    test('总大小未知时为 0', () {
      const task =
          DownloadTask(bvid: 'BV1', cid: 1, title: 't', downloadedSize: 50);
      expect(task.progress, 0.0);
    });

    test('超出上限被裁剪到 1.0', () {
      const task = DownloadTask(
        bvid: 'BV1',
        cid: 1,
        title: 't',
        fileSize: 100,
        downloadedSize: 300,
      );
      expect(task.progress, 1.0);
    });
  });

  group('JSON 往返', () {
    test('toJson/fromJson 保持字段一致', () {
      const task = DownloadTask(
        bvid: 'BV1',
        aid: 9,
        cid: 2,
        title: '标题',
        cover: 'c',
        ownerName: 'u',
        ownerFace: 'f',
        duration: 300,
        quality: 112,
        qualityDesc: '1080P+',
        videoUrl: 'v',
        audioUrl: 'a',
        groupKey: 'g',
        groupTitle: 'GT',
        episodeSortIndex: 2,
        episodeCount: 5,
        status: DownloadStatus.completed,
        filePath: 'p',
        fileSize: 1000,
        downloadedSize: 1000,
        createdAt: 123,
        options: DownloadOptions(includeDanmaku: false),
      );
      final restored = DownloadTask.fromJson(task.toJson());
      expect(restored.id, task.id);
      expect(restored.title, '标题');
      expect(restored.qualityDesc, '1080P+');
      expect(restored.aid, 9);
      expect(restored.status, DownloadStatus.completed);
      expect(restored.groupKey, 'g');
      expect(restored.groupTitle, 'GT');
      expect(restored.episodeCount, 5);
      expect(restored.filePath, 'p');
      expect(restored.options.includeDanmaku, isFalse);
      expect(restored.progress, 1.0);
    });

    test('fromJson 容忍缺失字段与未知状态', () {
      final restored = DownloadTask.fromJson(<String, dynamic>{
        'bvid': 'BV9',
        'cid': 7,
        'title': 'x',
        'status': 'mystery',
      });
      expect(restored.bvid, 'BV9');
      expect(restored.cid, 7);
      expect(restored.quality, 80);
      expect(restored.episodeCount, 1);
      expect(restored.status, DownloadStatus.pending);
      expect(restored.aid, 0);
      expect(restored.options.includeDanmaku, isTrue);
    });

    test('fromJson 数值字符串容错', () {
      final restored = DownloadTask.fromJson(<String, dynamic>{
        'bvid': 'BV',
        'cid': '12',
        'title': 'x',
        'aid': '3',
      });
      expect(restored.cid, 12);
      expect(restored.aid, 3);
    });
  });

  group('copyWith', () {
    test('覆盖指定字段并保留其余', () {
      const task = DownloadTask(bvid: 'BV1', cid: 1, title: 'a', quality: 80);
      final next = task.copyWith(
        title: 'b',
        quality: 120,
        status: DownloadStatus.queued,
      );
      expect(next.title, 'b');
      expect(next.quality, 120);
      expect(next.status, DownloadStatus.queued);
      expect(next.bvid, 'BV1');
      expect(next.cid, 1);
      expect(next.id, 'BV1_1_120');
    });
  });

  group('DownloadOptions', () {
    test('默认包含弹幕，可关闭并往返', () {
      const options = DownloadOptions();
      expect(options.includeDanmaku, isTrue);
      final restored = DownloadOptions.fromJson(
        options.copyWith(includeDanmaku: false).toJson(),
      );
      expect(restored.includeDanmaku, isFalse);
    });
  });
}