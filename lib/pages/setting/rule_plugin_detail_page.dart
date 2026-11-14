import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart'
    show MiuixButtonDefaults, MiuixTextButton;

import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/common/widgets/app_dialog_shell.dart';
import 'package:winwin/core/shell/app_dialogs.dart';
import 'package:winwin/core/shell/app_scaffold.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/plugin/rules/json_rule_plugin.dart';
import 'package:winwin/plugin/rules/rule_plugin_manager.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/app_components.dart';

/// 规则插件详情：规则摘要、命中统计、来源路径与删除入口。
class RulePluginDetailPage extends StatelessWidget {
  const RulePluginDetailPage({super.key, required this.pluginId});

  final String pluginId;

  RulePluginManager? get _manager => RulePluginManager.maybeInstance;

  @override
  Widget build(BuildContext context) {
    final manager = _manager;
    if (manager == null) {
      return const AppScaffold(
        reserveTopStrip: true,
        body: Center(child: Text('规则插件系统尚未初始化')),
      );
    }
    return AppScaffold(
      reserveTopStrip: true,
      body: ListenableBuilder(
        listenable: Listenable.merge([manager.plugins, manager.stats]),
        builder: (context, _) {
          LoadedRulePlugin? loaded;
          for (final item in manager.plugins.value) {
            if (item.plugin.id == pluginId) {
              loaded = item;
              break;
            }
          }
          if (loaded == null) {
            return const Center(child: Text('插件已删除'));
          }
          final plugin = loaded.plugin;
          final tokens = AppThemeHost.of(context);
          final padding = MediaQuery.viewPaddingOf(context);
          return ListView(
            padding: EdgeInsets.only(
              left: Style.md,
              right: Style.md,
              top: Style.md,
              bottom: padding.bottom + 100,
            ),
            children: [
              AppGroup(
                children: [
                  AppListItem(
                    icon: AppIcon(AppIcons.rulePlugin()),
                    title: plugin.name,
                    subtitle:
                        'v${plugin.version} · ${plugin.author} · '
                        '${plugin.isFeed ? '推荐流' : '弹幕'}',
                  ),
                ],
              ),
              if (plugin.description.isNotEmpty) ...[
                const SizedBox(height: Style.md),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Style.lg),
                  child: Text(
                    plugin.description,
                    style: tokens.text.bodyMedium?.copyWith(
                      color: tokens.colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: Style.xl),
              const _SectionLabel('规则列表'),
              AppGroup(
                children: [
                  for (var index = 0; index < plugin.rules.length; index++)
                    AppListItem(
                      icon: AppIcon(AppIcons.filter()),
                      title: '规则 ${index + 1} · ${_actionLabel(plugin.rules[index])}',
                      subtitle: _conditionSummary(plugin.rules[index].condition),
                    ),
                ],
              ),
              const SizedBox(height: Style.xl),
              const _SectionLabel('运行状态'),
              AppGroup(
                children: [
                  AppListItem(
                    icon: AppIcon(AppIcons.info()),
                    title: '累计命中',
                    subtitle: '${manager.statsOf(pluginId)} 次',
                  ),
                  AppListItem(
                    icon: AppIcon(AppIcons.refresh()),
                    title: '重置统计',
                    subtitle: '只清零命中次数，不影响规则',
                    onTap: () async {
                      await manager.resetStats(pluginId);
                      if (context.mounted) showToast(context, '统计已重置');
                    },
                  ),
                  AppListItem(
                    icon: AppIcon(AppIcons.link()),
                    title: '打开所在文件夹',
                    subtitle: loaded.sourcePath,
                    onTap: () => _openFolder(context, loaded!.sourcePath),
                  ),
                ],
              ),
              const SizedBox(height: Style.xl),
              const _SectionLabel('危险操作'),
              AppGroup(
                children: [
                  AppListItem(
                    icon: AppIcon(AppIcons.delete(), color: tokens.colors.error),
                    title: '删除插件',
                    subtitle: '删除本地规则文件并清除启用状态与统计',
                    iconTint: tokens.colors.error,
                    onTap: () => _confirmDelete(context, manager, plugin),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  static String _actionLabel(JsonRule rule) =>
      rule.isHide ? '隐藏' : '高亮';

  static String _conditionSummary(RuleCondition condition) {
    switch (condition) {
      case SimpleRuleCondition():
        return '${condition.field} ${_opLabel(condition.op)} '
            '${_valueText(condition.value)}';
      case AndRuleCondition():
        return '(${condition.conditions.map(_conditionSummary).join(' 且 ')})';
      case OrRuleCondition():
        return '(${condition.conditions.map(_conditionSummary).join(' 或 ')})';
    }
  }

  static String _opLabel(String op) => switch (op) {
        'eq' => '=',
        'ne' => '≠',
        'lt' => '<',
        'le' => '≤',
        'gt' => '>',
        'ge' => '≥',
        'contains' => '包含',
        'startsWith' => '开头是',
        'endsWith' => '结尾是',
        'regex' => '正则匹配',
        'in' => '属于',
        _ => op,
      };

  static String _valueText(Object? value) {
    if (value is List) return '[${value.join(', ')}]';
    return value?.toString() ?? 'null';
  }

  Future<void> _openFolder(BuildContext context, String path) async {
    try {
      final directory = File(path).parent;
      if (Platform.isWindows) {
        await Process.start('explorer', [directory.path]);
      } else if (Platform.isMacOS) {
        await Process.start('open', [directory.path]);
      } else {
        await Process.start('xdg-open', [directory.path]);
      }
    } catch (error) {
      if (context.mounted) showToast(context, '打开文件夹失败：$error');
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    RulePluginManager manager,
    JsonRulePlugin plugin,
  ) async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AppAlertDialog(
        title: const Text('删除插件'),
        content: Text('确定删除「${plugin.name}」吗？本地规则文件、启用状态与命中统计都会被清除。'),
        actions: [
          MiuixTextButton(
            '取消',
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          MiuixTextButton(
            '删除',
            colors: MiuixButtonDefaults.buttonColorsPrimary(dialogContext),
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await manager.remove(plugin.id);
    if (!context.mounted) return;
    showToast(context, '已删除「${plugin.name}」');
    Navigator.of(context).pop();
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        left: Style.lg,
        bottom: Style.sm,
      ),
      child: Text(
        text,
        style: tokens.text.labelMedium?.copyWith(
          color: tokens.colors.outline,
        ),
      ),
    );
  }
}
