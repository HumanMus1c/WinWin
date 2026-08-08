import 'package:flutter/material.dart';

import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/common/widgets/refresh_indicator.dart';
import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/pgc.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/utils/num_utils.dart';

/// 番剧页（Phase 7.7.4）。
///
/// 参照 PiliPlus 的 `PgcPage`：番剧索引 + 时间线。
/// 桌面端精简：实现番剧索引网格（新番时间排序），时间线作为 secondary tab。
class PgcPage extends StatefulWidget {
  const PgcPage({super.key});

  @override
  State<PgcPage> createState() => _PgcPageState();
}

class _PgcPageState extends State<PgcPage>
    with AutomaticKeepAliveClientMixin {
  LoadingState<List<Map<String, dynamic>>?> _state = LoadingState.loading();
  final List<Map<String, dynamic>> _items = [];
  int _page = 1;
  bool _hasMore = true;
  bool _loading = false;
  late final ScrollController _scrollController;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _load(refresh: true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load({required bool refresh}) async {
    if (_loading) return;
    if (!refresh && !_hasMore) return;
    _loading = true;
    if (refresh) {
      _page = 1;
      _items.clear();
      _hasMore = true;
      setState(() => _state = LoadingState.loading());
    }
    await ensureBootstrap();
    final res = await PgcHttp.pgcIndex(page: _page);
    if (!mounted) return;
    switch (res) {
      case Success(:final response):
        if (response == null || response.isEmpty) {
          _hasMore = false;
        } else {
          _items.addAll(response);
          _hasMore = response.length >= 20;
          _page++;
        }
        setState(() => _state = Success(response));
      case Error():
        setState(() => _state = res);
      case Loading():
        break;
    }
    _loading = false;
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      _load(refresh: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // 嵌入 HomePage 时需顶部留白以避开浮动顶栏 + 分类标签行。
    return Padding(
      padding: const EdgeInsets.only(top: 120),
      child: AppRefreshIndicator(
        onRefresh: () => _load(refresh: true),
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n is ScrollEndNotification) _onScroll();
            return false;
          },
          child: switch (_state) {
            Loading() => const Center(child: CircularProgressIndicator()),
            Error(:final errMsg) => _buildError(errMsg),
            Success() => _items.isEmpty
                ? _buildEmpty()
                : CustomScrollView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(
                          Style.safeSpace,
                          Style.sm,
                          Style.safeSpace,
                          Style.xxl * 2,
                        ),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 180,
                            childAspectRatio: 0.62,
                            mainAxisSpacing: Style.cardSpace,
                            crossAxisSpacing: Style.cardSpace,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, i) {
                              if (i == _items.length) return _buildTrailer();
                              return _PgcCard(item: _items[i]);
                            },
                            childCount: _items.length + 1,
                          ),
                        ),
                      ),
                    ],
                  ),
          },
        ),
      ),
    );
  }

  Widget _buildError(String? msg) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(msg ?? '加载失败'),
            const SizedBox(height: Style.md),
            FilledButton.tonal(
              onPressed: () => _load(refresh: true),
              child: const Text('重试'),
            ),
          ],
        ),
      );

  Widget _buildEmpty() => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: Text('暂无番剧')),
        ],
      );

  Widget _buildTrailer() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: Style.lg),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (!_hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: Style.lg),
        child: Center(child: Text('没有更多了')),
      );
    }
    return const SizedBox.shrink();
  }
}

/// 番剧卡片：封面 + 标题 + 角标（播放/分数）。
class _PgcCard extends StatelessWidget {
  const _PgcCard({required this.item});

  final Map<String, dynamic> item;

  String? get _cover => item['cover']?.toString();
  String get _title => item['title']?.toString() ?? '';
  String? get _subtitle => item['subtitle']?.toString();
  int? get _play => (item['stat']?['view'] as num?)?.toInt() ??
      (item['order']?['play'] as num?)?.toInt();
  double? get _score {
    final raw = item['order']?['score'];
    if (raw is num) return raw.toDouble();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text('番剧详情页待后续集成'),
              duration: const Duration(seconds: 1),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NetworkImgLayer(
                    src: _cover,
                    width: double.infinity,
                    height: double.infinity,
                    borderRadius: BorderRadius.zero,
                  ),
                  if (_score != null)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _score!.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  if (_play != null)
                    Positioned(
                      left: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.play_circle_outlined,
                              size: 10,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              NumUtils.formatNum(_play),
                              style: const TextStyle(
                                fontSize: 9,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(Style.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (_subtitle != null && _subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        _subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.outline,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
