import 'package:flutter_miuix/miuix.dart'
    show MiuixDropdownEntry, MiuixDropdownItem, MiuixTextButton;
import 'package:flutter/widgets.dart';

import 'package:winwin/common/widgets/app_dialog_shell.dart';
import 'package:winwin/common/widgets/miuix_popup_menu.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/core/shell/app_dialogs.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/msg.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/app_tooltip.dart';
import 'package:winwin/ui/components/hover_container.dart';

/// 聊天详情右上角「会话设置」（阶段 D 修订）。
///
/// 取代原 `SessionSettingsPage` 二级页面：设置项收敛到锚定触发按钮的
/// [MiuixPopupMenu] 弹层（与列表「更多选项」同款自绘壳 / 材质 / 动效 /
/// Esc 收起），免打扰开关 + 举报 + 删除会话一并呈现。
///
/// **触发控件用被动视觉**（[HoverContainer] + 图标）而非 `MiuixIconButton`：
/// 弹层壳以自身外层 `GestureDetector` 接管点击，若子级再放一个可点击按钮，
/// 内层手势会赢下手势竞技场导致弹层无法展开（见 `miuix_popup_menu.dart`
/// 触发契约）。图标色显式取主题色，修复深色主题下按钮不反色的问题。
class SessionSettingsMenuButton extends StatefulWidget {
  const SessionSettingsMenuButton({
    super.key,
    required this.talkerId,
    required this.sessionType,
  });

  final int talkerId;
  final int sessionType;

  @override
  State<SessionSettingsMenuButton> createState() =>
      _SessionSettingsMenuButtonState();
}

class _SessionSettingsMenuButtonState extends State<SessionSettingsMenuButton> {
  bool _dnd = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadDnd();
  }

  Future<void> _loadDnd() async {
    // 项目约定：触碰网络前等待 bootstrap（幂等），防 dio 未初始化。
    await ensureBootstrap();
    final res = await MsgHttp.getSessionSs(talkerUid: widget.talkerId);
    if (!mounted) return;
    if (res case Success(:final response)) {
      setState(() => _dnd = (response['setting'] as num?)?.toInt() == 1);
    }
  }

  Future<void> _toggleDnd() async {
    if (_busy) return;
    final next = !_dnd;
    setState(() => _busy = true);
    final res = await MsgHttp.setMsgDnd(
      uid: Accounts.main.mid,
      setting: next ? 1 : 0,
      dndUid: widget.talkerId,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (res.isSuccess) _dnd = next;
    });
    // 弹层在选项点击后即收起，故以 Toast 回执本次切换结果。
    if (res.isSuccess) {
      showToast(context, next ? '已开启免打扰' : '已关闭免打扰',
          duration: const Duration(seconds: 1));
    } else {
      _toast(res is Error ? (res.errMsg ?? '操作失败') : '操作失败');
    }
  }

  Future<void> _deleteSession() async {
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: const Text('删除会话'),
        content: const Text('会话会从列表中移除，聊天记录仍由服务端保留。'),
        actions: [
          MiuixTextButton('取消', onPressed: () => Navigator.pop(ctx, false)),
          MiuixTextButton('删除', onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (ok != true) return;
    final res = await MsgHttp.removeMsg(widget.talkerId);
    if (!mounted) return;
    if (res.isSuccess) {
      // 会话已从列表移除 → 退出当前聊天详情页（弹层所在页面）。
      Navigator.of(context).maybePop();
    } else {
      _toast(res is Error ? (res.errMsg ?? '删除失败') : '删除失败');
    }
  }

  Future<void> _report() async {
    final reasons = ['垃圾广告', '骚扰谩骂', '色情低俗', '违法信息', '其他'];
    final reason = await showAppDialog<String>(
      context: context,
      builder: (ctx) => AppSimpleDialog(
        title: const Text('举报原因'),
        children: reasons
            .map((r) => AppSimpleDialogOption(
                  child: Text(r),
                  onPressed: () => Navigator.pop(ctx, r),
                ))
            .toList(),
      ),
    );
    if (reason == null) return;
    final res = await MsgHttp.imMsgReport(
      accusedUid: widget.talkerId,
      reasonType: 1,
      reasonDesc: reason,
      comment: {'content': reason},
      extra: {'session_type': widget.sessionType},
    );
    if (!mounted) return;
    _toast(res.isSuccess ? '举报已提交' : (res is Error ? (res.errMsg ?? '举报失败') : '举报失败'));
  }

  void _toast(String msg) {
    showToast(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final cs = AppThemeHost.of(context).colors;
    return MiuixPopupMenu(
      title: '会话设置',
      entries: [
        MiuixDropdownEntry(
          items: [
            MiuixDropdownItem(
              text: _dnd ? '关闭免打扰' : '开启免打扰',
              icon: AppIcon(
                AppIcons.notificationsOff(active: _dnd),
                color: _dnd ? cs.primary : null,
              ),
              selected: _dnd,
              enabled: !_busy,
              onClick: _toggleDnd,
            ),
          ],
        ),
        MiuixDropdownEntry(
          items: [
            MiuixDropdownItem(
              text: '举报',
              icon: AppIcon(AppIcons.reportAbuse(), color: cs.error),
              onClick: _report,
            ),
            MiuixDropdownItem(
              text: '删除会话',
              icon: AppIcon(AppIcons.delete(), color: cs.error),
              onClick: _deleteSession,
            ),
          ],
        ),
      ],
      child: HoverContainer(
        borderRadius: Style.radiusSm,
        padding: const EdgeInsets.all(Style.sm),
        child: AppTooltip(
          message: '会话设置',
          child: AppIcon(AppIcons.more(), size: 20, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}