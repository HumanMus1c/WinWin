// Phase 5 下载系统 · 批次3：任务持久化仓储。
//
// 纯仓储层：把 [DownloadTask] 的增删改查收敛到单一入口，屏蔽 Hive 细节。
//
// 存储后端通过 [DownloadTaskStorage] 抽象注入（生产用 Hive box，单测用内存实现），
// 与批次2 的 [DownloadTransport] 注入思路一致——持久化 / 传输 / 编排三层各自可单测。
//
// 序列化沿用 [DownloadTask.toJson] / [DownloadTask.fromJson]；读取时对单条脏数据
// 容错跳过，避免一条损坏记录导致整个下载列表不可用。

import 'package:hive_ce/hive.dart';

import 'package:winwin/models/download/download_task.dart';

/// 任务存储后端抽象：以「任务 id → JSON」为最小契约。
abstract interface class DownloadTaskStorage {
  /// 读取单条（不存在返回 null）。
  Map<String, dynamic>? read(String id);

  /// 全量读取（id → JSON）。
  Map<String, dynamic> readAll();

  /// 写入 / 覆盖单条。
  Future<void> write(String id, Map<String, dynamic> value);

  /// 删除单条（不存在时静默）。
  Future<void> delete(String id);

  /// 清空全部。
  Future<void> clear();
}

/// 基于 Hive box 的 [DownloadTaskStorage] 实现。
///
/// box 由 `GStorage.init()` 打开（见 `lib/core/storage/storage.dart` 的 `download`）。
class HiveDownloadTaskStorage implements DownloadTaskStorage {
  HiveDownloadTaskStorage(this._box);

  final Box<dynamic> _box;

  @override
  Map<String, dynamic>? read(String id) {
    final value = _box.get(id);
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  @override
  Map<String, dynamic> readAll() => <String, dynamic>{
        for (final key in _box.keys)
          if (key is String && _box.get(key) is Map)
            key: Map<String, dynamic>.from(_box.get(key) as Map),
      };

  @override
  Future<void> write(String id, Map<String, dynamic> value) =>
      _box.put(id, value);

  @override
  Future<void> delete(String id) => _box.delete(id);

  @override
  Future<void> clear() => _box.clear();
}

/// 下载任务仓储。
///
/// 单一事实源：队列调度器（见 `download_queue.dart`）的一切读写都经由此处，
/// 从而保证内存态与磁盘态不会各自发散。
class DownloadStore {
  DownloadStore({required this.storage});

  final DownloadTaskStorage storage;

  /// 全量任务，按 `createdAt` 升序、`id` 升序排序（与队列调度选队规则一致）。
  ///
  /// 无法解析的脏记录被跳过（不抛出），保证列表可用性。
  List<DownloadTask> loadAll() {
    final items = <DownloadTask>[];
    final raw = storage.readAll();
    for (final entry in raw.entries) {
      final parsed = _tryParse(entry.value);
      if (parsed != null) items.add(parsed);
    }
    items.sort(_compareTasks);
    return items;
  }

  /// 读取单条任务；不存在或脏数据返回 null。
  DownloadTask? getById(String id) {
    final value = storage.read(id);
    if (value == null) return null;
    return _tryParse(value);
  }

  /// 写入 / 覆盖单条任务。
  Future<void> save(DownloadTask task) => storage.write(task.id, task.toJson());

  /// 批量写入。
  Future<void> saveAll(Iterable<DownloadTask> tasks) => Future.wait(
        tasks.map((task) => storage.write(task.id, task.toJson())),
      );

  /// 删除单条任务（不触碰已落盘文件）。
  Future<void> remove(String id) => storage.delete(id);

  /// 清空全部任务记录（不触碰已落盘文件）。
  Future<void> clear() => storage.clear();

  static int _compareTasks(DownloadTask a, DownloadTask b) {
    final byTime = a.createdAt.compareTo(b.createdAt);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  }

  static DownloadTask? _tryParse(Object? value) {
    if (value is! Map) return null;
    try {
      return DownloadTask.fromJson(Map<String, dynamic>.from(value));
    } catch (_) {
      return null;
    }
  }
}