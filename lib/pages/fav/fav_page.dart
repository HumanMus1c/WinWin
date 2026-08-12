import 'package:flutter/material.dart';

import 'package:winwin/common/widgets/video_card/video_card_h.dart';
import 'package:winwin/core/account/account_service.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/http/fav.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/models/fav/fav_models.dart';
import 'package:winwin/pages/video/detail_page.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/app_empty_state.dart';

/// 收藏夹页面（移植自 PiliPlus `lib/pages/fav/`）。
///
/// WinWin 精简版：收藏夹列表 + 点击进入视频列表详情。
void showFavPage(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const FavPage()),
  );
}

class FavPage extends StatefulWidget {
  const FavPage({super.key});

  @override
  State<FavPage> createState() => _FavPageState();
}

class _FavPageState extends State<FavPage> {
  final List<FavFolderInfo> _folders = [];
  int _page = 1;
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
      _folders.clear();
    }
    if (!_hasMore) return;

    if (!Accounts.main.isLogin) {
      setState(() {
        _loading = false;
        _error = '请先登录';
      });
      return;
    }

    final res = await FavHttp.userFavFolder(
      pn: _page,
      mid: Accounts.main.mid,
    );
    if (!mounted) return;

    switch (res) {
      case Success(:final response):
        setState(() {
          _loading = false;
          _error = null;
          if (response.list != null) _folders.addAll(response.list!);
          _hasMore = response.hasMore == true;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的收藏')),
      body: _loading && _folders.isEmpty
          ? const Center(child: CircularProgressIndicator(color: biliPink))
          : _error != null && _folders.isEmpty
              ? _buildError()
              : _folders.isEmpty
                  ? const AppEmptyState(
                      icon: Icons.folder_off_outlined,
                      title: '暂无收藏夹',
                      subtitle: '去创建或收藏喜欢的视频吧',
                    )
                  : RefreshIndicator(
                  color: biliPink,
                  onRefresh: () => _load(refresh: true),
                  child: ListView.builder(
                    itemCount: _folders.length + 1,
                    itemBuilder: (context, index) {
                      if (index == _folders.length) {
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
                      final folder = _folders[index];
                      return _FavFolderTile(
                        folder: folder,
                        onTap: () => _openDetail(folder),
                      );
                    },
                  ),
                ),
    );
  }

  void _openDetail(FavFolderInfo folder) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FavDetailPage(folder: folder),
      ),
    );
  }

  /// 错误/未登录态：未登录用语义空态，其余用统一错误态（含重试）。
  Widget _buildError() {
    if (_error == '请先登录') {
      return const AppEmptyState(
        icon: Icons.account_circle_outlined,
        title: '请先登录',
        subtitle: '登录后可查看我的收藏',
      );
    }
    return AppErrorState(
      message: _error ?? '加载失败',
      onRetry: () => _load(refresh: true),
    );
  }
}

class _FavFolderTile extends StatelessWidget {
  const _FavFolderTile({required this.folder, required this.onTap});

  final FavFolderInfo folder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(
        folder.isPublic ? Icons.folder_outlined : Icons.lock_outline,
        color: biliPink,
      ),
      title: Text(folder.title),
      subtitle: Text('${folder.mediaCount} 个内容 · ${folder.isPublic ? "公开" : "私密"}'),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

// ── 收藏夹详情（视频列表） ──

class FavDetailPage extends StatefulWidget {
  const FavDetailPage({super.key, required this.folder});

  final FavFolderInfo folder;

  @override
  State<FavDetailPage> createState() => _FavDetailPageState();
}

class _FavDetailPageState extends State<FavDetailPage> {
  final List<FavDetailItem> _items = [];
  int _page = 1;
  bool _hasMore = true;
  bool _loading = true;

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

    final res = await FavHttp.favDetail(
      mediaId: widget.folder.id,
      pn: _page,
    );
    if (!mounted) return;

    switch (res) {
      case Success(:final response):
        setState(() {
          _loading = false;
          if (response.medias != null) _items.addAll(response.medias!);
          _hasMore = response.hasMore == true;
          _page++;
        });
      case Error():
        setState(() => _loading = false);
      case Loading():
        break;
    }
  }

