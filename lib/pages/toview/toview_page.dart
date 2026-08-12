import 'package:flutter/material.dart';

import 'package:winwin/common/widgets/video_card/video_card_h.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/toview.dart';
import 'package:winwin/models/toview/toview_models.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/app_empty_state.dart';

/// 稍后再看页面（移植自 PiliPlus `lib/pages/later/`）。
///
/// WinWin 精简版：列表展示 + 单条移除 + 清空。
void showToviewPage(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const ToviewPage()),
  );
}

class ToviewPage extends StatefulWidget {
  const ToviewPage({super.key});

  @override
  State<ToviewPage> createState() => _ToviewPageState();
}

class _ToviewPageState extends State<ToviewPage> {
  final List<LaterItem> _items = [];
  int _page = 1;
  int? _totalCount;
  bool _hasMore = true;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    if (refresh) {
      _page = 1;
      _hasMore = true;
      _items.clear();
    }
    if (!_hasMore) return;

    if (!Accounts.main.isLogin) {
      setState(() {
        _loading = false;
        _error = '请先登录';
      });
      return;
    }

    final res = await ToviewHttp.toviewList(page: _page);
    if (!mounted) return;

    switch (res) {
      case Success(:final response):
        setState(() {
          _loading = false;
          _error = null;
          _totalCount = response.count;
          if (response.list != null) _items.addAll(response.list!);
          _hasMore = _items.length < (_totalCount ?? 0) &&
              (response.list?.isNotEmpty ?? false);
          _page++;
        });
      case Error(:final errMsg):
        setState(() {
          _loading = false;
          _error = errMsg ?? '加载失败';
        });
      case Loading():
        break;
    }
  }

  Future<void> _removeItem(LaterItem item) async {
    if (item.aid == null) return;
    final res = await ToviewHttp.delToview('${item.aid}');
    if (!mounted) return;
    switch (res) {
      case Success():
        setState(() {
          _items.remove(item);
          if (_totalCount != null) _totalCount = _totalCount! - 1;
        });
      case Error(:final errMsg):
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(errMsg ?? '移除失败')),
        );
      case Loading():
        break;
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空稍后再看'),
        content: const Text('确定清空所有稍后再看？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final res = await ToviewHttp.clearToview();
    if (!mounted) return;
    switch (res) {
      case Success():
        setState(() {
          _items.clear();
          _hasMore = false;
          _totalCount = 0;
        });
      case Error(:final errMsg):
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(errMsg ?? '清空失败')),
        );
      case Loading():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('稍后再看'),
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: '清空',
              onPressed: _clearAll,
            ),
        ],
      ),
      body: _loading && _items.isEmpty
          ? const Center(child: CircularProgressIndicator(color: biliPink))
          : _error != null && _items.isEmpty
              ? _buildError()
              : _items.isEmpty
                  ? const AppEmptyState(
                      icon: Icons.watch_later_outlined,
                      title: '稍后再看列表为空',
                      subtitle: '把想看的视频加入稍后再看吧',
                    )
                  : RefreshIndicator(
                  color: biliPink,
                  onRefresh: () => _load(refresh: true),
                  child: ListView.builder(
                    itemCount: _items.length + 1,
                    itemBuilder: (context, index) {
                      if (index == _items.length) {
                        if (_hasMore) {
                          _load();
                          return const Padding(
                            padding: EdgeInsets.all(Style.md),
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2, color: biliPink),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      }
                      return _ToviewTile(
                        item: _items[index],
                        onRemove: () => _removeItem(_items[index]),
                      );
                    },
                  ),
                ),
    );
  }

  /// 错误/未登录态：未登录用语义空态，其余用统一错误态（含重试）。
  Widget _buildError() {
    if (_error == '请先登录') {
      return const AppEmptyState(
        icon: Icons.account_circle_outlined,
        title: '请先登录',
        subtitle: '登录后可查看稍后再看',
      );
    }
    return AppErrorState(
      message: _error ?? '加载失败',
      onRetry: () => _load(refresh: true),
    );
  }
}

class _ToviewTile extends StatelessWidget {
  const _ToviewTile({required this.item, required this.onRemove});

  final LaterItem item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(item.aid),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: Style.lg),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onRemove(),
      child: VideoCardH(videoItem: item),
    );
  }
}
