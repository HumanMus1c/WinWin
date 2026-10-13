import 'package:flutter_miuix/miuix.dart' show MiuixBasicComponent, MiuixIconButton, MiuixTextButton;
import 'package:material_ui/material_ui.dart';

import 'package:winwin/theme/app_colors.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/http/danmaku_block.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/models/danmaku/danmaku_rule.dart';
import 'package:winwin/pages/danmaku/controller.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/utils/crc32.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/core/shell/app_dialogs.dart';
import 'package:winwin/ui/components/app_progress.dart';
import 'package:winwin/ui/components/app_tooltip.dart';

/// 弹幕屏蔽规则管理页（移植自 PiliPlus `lib/pages/danmaku_block/view.dart`）。
///
/// 三栏 Tab：关键词(type=0) / 正则(type=1) / 用户(type=2)。
///
/// - 启动时拉取云端规则（[DanmakuFilterHttp.danmakuFilter]）。
/// - 添加：调用 [DanmakuFilterHttp.danmakuFilterAdd]，成功后入本地列表。
/// - 删除：调用 [DanmakuFilterHttp.danmakuFilterDel]，成功后移除。
/// - 任意改动后重建 [RuleFilter] 写回 [Pref.danmakuFilterRule]，并通知
///   [WinWinDanmakuController.setFilters] 即时生效。
///
/// 用户类型（type=2）本地统一存 midHash（CRC32 hex），与服务端返回格式
/// 及 [RuleFilter] 匹配逻辑对齐。
void showDanmakuBlockPage(
  BuildContext context, {
  WinWinDanmakuController? danmakuController,
}) {
  showAppDialog<void>(
    context: context,
    builder: (context) => _DanmakuBlockDialog(
      danmakuController: danmakuController,
    ),
  );
}

class _DanmakuBlockDialog extends StatefulWidget {
  const _DanmakuBlockDialog({this.danmakuController});

  final WinWinDanmakuController? danmakuController;

  @override
  State<_DanmakuBlockDialog> createState() => _DanmakuBlockDialogState();
}

