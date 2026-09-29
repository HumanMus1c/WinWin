import 'package:material_ui/material_ui.dart';

import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/msg.dart';
import 'package:winwin/pages/whisper/msg_feed/msg_feed_page.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';

/// 「系统消息」入口。
void showSysMsgPage(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const SysMsgPage()),
  );
}

class SysMsgPage extends StatefulWidget {
  const SysMsgPage({super.key});

  @override
  State<SysMsgPage> createState() => _SysMsgPageState();
}

class _SysMsgPageState extends State<SysMsgPage> {
  final List<Map<String, dynamic>> _items = [];
  int? _cursor;
  bool _hasMore = true;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    // 项目约定：触碰网络前等待 bootstrap（幂等），防 dio 未初始化。
    await ensureBootstrap();
    if (refresh) {
      _cursor = null;
      _hasMore = true;
      _items.clear();
      setState(() => _loading = true);
    }
    if (!_hasMore) return;
    final res = await MsgHttp.msgFeedNotify(cursor: _cursor);
    if (!mounted) return;
    switch (res) {
      case Success(:final response):
        final items = response ?? const <Map<String, dynamic>>[];
        setState(() {
          _loading = false;
          _error = null;
          _items.addAll(items);
          _hasMore = items.length >= 20;
          _cursor = items.isNotEmpty
              ? (items.last['cursor'] as num?)?.toInt()
              : _cursor;
        });
        // 首屏标记已读（取最早一条的 cursor）。
        if (refresh && items.isNotEmpty) {
          final firstCursor = (items.first['cursor'] as num?)?.toInt();
          if (firstCursor != null) {
            MsgHttp.msgSysUpdateCursor(firstCursor);
          }
        }
      case Error(:final errMsg):
        setState(() {
          _loading = false;
          _error = errMsg ?? '加载失败';
        });
      case Loading():
        break;
    }
  }

  Future<void> _delete(int index) async {
    final item = _items[index];
    final res = await MsgHttp.delSysMsg(item['id']);
    if (!mounted) return;
    switch (res) {
      case Success():
        setState(() => _items.removeAt(index));
        showToast(context, '已删除', duration: const Duration(seconds: 1));
      case Error(:final errMsg):
        showToast(context, errMsg ?? '删除失败');
      case Loading():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('系统消息')),
      body: _loading && _items.isEmpty
          ? const Center(child: CircularProgressIndicator(color: biliPink))
          : _error != null && _items.isEmpty
              ? MsgFeedErrorView(error: _error!, onRetry: () => _load(refresh: true))
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
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: biliPink,
                              ),
                            ),
                          );
                        }
                        return _items.isEmpty
                            ? const MsgFeedEmptyView()
                            : const SizedBox.shrink();
                      }
                      return _SysMsgTile(
                        item: _items[index],
                        onDelete: () => _delete(index),
                      );
                    },
                  ),
                ),
    );
  }
}

class _SysMsgTile extends StatelessWidget {
  const _SysMsgTile({required this.item, required this.onDelete});

  final Map<String, dynamic> item;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = item['title']?.toString() ?? '';
    final content = item['content']?.toString() ?? '';
    final timeAt = item['time_at']?.toString() ?? '';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Style.safeSpace,
        vertical: Style.xs,
      ),
      title: title.isEmpty
          ? null
          : Text(
              title,
              style: theme.textTheme.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (content.isNotEmpty)
            Text(content, style: theme.textTheme.bodyMedium),
          if (timeAt.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                timeAt,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
        ],
      ),
      onLongPress: () => _confirmDelete(context),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除该通知？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) onDelete();
  }
}
