// Phase 5 下载系统 · 批次3：任务持久化仓储单测。
//
// 用内存后端 [MemoryDownloadTaskStorage] 驱动，验证排序 / 往返 / 删除 / 清空 /
// 脏记录容错，无需 Hive。

import 'package:flutter_test/flutter_test.dart';

import 'package:winwin/core/download/download_store.dart';
import 'package:winwin/models/download/download_task.dart';

/// 内存后端：直接把 JSON Map 存在内存，便于构造脏数据。
class MemoryDownloadTaskStorage implements DownloadTaskStorage {
  final Map<String, Object?> data = <String, Object?>{};

  @override
  Map<String, dynamic>? read(String id) {
    final value = data[id];
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  @override
  Map<String, dynamic> readAll() => Map<String, dynamic>.from(data);

  @override
  Future<void> write(String id, Map<String, dynamic> value) async {
    data[id] = value;
  }

  @override
  Future<void> delete(String id) async {
    data.remove(id);
  }

  @override
  Future<void> clear() async {
    data.clear();
  }
}

DownloadTask buildTask({
  required String bvid,
  required int cid,
  int quality = 80,
  int createdAt = 0,
  DownloadStatus status = DownloadStatus.pending,
}) =>
    DownloadTask(
      bvid: bvid,
      cid: cid,
      title: '标题 $bvid',
      quality: quality,
      createdAt: createdAt,
      status: status,
    );

void main() {
  late MemoryDownloadTaskStorage storage;
  late DownloadStore store;

  setUp(() {
    storage = MemoryDownloadTaskStorage();
    store = DownloadStore(storage: storage);
  });

  group('DownloadStore', () {
    test('save / getById 往返保持字段', () async {
      final task = buildTask(bvid: 'BV1', cid: 10, quality: 112, createdAt: 5)
          .copyWith(fileSize: 2048, downloadedSize: 1024);
      await store.save(task);

      final loaded = store.getById(task.id);
      expect(loaded, isNotNull);
      expect(loaded!.bvid, 'BV1');
      expect(loaded.cid, 10);
      expect(loaded.quality, 112);
      expect(loaded.fileSize, 2048);
      expect(loaded.downloadedSize, 1024);
      expect(loaded.progress, 0.5);
    });

    test('loadAll 按 createdAt 升序、同值按 id 升序', () async {
      await store.save(buildTask(bvid: 'BV2', cid: 1, createdAt: 20));
      await store.save(buildTask(bvid: 'BV1', cid: 9, createdAt: 10));
      await store.save(buildTask(bvid: 'BV1', cid: 2, createdAt: 10));

      final all = store.loadAll();
      expect(all.map((t) => t.id).toList(),
          <String>['BV1_2_80', 'BV1_9_80', 'BV2_1_80']);
    });

    test('仅音频任务 id 带 _audio 后缀', () async {
      final audio = buildTask(bvid: 'BV9', cid: 3).copyWith(isAudioOnly: true);
      await store.save(audio);
      expect(store.getById('BV9_3_audio'), isNotNull);
    });

    test('remove 删除单条', () async {
      final task = buildTask(bvid: 'BV1', cid: 1);
      await store.save(task);
      await store.remove(task.id);
      expect(store.getById(task.id), isNull);
      expect(store.loadAll(), isEmpty);
    });

    test('clear 清空全部', () async {
      await store.save(buildTask(bvid: 'BV1', cid: 1));
      await store.save(buildTask(bvid: 'BV2', cid: 2));
      await store.clear();
      expect(store.loadAll(), isEmpty);
    });

    test('loadAll 跳过非 Map 脏记录，其余仍可读', () async {
      await store.save(buildTask(bvid: 'BV1', cid: 1));
      storage.data['broken'] = 'not-a-map';

      final all = store.loadAll();
      expect(all.length, 1);
      expect(all.single.bvid, 'BV1');
      expect(store.getById('broken'), isNull);
    });

    test('未知状态字符串回退为 pending（旧数据兼容）', () {
      storage.data['BV1_1_80'] = <String, dynamic>{
        'bvid': 'BV1',
        'cid': 1,
        'status': 'someLegacyStatus',
      };
      final loaded = store.getById('BV1_1_80');
      expect(loaded, isNotNull);
      expect(loaded!.status, DownloadStatus.pending);
    });

    test('saveAll 批量写入', () async {
      await store.saveAll(<DownloadTask>[
        buildTask(bvid: 'BV1', cid: 1),
        buildTask(bvid: 'BV2', cid: 2),
      ]);
      expect(store.loadAll().length, 2);
    });
  });
}