class _DanmakuBlockDialogState extends State<_DanmakuBlockDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final List<TextEditingController> _controllers = [
    for (var i = 0; i < 3; i++) TextEditingController(),
  ];

  /// 三栏规则：[0]=关键词 [1]=正则 [2]=用户(存 midHash)。
  final List<List<SimpleRule>> _rules = [[], [], []];

  bool _loading = true;
  String? _errorMsg;

  static const _tabs = [DmBlockType.keyword, DmBlockType.regex, DmBlockType.uid];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchRules();
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchRules() async {
    if (!Accounts.main.isLogin) {
      setState(() {
        _loading = false;
        _errorMsg = '请先登录';
      });
      return;
    }
    final res = await DanmakuFilterHttp.danmakuFilter();
    if (!mounted) return;
    switch (res) {
      case Success(:final response):
        _rules[0] = List.of(response.rule);
        _rules[1] = List.of(response.rule1);
        _rules[2] = List.of(response.rule2);
        _sync();
        setState(() {
          _loading = false;
          _errorMsg = null;
        });
      case Error(:final errMsg):
        setState(() {
          _loading = false;
          _errorMsg = errMsg ?? '拉取失败';
        });
      case Loading():
        break;
    }
  }

  /// 重建 RuleFilter 并同步到控制器与持久化。
  void _sync() {
    final filter = RuleFilter.fromRules(_rules);
    widget.danmakuController?.setFilters(filter);
    Pref.danmakuFilterRule = filter.toJson();
  }

  Future<void> _addRule(int type) async {
    final input = _controllers[type].text.trim();
    if (input.isEmpty) return;
    _controllers[type].clear();

    final res = await DanmakuFilterHttp.danmakuFilterAdd(
      filter: input,
      type: type,
    );
    if (!mounted) return;
    switch (res) {
      case Success(:final response):
        // 用户类型本地存 midHash（与服务端返回格式、RuleFilter 匹配逻辑对齐）。
        final localFilter = type == DmBlockType.uid.serverType
            ? Crc32.midHash(int.parse(input))
            : input;
        setState(() {
          _rules[type].add(SimpleRule(
            id: response.id,
            type: type,
            filter: localFilter,
          ));
        });
        _sync();
      case Error(:final errMsg):
        _toast(errMsg ?? '添加失败');
      case Loading():
        break;
    }
  }

  Future<void> _delRule(int type, SimpleRule rule) async {
    final res = await DanmakuFilterHttp.danmakuFilterDel(ids: rule.id);
    if (!mounted) return;
    switch (res) {
      case Success():
        setState(() {
          _rules[type].removeWhere((r) => r.id == rule.id);
        });
        _sync();
      case Error(:final errMsg):
        _toast(errMsg ?? '删除失败');
        // 删除失败时恢复列表项（Dismissible 已移除 UI）。
        setState(() => _rules[type].add(rule));
      case Loading():
        break;
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    showToast(context, msg, duration: const Duration(seconds: 2));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: Style.lg,
        vertical: Style.xl,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(Style.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text('弹幕屏蔽规则', style: tokens.text.titleMedium),
                  const Spacer(),
                  MiuixIconButton(

                    onPressed: () {
                      setState(() => _loading = true);
                      _fetchRules();
                    },

                    child: AppTooltip(message: '刷新', child: AppIcon(AppIcons.refresh(), size: 20)),
                  ),
                  MiuixIconButton(

                    onPressed: () => Navigator.of(context).pop(),

                    child: AppIcon(AppIcons.clear()),
                  ),
                ],
              ),
              TabBar(
                controller: _tabController,
                labelColor: biliPink,
                unselectedLabelColor: tokens.colors.onSurfaceVariant,
                indicatorColor: biliPink,
                tabs: [for (final t in _tabs) Tab(text: t.label)],
              ),
              const SizedBox(height: Style.sm),
              Expanded(
                child: _loading
                    ? const Center(child: AppProgressIndicator(color: biliPink))
                    : _errorMsg != null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_errorMsg!,
                                    style: tokens.text.bodyMedium),
                                const SizedBox(height: Style.sm),
                                if (Accounts.main.isLogin)
                                  MiuixTextButton('重试', onPressed: () {
                                      setState(() => _loading = true);
                                      _fetchRules();
                                    }),
                              ],
                            ),
                          )
                        : TabBarView(
                            controller: _tabController,
                            children: [
                              for (var i = 0; i < 3; i++)
                                _RuleListSection(
                                  type: i,
                                  rules: _rules[i],
                                  controller: _controllers[i],
                                  onAdd: _addRule,
                                  onDelete: _delRule,
                                ),
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 单栏：输入行 + 规则列表（可滑动删除）。
class _RuleListSection extends StatelessWidget {
  const _RuleListSection({
    required this.type,
    required this.rules,
    required this.controller,
    required this.onAdd,
    required this.onDelete,
  });

  final int type;
  final List<SimpleRule> rules;
  final TextEditingController controller;
  final ValueChanged<int> onAdd;
  final void Function(int type, SimpleRule rule) onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final hint = switch (type) {
      0 => '输入关键词',
      1 => '输入正则（如 \\d+）',
      _ => '输入用户 UID',
    };
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Style.xs),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: hint,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: Style.md,
                      vertical: Style.sm,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Style.radiusSm),
                    ),
                  ),
                  onSubmitted: (_) => onAdd(type),
                ),
              ),
              const SizedBox(width: Style.sm),
              MiuixIconButton(
                backgroundColor: biliPink,
                child: AppIcon(AppIcons.add(), color: AppColors.white),
                onPressed: () => onAdd(type),
              ),
            ],
          ),
        ),
        const SizedBox(height: Style.sm),
        Expanded(
          child: rules.isEmpty
              ? Center(
                  child: Text(
                    '暂无${DmBlockType.values[type].label}规则',
                    style: TextStyle(color: tokens.colors.outline),
                  ),
                )
              : ListView.builder(
                  itemCount: rules.length,
                  itemBuilder: (context, index) {
                    final r = rules[index];
                    return Dismissible(
                      key: ValueKey('${type}_${r.id}_$index'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: Style.lg),
                        color: AppColors.red,
                        child: AppIcon(AppIcons.delete(), color: AppColors.white),
                      ),
                      confirmDismiss: (_) async {
                        onDelete(type, r);
                        return true;
                      },
                      child: MiuixBasicComponent(
                        content: [
                          Text(r.filter),
                          if (type == DmBlockType.uid.serverType)
                            Text('midHash', style: TextStyle(
                              fontSize: 11,
                              color: tokens.colors.outline,
                            )),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