  /// 打开收藏夹视频项：跳转视频详情页；
  /// 已失效资源（无 bvid）提示不可打开。
  void _openItem(FavDetailItem item) {
    final bvid = item.bvid;
    if (bvid == null || bvid.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('该资源已失效，无法打开')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VideoDetailPage(bvid: bvid, cover: item.cover),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.folder.title)),
      body: _loading && _items.isEmpty
          ? const Center(child: CircularProgressIndicator(color: biliPink))
          : _items.isEmpty
              ? const AppEmptyState(
                  icon: Icons.folder_off_outlined,
                  title: '该收藏夹暂无视频',
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
                  final item = _items[index];
                  return _FavVideoTile(
                    item: item,
                    onTap: () => _openItem(item),
                  );
                },
              ),
            ),
    );
  }
}

class _FavVideoTile extends StatelessWidget {
  const _FavVideoTile({required this.item, this.onTap});

  final FavDetailItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return VideoCardH(videoItem: item, onTap: onTap);
  }
}

// ── 收藏面板（从视频详情页弹出，选择收藏夹） ──

/// 弹出收藏面板。
///
/// [rid] 为视频 aid，[type] 为资源类型（UGC 视频=2）。
/// 成功后回调 [onSuccess]（true=已收藏，false=取消收藏）。
void showFavPanel(
  BuildContext context, {
  required int rid,
  int type = 2,
  ValueChanged<bool>? onSuccess,
}) {
  if (!Accounts.main.isLogin) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('请先登录')),
    );
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _FavPanel(rid: rid, type: type, onSuccess: onSuccess),
  );
}

class _FavPanel extends StatefulWidget {
  const _FavPanel({required this.rid, required this.type, this.onSuccess});

  final int rid;
  final int type;
  final ValueChanged<bool>? onSuccess;

  @override
  State<_FavPanel> createState() => _FavPanelState();
}

class _FavPanelState extends State<_FavPanel> {
  List<FavFolderInfo>? _folders;
  Set<int>? _initialFavIds;
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await FavHttp.videoInFolder(
      mid: Accounts.main.mid,
      rid: widget.rid,
      type: widget.type,
    );
    if (!mounted) return;
    switch (res) {
      case Success(:final response):
        setState(() {
          _folders = response.list ?? [];
          _initialFavIds = _folders
              ?.where((f) => f.favState == 1)
              .map((f) => f.id)
              .toSet();
          _loading = false;
        });
      case Error():
        setState(() => _loading = false);
      case Loading():
        break;
    }
  }

  Future<void> _submit() async {
    if (_folders == null || _initialFavIds == null) return;
    setState(() => _sending = true);

    final addIds = <int>[];
    final delIds = <int>[];
    for (final f in _folders!) {
      final wasFav = _initialFavIds!.contains(f.id);
      final nowFav = f.favState == 1;
      if (nowFav && !wasFav) addIds.add(f.id);
      if (!nowFav && wasFav) delIds.add(f.id);
    }

    final res = await FavHttp.favVideo(
      resources: '${widget.rid}:${widget.type}',
      addIds: addIds.join(','),
      delIds: delIds.join(','),
    );
    if (!mounted) return;

    setState(() => _sending = false);
    switch (res) {
      case Success():
        final isFav = addIds.isNotEmpty ||
            (_initialFavIds!.isNotEmpty && delIds.length != _initialFavIds!.length);
        widget.onSuccess?.call(isFav);
        Navigator.of(context).pop();
      case Error(:final errMsg):
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(errMsg ?? '操作失败')),
        );
      case Loading():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 500),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppBar(
            title: const Text('添加到收藏夹'),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator(color: biliPink)))
          else if (_folders == null || _folders!.isEmpty)
            const Expanded(child: Center(child: Text('暂无收藏夹')))
          else
            Expanded(
              child: ListView.builder(
                itemCount: _folders!.length,
                itemBuilder: (context, index) {
                  final f = _folders![index];
                  return CheckboxListTile(
                    value: f.favState == 1,
                    onChanged: _sending
                        ? null
                        : (v) => setState(() {
                              f.favState = v == true ? 1 : 0;
                            }),
                    title: Text(f.title),
                    subtitle: Text('${f.mediaCount} 个内容'),
                    secondary: Icon(
                      f.isPublic ? Icons.folder_outlined : Icons.lock_outline,
                      color: biliPink,
                    ),
                  );
                },
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(Style.md),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _sending ? null : () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: Style.md),
                Expanded(
                  child: FilledButton(
                    onPressed: _sending ? null : _submit,
                    style: FilledButton.styleFrom(backgroundColor: biliPink),
                    child: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('完成'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
