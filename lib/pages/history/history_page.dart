import 'package:flutter/material.dart';

import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/http/history.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/models/history/history_models.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';

/// 历史记录页面（移植自 PiliPlus `lib/pages/history/`）。
///
/// WinWin 精简版：游标分页列表 + 单条删除 + 清空。
void showHistoryPage(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const HistoryPage()),
  );
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final List<HistoryItem> _items = [];
  int? _max;
  int? _viewAt;
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
      _max = null;
      _viewAt = null;
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

    final res = await HistoryHttp.historyList(
      max: _max,
      viewAt: _viewAt,
    );
    if (!mounted) return;

    switch (res) {
      case Success(:final response):
        setState(() {
          _loading = false;
          _error = null;
          if (response.list != null) _items.addAll(response.list!);
          // 游标分页：取末尾项的 oid 和 viewAt。
          if (response.list != null && response.list!.isNotEmpty) {
            final last = response.list!.last;
            _max = last.history.oid;
            _viewAt = last.viewAt;
            _hasMore = response.list!.length >= 20;
          } else {
            _hasMore = false;
          }
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

  Future<void> _deleteItem(HistoryItem item) async {
    final res = await HistoryHttp.delHistory(item.delKid);
    if (!mounted) return;
    switch (res) {
      case Success():
        setState(() => _items.remove(item));
      case Error(:final errMsg):
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(errMsg ?? '删除失败')),
        );
      case Loading():
        break;
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空历史'),
        content: const Text('确定清空所有观看历史？此操作不可撤销。'),
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

    final res = await HistoryHttp.clearHistory();
    if (!mounted) return;
    switch (res) {
      case Success():
        setState(() {
          _items.clear();
          _hasMore = false;
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
        title: const Text('历史记录'),
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
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!),
                      const SizedBox(height: Style.md),
                      FilledButton(
                        onPressed: () => _load(refresh: true),
                        style: FilledButton.styleFrom(backgroundColor: biliPink),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
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
                      return _HistoryTile(
                        item: _items[index],
                        onDelete: () => _deleteItem(_items[index]),
                      );
                    },
                  ),
                ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.item, required this.onDelete});

  final HistoryItem item;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('${item.history.oid}_${item.viewAt}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: Style.lg),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: ListTile(
        leading: item.cover != null && item.cover!.isNotEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.circular(Style.radiusSm),
                child: Image.network(
                  item.cover!,
                  width: 120,
                  height: 68,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 120,
                    height: 68,
                    color: Colors.grey[300],
                    child: const Icon(Icons.play_circle_outline),
                  ),
                ),
              )
            : null,
        title: Text(
          item.title ?? '',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${item.authorName ?? ''} · ${_formatTime(item.viewAt)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  String _formatTime(int? timestamp) {
    if (timestamp == null) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 30) return '${diff.inDays}天前';
    return '${dt.month}-${dt.day}';
  }
}
