import 'package:material_ui/material_ui.dart';

import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/msg.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/core/shell/app_routes.dart';

/// 会话设置入口（阶段 D）。
///
/// 精简版：免打扰开关 + 删除会话 + 举报。推送开关/拉黑/清空消息待后续扩展。
void showSessionSettingsPage(
  BuildContext context, {
  required int talkerId,
  required int sessionType,
  required String title,
}) {
  Navigator.of(context).push(
    AppRoute<void>(
      builder: (_) => SessionSettingsPage(
        talkerId: talkerId,
        sessionType: sessionType,
        title: title,
      ),
    ),
  );
}

class SessionSettingsPage extends StatefulWidget {
  const SessionSettingsPage({
    super.key,
    required this.talkerId,
    required this.sessionType,
    required this.title,
  });

  final int talkerId;
  final int sessionType;
  final String title;

  @override
  State<SessionSettingsPage> createState() => _SessionSettingsPageState();
}

class _SessionSettingsPageState extends State<SessionSettingsPage> {
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

  Future<void> _toggleDnd(bool value) async {
    if (_busy) return;
    setState(() => _busy = true);
    final res = await MsgHttp.setMsgDnd(
      uid: Accounts.main.mid,
      setting: value ? 1 : 0,
      dndUid: widget.talkerId,
    );
    if (!mounted) return;
    if (res.isSuccess) {
      setState(() {
        _dnd = value;
        _busy = false;
      });
    } else {
      setState(() => _busy = false);
      _toast(res is Error ? (res.errMsg ?? '操作失败') : '操作失败');
    }
  }

  Future<void> _deleteSession() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除会话'),
        content: const Text('会话会从列表中移除，聊天记录仍由服务端保留。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    final res = await MsgHttp.removeMsg(widget.talkerId);
    if (!mounted) return;
    if (res.isSuccess) {
      // 退出聊天详情 + 设置页两层。
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      _toast(res is Error ? (res.errMsg ?? '删除失败') : '删除失败');
    }
  }

  Future<void> _report() async {
    final reasons = ['垃圾广告', '骚扰谩骂', '色情低俗', '违法信息', '其他'];
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('举报原因'),
        children: reasons
            .map((r) => SimpleDialogOption(
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
    final tokens = AppThemeHost.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('消息免打扰'),
            subtitle: Text(_dnd ? '已开启' : '关闭', style: tokens.text.bodySmall),
            value: _dnd,
            onChanged: _busy ? null : _toggleDnd,
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.report_outlined, color: tokens.colors.error),
            title: Text('举报', style: TextStyle(color: tokens.colors.error)),
            onTap: _report,
          ),
          ListTile(
            leading: Icon(AppIcons.delete(), color: tokens.colors.error),
            title: Text('删除会话', style: TextStyle(color: tokens.colors.error)),
            onTap: _deleteSession,
          ),
          Padding(
            padding: const EdgeInsets.all(Style.lg),
            child: Text(
              '推送开关 / 拉黑 / 清空消息等待后续扩展',
              style: tokens.text.bodySmall?.copyWith(color: tokens.colors.outline),
            ),
          ),
        ],
      ),
    );
  }
}
