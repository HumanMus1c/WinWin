import 'package:flutter_miuix/miuix.dart' show MiuixBasicComponent;
import 'package:material_ui/material_ui.dart';

import 'package:winwin/common/widgets/demo_mask.dart';
import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/msg.dart';
import 'package:winwin/pages/member/member_space_page.dart';
import 'package:winwin/pages/whisper/msg_feed/msg_feed_page.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/core/shell/app_routes.dart';
import 'package:winwin/core/shell/app_scaffold.dart';
import 'package:winwin/ui/components/app_progress.dart';

/// 「点赞详情」入口——展开单条点赞卡片的用户列表。
void showLikeDetailPage(
  BuildContext context, {
  required String cardId,
  required int counts,
}) {
  Navigator.of(context).push(
    AppRoute<void>(
      builder: (_) => LikeDetailPage(cardId: cardId, counts: counts),
    ),
  );
}

class LikeDetailPage extends StatefulWidget {
  const LikeDetailPage({super.key, required this.cardId, required this.counts});

  final String cardId;
  final int counts;

  @override
  State<LikeDetailPage> createState() => _LikeDetailPageState();
}

class _LikeDetailPageState extends State<LikeDetailPage> {
  final List<Map<String, dynamic>> _items = [];
  int _pn = 1;
  int _lastMid = 0;
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
      _pn = 1;
      _lastMid = 0;
      _hasMore = true;
      _items.clear();
      setState(() => _loading = true);
    }
    if (!_hasMore) return;
    final res = await MsgHttp.msgLikeDetail(
      cardId: widget.cardId,
      pn: _pn,
      lastMid: _lastMid,
    );
    if (!mounted) return;
    switch (res) {
      case Success(:final response):
        final items = (response['items'] as List?)
                ?.map((e) => (e as Map).cast<String, dynamic>())
                .toList() ??
            const [];
        setState(() {
          _loading = false;
          _error = null;
          _items.addAll(items);
          if (items.isNotEmpty) {
            final last = items.last;
            _lastMid = (last['user'] as Map?)?['mid'] as int? ?? _lastMid;
          }
          _pn++;
          _hasMore = items.isNotEmpty && _items.length < widget.counts;
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
    return AppScaffold(
      body: Pref.demoMode
          ? const DemoListSkeleton(coverWidth: 40, coverHeight: 40)
          : _loading && _items.isEmpty
          ? const Center(child: AppProgressIndicator(color: biliPink))
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
                              child: AppProgressIndicator(
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
                      return _LikeUserTile(item: _items[index]);
                    },
                  ),
                ),
    );
  }
}

class _LikeUserTile extends StatelessWidget {
  const _LikeUserTile({required this.item});

  final Map<String, dynamic> item;

  Map? get _user => item['user'] as Map?;
  int? get _mid => _user?['mid'] as int?;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    return MiuixBasicComponent(
      insideMargin: const EdgeInsets.symmetric(
        horizontal: Style.safeSpace,
        vertical: Style.xs,
      ),
      startAction: MsgFeedAvatar(src: _user?['avatar']?.toString(), size: 40),
      content: [
        Text(
          _user?['nickname']?.toString() ?? '',
          style: tokens.text.bodyLarge,
        ),
        Text(
          msgFeedTime(item['like_time'] as int?),
          style: tokens.text.bodySmall
              ?.copyWith(color: tokens.colors.outline),
        ),
      ],
      onClick: () {
        final mid = _mid;
        if (mid == null) return;
        Navigator.of(context).push(
          AppRoute(builder: (_) => MemberSpacePage(mid: mid)),
        );
      },
    );
  }
}
