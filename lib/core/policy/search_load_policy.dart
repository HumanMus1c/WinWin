// Ported from BiliPai (Kotlin) -> WinWin (Dart)
// Original: com/android/purebilibili/data/repository/SearchLoadPolicy.kt
//
// 搜索结果后处理策略：去重合并、分页协调、时长过滤、过期结果检测。
// 作用在 SearchHttp 拉取原始结果之后、UI 渲染之前。

import 'package:winwin/models/search/result.dart';

/// 搜索结果后处理配置。
class SearchLoadConfig {
  /// 合并相邻分页结果时是否按 bvid 去重。
  final bool deduplicateByBvid;

  /// 视频时长过滤下限（秒），低于此值的视为无效短视频（0=不过滤）。
  final int minDurationSeconds;

  /// 过期结果检测阈值（秒）：pubdate 距今超过此值视为过期。
  /// 默认 180 天，用于排序降权而非剔除。
  final int staleThresholdSeconds;

  /// 单页最大保留条数（0=不限制）。
  final int maxItemsPerPage;

  const SearchLoadConfig({
    this.deduplicateByBvid = true,
    this.minDurationSeconds = 0,
    this.staleThresholdSeconds = 180 * 24 * 3600,
    this.maxItemsPerPage = 0,
  });

  /// 默认配置（桌面端：去重开启、不时长过滤、180 天过期阈值）。
  static const SearchLoadConfig defaultConfig = SearchLoadConfig();
}

/// 搜索结果加载策略。
///
/// 纯函数集合，不持有状态、不触发 I/O。调用方（SearchHttp 或 controller）
/// 在拿到分页数据后调用本策略做后处理。
class SearchLoadPolicy {
  SearchLoadPolicy._();

  /// 合并上一页（已有）与当前页（新拉取）的视频结果。
  ///
  /// 步骤：
  /// 1. 按 [config.deduplicateByBvid] 决定是否去重（bvid 为空时用 aid 兜底）。
  /// 2. 按 [config.minDurationSeconds] 过滤过短视频。
  /// 3. 按 [config.maxItemsPerPage] 截断。
  static List<SearchVideoItemModel> mergeVideoPages(
    List<SearchVideoItemModel> previous,
    List<SearchVideoItemModel> current, {
    SearchLoadConfig config = SearchLoadConfig.defaultConfig,
  }) {
    final seen = <String>{};
    if (config.deduplicateByBvid) {
      for (final item in previous) {
        final key = _dedupKey(item);
        if (key != null) seen.add(key);
      }
    }

    final merged = <SearchVideoItemModel>[...previous];
    for (final item in current) {
      if (config.deduplicateByBvid) {
        final key = _dedupKey(item);
        if (key != null && seen.contains(key)) continue;
        if (key != null) seen.add(key);
      }
      if (config.minDurationSeconds > 0 &&
          (item.duration ?? 0) < config.minDurationSeconds &&
          !item.isLive) {
        continue;
      }
      merged.add(item);
    }

    if (config.maxItemsPerPage > 0 && merged.length > config.maxItemsPerPage) {
      return merged.sublist(0, config.maxItemsPerPage);
    }
    return merged;
  }

  /// 判断搜索结果是否已过期（用于排序降权标记，不剔除）。
  ///
  /// 以当前时间 [now] 与 [item.pubdate] 比较，超过 [config.staleThresholdSeconds]
  /// 视为过期。直播 / 无 pubdate 的条目永不过期。
  static bool isStale(
    SearchVideoItemModel item, {
    DateTime? now,
    SearchLoadConfig config = SearchLoadConfig.defaultConfig,
  }) {
    if (item.isLive) return false;
    final pubdate = item.pubdate;
    if (pubdate == null || pubdate <= 0) return false;
    final nowSec = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    return (nowSec - pubdate) > config.staleThresholdSeconds;
  }

  /// 过期降权排序：非过期结果在前，过期结果在后；同组内保持原顺序（稳定）。
  static List<SearchVideoItemModel> sortByStaleness(
    List<SearchVideoItemModel> items, {
    DateTime? now,
    SearchLoadConfig config = SearchLoadConfig.defaultConfig,
  }) {
    final now_ = now ?? DateTime.now();
    final fresh = <SearchVideoItemModel>[];
    final stale = <SearchVideoItemModel>[];
    for (final item in items) {
      if (isStale(item, now: now_, config: config)) {
        stale.add(item);
      } else {
        fresh.add(item);
      }
    }
    return [...fresh, ...stale];
  }

  /// 计算下一页页码。
  ///
  /// B 站搜索页码从 1 开始，[currentPage] 为当前已加载的最后一页。
  /// [hasMore] 来自响应的 numResults 判断：当累计条数 < numResults 时有更多。
  static int? nextPage({
    required int currentPage,
    required int accumulatedCount,
    int? totalResults,
  }) {
    if (totalResults != null && accumulatedCount >= totalResults) {
      return null;
    }
    return currentPage + 1;
  }

  /// 提取去重 key：优先 bvid，其次 aid 字符串；两者皆空返回 null。
  static String? _dedupKey(SearchVideoItemModel item) {
    final bvid = item.bvid;
    if (bvid != null && bvid.isNotEmpty) return bvid;
    final aid = item.aid;
    if (aid != null && aid > 0) return 'av$aid';
    return null;
  }
}
