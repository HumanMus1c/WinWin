// CDN 候选失败记忆与按候选冷却（纯逻辑，无 IO / 网络）。
//
// 背景：播放器自愈此前只会按 `(index + 1) % n` 轮换候选，坏节点会在
// 下一轮再次被撞上。本策略按候选 URL 记录连续失败次数并指数退避，
// 自愈/换源时优先跳过冷却中的候选；全部候选都在冷却时退回顺序轮换。

import 'package:flutter/foundation.dart';

/// 单条 CDN 候选的失败记录。
@immutable
class CdnFailureRecord {
  const CdnFailureRecord({
    required this.failures,
    required this.lastFailureAt,
  });

  /// 连续失败次数（成功播放后清零）。
  final int failures;

  /// 最近一次失败时刻。
  final DateTime lastFailureAt;
}

/// CDN 候选失败记忆与按候选冷却策略。
class CdnFailoverPolicy {
  CdnFailoverPolicy({
    this.backoff = const [
      Duration(seconds: 30),
      Duration(minutes: 2),
      Duration(minutes: 10),
    ],
    DateTime Function()? clock,
  }) : assert(backoff.isNotEmpty),
       _clock = clock ?? DateTime.now;

  /// 连续失败 1 / 2 / 3+ 次对应的冷却时长（超出列表按最后一档）。
  final List<Duration> backoff;

  final DateTime Function() _clock;
  final Map<String, CdnFailureRecord> _records = {};

  /// 失败记录上限：超出后按最近失败时间淘汰最旧条目。
  static const int _maxEntries = 64;

  /// 记录一次失败；同一候选连续失败次数递增。
  void recordFailure(String url, {DateTime? now}) {
    if (url.isEmpty) return;
    final at = now ?? _clock();
    final previous = _records[url];
    _records[url] = CdnFailureRecord(
      failures: (previous?.failures ?? 0) + 1,
      lastFailureAt: at,
    );
    _prune(at);
  }

  /// 候选成功播放后清零失败记忆。
  void recordSuccess(String url) {
    if (url.isEmpty) return;
    _records.remove(url);
  }

  /// 该候选是否仍在冷却窗口内。
  bool shouldSkip(String url, {DateTime? now}) {
    final record = _records[url];
    if (record == null) return false;
    final at = now ?? _clock();
    return at.isBefore(record.lastFailureAt.add(_backoffFor(record.failures)));
  }

  /// 返回下一个可用候选下标；[currentIndex] 传 -1 表示从列表头开始。
  ///
  /// [excludeCurrent] 为 true 时保证返回不同于当前的下标（用于自愈/重开
  /// 必须换源的场景）；全部候选都在冷却时退回顺序轮换，避免无候选可用。
  int? nextIndex(
    List<String> candidates,
    int currentIndex, {
    bool excludeCurrent = false,
    DateTime? now,
  }) {
    if (candidates.isEmpty) return null;
    final at = now ?? _clock();
    final count = candidates.length;
    final start = currentIndex >= 0 && currentIndex < count
        ? currentIndex
        : -1;
    final maxStep = excludeCurrent ? count - 1 : count;
    for (var step = 1; step <= maxStep; step++) {
      final index = (start + step) % count;
      if (!shouldSkip(candidates[index], now: at)) return index;
    }
    return (start + 1) % count;
  }

  /// 清空全部失败记忆。
  void reset() => _records.clear();

  /// 某候选当前的连续失败次数（测试/诊断用）。
  @visibleForTesting
  int failureCount(String url) => _records[url]?.failures ?? 0;

  Duration _backoffFor(int failures) {
    final index = failures <= 0 ? 0 : failures - 1;
    return backoff[index < backoff.length ? index : backoff.length - 1];
  }

  void _prune(DateTime now) {
    _records.removeWhere((_, record) {
      final until = record.lastFailureAt.add(_backoffFor(record.failures));
      return !now.isBefore(until);
    });
    if (_records.length <= _maxEntries) return;
    final entries = _records.entries.toList()
      ..sort((a, b) => a.value.lastFailureAt.compareTo(b.value.lastFailureAt));
    for (final entry in entries.take(_records.length - _maxEntries)) {
      _records.remove(entry.key);
    }
  }
}
