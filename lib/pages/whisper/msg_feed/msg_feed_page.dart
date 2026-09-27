import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/msg.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/app_empty_state.dart';
import 'package:winwin/utils/image_utils.dart';

/// 消息流加载器（游标分页）：回复我 / 艾特我 / 点赞我 共用此签名。
typedef MsgFeedLoader = Future<LoadingState<Map<String, dynamic>>> Function({
  int? cursor,
  int? cursorTime,
});

/// 从消息流 data 中提取列表项。
typedef MsgFeedItemsExtractor = List<Map<String, dynamic>> Function(
  Map<String, dynamic> data,
);

/// 从消息流 data 中提取游标（含 is_end / id / time）。
typedef MsgFeedCursorExtractor = Map<String, dynamic>? Function(
  Map<String, dynamic> data,
);

/// 消息流列表项构造器（[onDelete] 由框架提供，用于删除当前项）。
typedef MsgFeedTileBuilder = Widget Function(
  Map<String, dynamic> item,
  VoidCallback onDelete,
);

/// 消息流通用列表页（阶段 B）。
///
/// 复用 history_page 的游标分页模式（StatefulWidget + 手动 cursor），
/// 而非 CommonListController（后者为 page 自增分页，与 msg feed 的
/// cursor+cursorTime 不匹配）。回复/艾特/点赞三流共用本框架，
/// 仅 loader / extractors / tileBuilder 不同。
class MsgFeedPage extends StatefulWidget {
  const MsgFeedPage({
    super.key,
    required this.title,
    required this.loader,
    required this.extractItems,
    required this.extractCursor,
    required this.tileBuilder,
    required this.delType,
    this.actions,
  });

  final String title;
  final MsgFeedLoader loader;
  final MsgFeedItemsExtractor extractItems;
  final MsgFeedCursorExtractor extractCursor;
  final MsgFeedTileBuilder tileBuilder;

  /// delMsgfeed 的 tp 参数：0=like 1=reply 2=at。
  final int delType;
  final List<Widget>? actions;

  @override
  State<MsgFeedPage> createState() => _MsgFeedPageState();
}

class _MsgFeedPageState extends State<MsgFeedPage> {
  final List<Map<String, dynamic>> _items = [];
  int? _cursor;
  int? _cursorTime;
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
      _cursorTime = null;
      _hasMore = true;
      _items.clear();
      setState(() => _loading = true);
    }
    if (!_hasMore) return;
    final res = await widget.loader(cursor: _cursor, cursorTime: _cursorTime);
    if (!mounted) return;
    switch (res) {
      case Success(:final response):
        final items = widget.extractItems(response);
        final cur = widget.extractCursor(response);
        setState(() {
          _loading = false;
          _error = null;
          _items.addAll(items);
          _cursor = cur?['id'] as int?;
          _cursorTime = cur?['time'] as int?;
          _hasMore = cur?['is_end'] != true && items.isNotEmpty;
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

  Future<void> _delete(Map<String, dynamic> item, int index) async {
    final res = await MsgHttp.delMsgfeed(widget.delType, item['id']);
    if (!mounted) return;
    switch (res) {
      case Success():
        setState(() => _items.removeAt(index));
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('已删除'), duration: Duration(seconds: 1)),
        );
      case Error(:final errMsg):
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(errMsg ?? '删除失败')),
        );
      case Loading():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: widget.actions,
      ),
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
                      final item = _items[index];
                      return widget.tileBuilder(
                        item,
                        () => _delete(item, index),
                      );
                    },
                  ),
                ),
    );
  }
}

/// 错误重试视图。
class MsgFeedErrorView extends StatelessWidget {
  const MsgFeedErrorView({super.key, required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(error),
          const SizedBox(height: Style.md),
          FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(backgroundColor: biliPink),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }
}

/// 空态视图（统一接入 [AppEmptyState]，通知语义图标）。
class MsgFeedEmptyView extends StatelessWidget {
  const MsgFeedEmptyView({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppEmptyState(
      icon: Icons.notifications_none_rounded,
      title: '暂无消息',
      subtitle: '新的消息会出现在这里',
    );
  }
}

/// 圆形网络头像（消息流列表通用）。
class MsgFeedAvatar extends StatelessWidget {
  const MsgFeedAvatar({super.key, required this.src, this.size = 45});

  final String? src;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 解码尺寸限制（对齐 NetworkImgLayer 策略）：头像原图可能高达 1000+px，
    // 不限制解码尺寸会让每张头像按原图解码（CPU 位图 + GPU 纹理双份占用）。
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final decodeTarget = (size * dpr).round().clamp(64, 256);
    return ClipOval(
      child: src != null && src!.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: ImageUtils.thumbnailUrl(src, type: 'avatar'),
              width: size,
              height: size,
              fit: BoxFit.cover,
              memCacheWidth: decodeTarget,
              memCacheHeight: decodeTarget,
              placeholder: (_, _) => _fallback(cs),
              errorBuilder: (_, _, _) => _fallback(cs),
            )
          : _fallback(cs),
    );
  }

  Widget _fallback(ColorScheme cs) => Container(
        width: size,
        height: size,
        color: cs.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(Icons.person, color: cs.outline, size: size * 0.5),
      );
}

/// 相对时间格式化（秒级时间戳）。
String msgFeedTime(int? timestamp) {
  if (timestamp == null || timestamp <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
  if (diff.inDays < 1) return '${diff.inHours}小时前';
  if (diff.inDays < 2) return '昨天';
  if (diff.inDays < 30) return '${diff.inDays}天前';
  return '${dt.month}-${dt.day}';
}
