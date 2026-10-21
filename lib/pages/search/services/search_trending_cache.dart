import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/search.dart';
import 'package:winwin/models/search/result.dart';

/// 热搜榜的**进程内 TTL 缓存 + 预取**（单一实现）。
///
/// ## 为何要它（根因）
///
/// 搜索面板每次进入都会重新拉热搜（`SearchContentPanel.initState`）。而
/// 「加载中（矮）」→「已加载（高）」的**面板内在高度跳变**若落在 220ms 的展开
/// 动画窗口内，会触发 `RenderAnimatedSize` 把尺寸动画**从 0 重跑**
/// （`_restartAnimation()` ⇒ `forward(from: 0)`）——即用户看到的"顿挫"。
///
/// 本服务把热搜结果**缓存 [ttl] 并支持首帧静默预取**：用户点搜索框时数据多已
/// 就绪，从源头减少"动画途中换高度"的竞态（详见
/// `docs/搜索态扩充动效与合并栏阴影复盘-2026-10-21.md`）。
class SearchTrendingCache {
  SearchTrendingCache._();

  static final SearchTrendingCache instance = SearchTrendingCache._();

  /// 缓存有效期：热搜变化不频繁，过期后重新拉取。
  static const Duration ttl = Duration(minutes: 5);

  List<SearchTrendingItemModel>? _items;
  DateTime? _fetchedAt;
  Future<List<SearchTrendingItemModel>>? _inflight;

  /// 命中且未过期 → 返回缓存；否则 null（调用方可先落骨架）。
  List<SearchTrendingItemModel>? peek() {
    final items = _items;
    final at = _fetchedAt;
    if (items == null || at == null) return null;
    if (DateTime.now().difference(at) > ttl) return null;
    return items;
  }

  /// 取数据：命中缓存直接返回；未命中则**合并并发请求**（去重）后落缓存。
  Future<List<SearchTrendingItemModel>> fetch({int limit = 20}) {
    final cached = peek();
    if (cached != null) return Future.value(cached);
    final inflight = _inflight;
    if (inflight != null) return inflight;
    final future = _doFetch(limit);
    _inflight = future;
    return future;
  }

  Future<List<SearchTrendingItemModel>> _doFetch(int limit) async {
    try {
      final res = await SearchHttp.searchTrending(limit: limit);
      if (res case Success(:final response)) {
        final list = response.list ?? const <SearchTrendingItemModel>[];
        _items = list;
        _fetchedAt = DateTime.now();
        return list;
      }
      // 失败：回落旧值（无则空），由调用方决定展示（空则整块省略）。
      return _items ?? const <SearchTrendingItemModel>[];
    } finally {
      _inflight = null;
    }
  }

  /// 作废缓存（「刷新」入口用：强制下次重新拉取）。
  void invalidate() {
    _items = null;
    _fetchedAt = null;
  }

  /// 静默预取（首页首帧调用）：命中即跳过；失败不抛、不影响调用方。
  void prefetch({int limit = 20}) {
    if (Pref.demoMode) return;
    if (peek() != null) return;
    fetch(limit: limit).then<void>((_) {}, onError: (_) {});
  }
}