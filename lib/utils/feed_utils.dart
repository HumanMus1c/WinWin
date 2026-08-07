/// Feed 刷新分页与合并工具 — 从 BiliPai FeedRefreshPaging.kt + FeedMergeUtils.kt 移植。
///
/// 纯函数，无副作用，用于推荐流/动态流等列表的刷新与分页合并。

/// 手动"换一批"时的页码决策。
///
/// 无更多内容时回第 1 页；否则返回 max(nextLoadPage, 1)。
int resolveReplaceRefreshPage(int nextLoadPage, bool hasMore) {
  if (!hasMore) return 1;
  return nextLoadPage < 1 ? 1 : nextLoadPage;
}

/// 刷新结果前置到列表头部，按 key 去重。
///
/// incoming 中的新项（key 不在 existing 中）按顺序插到 existing 顶部。
List<T> prependDistinctByKey<T, K>(
  List<T> existing,
  List<T> incoming,
  K Function(T) keySelector,
) {
  if (incoming.isEmpty) return existing;
  final seen = <K>{};
  for (final item in existing) {
    seen.add(keySelector(item));
  }
  final fresh = incoming.where((item) => seen.add(keySelector(item))).toList();
  if (existing.isEmpty) return fresh;
  return [...fresh, ...existing];
}

/// 分页结果追加到列表尾部，按 key 去重。
///
/// incoming 中的新项（key 不在 existing 中）按顺序追加到 existing 尾部。
List<T> appendDistinctByKey<T, K>(
  List<T> existing,
  List<T> incoming,
  K Function(T) keySelector,
) {
  if (incoming.isEmpty) return existing;
  final seen = <K>{};
  for (final item in existing) {
    seen.add(keySelector(item));
  }
  final fresh = incoming.where((item) => seen.add(keySelector(item))).toList();
  if (existing.isEmpty) {
    // 保留首项去重（incoming 内部也可能有重复）
    final deduped = <T>[];
    final innerSeen = <K>{};
    for (final item in fresh) {
      if (innerSeen.add(keySelector(item))) {
        deduped.add(item);
      }
    }
    return deduped;
  }
  return [...existing, ...fresh];
}
