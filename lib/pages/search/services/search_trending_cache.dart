import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/search.dart';
import 'package:winwin/models/search/result.dart';

/// 热搜榜的**进程内单次缓存 + 启动预取**（单一实现）。
///
/// ## 拉取口径（2026-11-02）
///
/// - 应用启动后由首页首帧 [prefetch] **后台静默拉取一次**；
/// - 之后**不再因进出搜索态而重复拉取**（进程内长期有效）；
/// - 只有用户点热搜标题行的「刷新」才 [invalidate] 并重新请求。
///
/// ## 为何要它（根因）
///
/// 搜索面板每次进入都会重新拉热搜（`SearchContentPanel.initState`）。而
/// 「加载中（矮）」→「已加载（高）」的**面板内在高度跳变**若落在 220ms 的展开
/// 动画窗口内，会触发 `RenderAnimatedSize` 把尺寸动画**从 0 重跑**
/// （`_restartAnimation()` ⇒ `forward(from: 0)`）——即用户看到的"顿挫"。
///
/// 本服务把热搜结果**缓存在进程内并支持首帧静默预取**：用户点搜索框时数据多
/// 已就绪，从源头减少"动画途中换高度"的竞态（详见
/// `docs/搜索态扩充动效与合并栏阴影复盘-2026-10-21.md`）。
class SearchTrendingCache {
  SearchTrendingCache._();

  static final SearchTrendingCache instance = SearchTrendingCache._();

  /// 已成功拉取的列表（进程内长期有效；「刷新」会置空后重新拉取）。
  List<SearchTrendingItemModel>? _items;
  Future<List<SearchTrendingItemModel>>? _inflight;

  /// 已有数据 → 返回缓存；从未成功拉取 → null（调用方可先落骨架）。
  List<SearchTrendingItemModel>? peek() => _items;

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
  }

  /// 静默预取（首页首帧调用 = 首次启动后台拉取一次）：命中即跳过；失败不抛、
  /// 不影响调用方（无数据时下次进入搜索态会再尝试一次）。
  void prefetch({int limit = 20}) {
    if (Pref.demoMode) return;
    if (peek() != null) return;
    fetch(limit: limit).then<void>((_) {}, onError: (_) {});
  }
}