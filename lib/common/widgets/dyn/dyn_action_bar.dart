import 'package:flutter_miuix/miuix.dart' show MiuixPressFeedbackType, MiuixPressable;
import 'package:flutter/widgets.dart';

import 'package:winwin/common/widgets/dyn/dyn_repost_dialog.dart';
import 'package:winwin/core/account/login_guard.dart';
import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/http/dyn.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/utils/num_utils.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/ui/components/app_tooltip.dart';

/// 动态互动条（转发 / 评论 / 点赞），动态卡片、详情页与空间动态共用。
///
/// - 点赞：登录守卫 → `/x/dynamic/feed/dyn/thumb`，成功后图标高亮、计数 ±1；
/// - 评论：交由 [onComment] 回调处理（列表页跳详情并聚焦输入框 / 详情页聚焦输入框）；
/// - 转发：弹出 [DynRepostDialog] 输入转发理由，成功后转发数 +1。
class DynActionBar extends StatefulWidget {
  const DynActionBar({
    super.key,
    required this.item,
    this.liked,
    this.likeCount,
    this.onChanged,
    this.onComment,
    this.iconSize = 14,
    this.textSize = 12,
  });

  /// 所属动态（id 为点赞/转发目标）。
  final DynItemModel item;

  /// 外部点赞态覆盖（列表页跨滚动重建记忆），null 时采用接口数据。
  final bool? liked;

  /// 外部点赞数覆盖，null 时采用接口数据。
  final int? likeCount;

  /// 点赞成功后的回写（供列表页保存记忆）。
  final void Function(bool liked, int likeCount)? onChanged;

  /// 评论按钮点击回调（null 时不可点击）。
  final VoidCallback? onComment;

  /// 图标尺寸（卡片 14，详情页 16）。
  final double iconSize;

  /// 文字尺寸（卡片 12，详情页 13）。
  final double textSize;

  @override
  State<DynActionBar> createState() => _DynActionBarState();
}

class _DynActionBarState extends State<DynActionBar> {
  bool? _liked;
  int? _likeCount;
  int _repostBump = 0;
  bool _liking = false;

  DynStat? get _stat => widget.item.stat;

  bool get _effectiveLiked => _liked ?? widget.liked ?? (_stat?.liked ?? false);

  int get _effectiveLikeCount =>
      _likeCount ?? widget.likeCount ?? (_stat?.like ?? 0);

  Future<void> _onTapLike() async {
    if (_liking) return;
    if (!await LoginGuard.requireLogin(context)) return;
    if (!mounted) return;

    final liked = _effectiveLiked;
    setState(() => _liking = true);
    final res = await DynHttp.thumbDynamic(
      dynIdStr: widget.item.id,
      up: liked ? 2 : 1,
    );
    if (!mounted) return;
    setState(() => _liking = false);

    switch (res) {
      case Success():
        final newLiked = !liked;
        final newCount = newLiked
            ? _effectiveLikeCount + 1
            : (_effectiveLikeCount > 0 ? _effectiveLikeCount - 1 : 0);
        setState(() {
          _liked = newLiked;
          _likeCount = newCount;
        });
        widget.onChanged?.call(newLiked, newCount);
        _toast(newLiked ? '点赞成功' : '已取消点赞');
      case Error(:final errMsg):
        _toast(errMsg ?? '操作失败');
      case Loading():
        break;
    }
  }

  Future<void> _onTapRepost() async {
    final success = await DynRepostDialog.show(context, widget.item);
    if (!mounted || !success) return;
    setState(() => _repostBump++);
  }

  void _toast(String msg) {
    showToast(context, msg, duration: const Duration(seconds: 2));
  }

  @override
  Widget build(BuildContext context) {
    final cs = AppThemeHost.of(context).colors;
    final liked = _effectiveLiked;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildButton(
          icon: AppIcon(
            AppIcons.repost(),
            size: widget.iconSize,
            color: cs.outline,
          ),
          count: (_stat?.repost ?? 0) + _repostBump,
          color: cs.outline,
          tooltip: '转发',
          onTap: widget.item.id.isEmpty ? null : _onTapRepost,
        ),
        _buildButton(
          icon: AppIcon(
            AppIcons.comment(),
            size: widget.iconSize,
            color: cs.outline,
          ),
          count: _stat?.comment ?? 0,
          color: cs.outline,
          tooltip: '评论',
          onTap: widget.onComment,
        ),
        _buildButton(
          icon: AppIcon(
            AppIcons.like(active: liked),
            size: widget.iconSize,
            color: liked ? biliPink : cs.outline,
          ),
          count: _effectiveLikeCount,
          color: liked ? biliPink : cs.outline,
          tooltip: liked ? '取消点赞' : '点赞',
          onTap: widget.item.id.isEmpty ? null : _onTapLike,
        ),
      ],
    );
  }

  Widget _buildButton({
    required Widget icon,
    required int count,
    required Color color,
    required String tooltip,
    required VoidCallback? onTap,
  }) {
    return AppTooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
        child: MiuixPressable(
          feedbackType: MiuixPressFeedbackType.sink,
          sinkAmount: 0.98,
          onPressed: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(width: 4),
                Text(
                  count > 0 ? NumUtils.formatNum(count) : '0',
                  style: TextStyle(fontSize: widget.textSize, color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
