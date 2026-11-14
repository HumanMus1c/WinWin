import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart'
    show MiuixButtonDefaults, MiuixTextButton;

import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/common/widgets/app_dialog_shell.dart';
import 'package:winwin/core/shell/app_dialogs.dart';
import 'package:winwin/core/shell/app_routes.dart';
import 'package:winwin/core/shell/app_scaffold.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/plugin/api/app_plugin.dart';
import 'package:winwin/plugin/api/plugin_manager.dart';
import 'package:winwin/plugin/rules/json_rule_plugin.dart';
import 'package:winwin/plugin/rules/rule_plugin_manager.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/app_components.dart';

import 'plugin_detail_page.dart';
import 'rule_plugin_detail_page.dart';

/// 插件中心（对应 BiliPai `PluginsScreen`）。
///
/// 信息架构：
/// 1. 概览（已安装 / 已启用）
/// 2. 内置插件
/// 3. 可安装插件（随包分发的规则包）
/// 4. 已安装规则插件
/// 5. 导入外部插件（本地 / 链接）
/// 6. 提示设置
class PluginManagerPage extends StatefulWidget {
  const PluginManagerPage({super.key, this.showAppBar = false});

  final bool showAppBar;

  @override
  State<PluginManagerPage> createState() => _PluginManagerPageState();
}

class _PluginManagerPageState extends State<PluginManagerPage> {
  bool _importing = false;

  PluginManager? get _manager => PluginManager.maybeInstance;

  RulePluginManager? get _rules => RulePluginManager.maybeInstance;

  @override
  Widget build(BuildContext context) {
    final manager = _manager;
    final rules = _rules;
    if (manager == null) {
      return AppScaffold(
        reserveTopStrip: widget.showAppBar,
        body: const Center(child: Text('插件系统尚未初始化')),
      );
    }

    final listenables = <Listenable>[
      manager.plugins,
      if (rules != null) rules.plugins,
      if (rules != null) rules.stats,
    ];

    return AppScaffold(
      reserveTopStrip: widget.showAppBar,
      body: ListenableBuilder(
        listenable: Listenable.merge(listenables),
        builder: (context, _) {
          final builtin = manager.plugins.value;
          final installedRules = rules?.plugins.value ?? const <LoadedRulePlugin>[];
          final installedIds = {
            for (final item in installedRules) item.plugin.id,
          };
          final availableBundled = [
            for (final bundled in bundledRulePlugins)
              if (!installedIds.any(
                (id) => bundled.assetPath.endsWith('$id.json'),
              ))
                bundled,
          ];
          final enabledCount =
              builtin.where((info) => info.enabled).length +
                  installedRules.where((item) => item.enabled).length;
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
                    icon: AppIcon(AppIcons.plugin()),
                    title: '插件中心',
                    subtitle:
                        '已安装 ${builtin.length + installedRules.length} 个插件 · 已启用 $enabledCount 个',
                  ),
                ],
              ),
              const SizedBox(height: Style.xl),
              const _SectionLabel('内置插件'),
              AppGroup(
                children: [
                  for (final info in builtin)
                    AppListItem(
                      icon: _builtinIcon(info.plugin.id),
                      title: info.plugin.name,
                      subtitle:
                          'v${info.plugin.version} · ${info.plugin.description}',
                      trailing: AppSwitch(
                        value: info.enabled,
                        onChanged: (value) =>
                            _toggleBuiltin(info.plugin.id, value),
                      ),
                      onTap: () => _openBuiltin(info.plugin),
                    ),
                ],
              ),
              if (availableBundled.isNotEmpty) ...[
                const SizedBox(height: Style.xl),
                const _SectionLabel('可安装插件'),
                AppGroup(
                  children: [
                    for (final bundled in availableBundled)
                      AppListItem(
                        icon: AppIcon(AppIcons.rulePlugin()),
                        title: bundled.title,
                        subtitle: bundled.subtitle,
                        trailing: AppPrimaryButton(
                          onPressed: _importing
                              ? null
                              : () => _installBundled(bundled),
                          minWidth: 64,
                          minHeight: 32,
                          insideMargin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: const Text('安装'),
                        ),
                        onTap: _importing
                            ? null
                            : () => _installBundled(bundled),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: Style.xl),
              const _SectionLabel('已安装规则插件'),
              if (installedRules.isEmpty)
                AppGroup(
                  children: [
                    AppListItem(
                      icon: AppIcon(AppIcons.rulePlugin()),
                      title: '暂无规则插件',
                      subtitle: '可从上方安装内置规则包，或从本地/链接导入',
                    ),
                  ],
                )
              else
                AppGroup(
                  children: [
                    for (final item in installedRules)
                      AppListItem(
                        icon: AppIcon(AppIcons.rulePlugin()),
                        title: item.plugin.name,
                        subtitle:
                            '${item.plugin.isFeed ? '推荐流' : '弹幕'} · '
                            '${item.plugin.rules.length} 条规则 · '
                            '命中 ${rules?.statsOf(item.plugin.id) ?? 0} 次',
                        trailing: AppSwitch(
                          value: item.enabled,
                          onChanged: (value) =>
                              _toggleRule(item.plugin.id, value),
                        ),
                        onTap: () => _openRule(item.plugin.id),
                      ),
                  ],
                ),
              const SizedBox(height: Style.xl),
              const _SectionLabel('导入外部插件'),
              AppGroup(
                children: [
                  AppListItem(
                    icon: AppIcon(AppIcons.pluginImport()),
                    title: '从文件导入',
                    subtitle: '选择 .json 规则包，安装前预览规则与能力',
                    trailing: AppIcon(AppIcons.chevronForward()),
                    onTap: _importing ? null : _importFromFile,
                  ),
                  AppListItem(
                    icon: AppIcon(AppIcons.link()),
                    title: '从链接导入',
                    subtitle: '支持 http/https 直链，安装前预览规则与能力',
                    trailing: AppIcon(AppIcons.chevronForward()),
                    onTap: _importing ? null : _importFromUrl,
                  ),
                ],
              ),
              const SizedBox(height: Style.xl),
              const _SectionLabel('提示设置'),
              AppGroup(
                children: [
                  AppListItem(
                    icon: AppIcon(AppIcons.info()),
                    title: '显示插件生效提示',
                    subtitle: '推荐流过滤命中时在底部显示提示',
                    trailing: AppSwitch(
                      value: manager.effectHintsEnabled,
                      onChanged: (value) async {
                        await manager.setEffectHintsEnabled(value);
                        if (mounted) setState(() {});
                      },
                    ),
                    onTap: () async {
                      await manager.setEffectHintsEnabled(
                        !manager.effectHintsEnabled,
                      );
                      if (mounted) setState(() {});
                    },
                  ),
                ],
              ),
              const SizedBox(height: Style.xl),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Style.lg),
                child: Text(
                  '插件用于扩展应用能力：自动跳过赞助段落、过滤推荐内容、净化弹幕等。'
                  '规则插件只包含声明式 JSON，不执行外部代码；安装后可在列表中随时停用或删除。',
                  style: AppThemeHost.of(context).text.bodySmall?.copyWith(
                        color: AppThemeHost.of(context).colors.outline,
                      ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _builtinIcon(String pluginId) {
    return switch (pluginId) {
      'sponsor_block' => AppIcon(AppIcons.sponsorBlock()),
      'bilipai_feed_filter' => AppIcon(AppIcons.filter()),
      'eye_protection' => AppIcon(AppIcons.eyeCare()),
      'home_feed_anonymizer' => AppIcon(AppIcons.incognito()),
      _ => AppIcon(AppIcons.plugin()),
    };
  }

  Future<void> _toggleBuiltin(String pluginId, bool value) async {
    final ok = await PluginManager.instance.setEnabled(pluginId, value);
    if (!ok && mounted) {
      showToast(context, '插件状态切换失败，请查看运行日志');
    }
  }

  Future<void> _toggleRule(String pluginId, bool value) async {
    final ok = await _rules?.setEnabled(pluginId, value) ?? false;
    if (!ok && mounted) {
      showToast(context, '规则插件状态切换失败，请查看运行日志');
    }
  }

  void _openBuiltin(BuiltinPlugin plugin) {
    Navigator.of(context).push(
      AppRoute<void>(
        builder: (_) => PluginDetailPage(plugin: plugin),
      ),
    );
  }

  void _openRule(String pluginId) {
    Navigator.of(context).push(
      AppRoute<void>(
        builder: (_) => RulePluginDetailPage(pluginId: pluginId),
      ),
    );
  }

  Future<void> _installBundled(BundledRulePlugin bundled) async {
    final rules = _rules;
    if (rules == null || _importing) return;
    setState(() => _importing = true);
    try {
      final plugin = await rules.installBundled(bundled);
      if (!mounted) return;
      showToast(context, '已安装「${plugin.name}」');
    } catch (error) {
      if (mounted) {
        showToast(context, '安装失败：$error', duration: const Duration(seconds: 4));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _importFromFile() async {
    final rules = _rules;
    if (rules == null || _importing) return;
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      final path = file?.path;
      if (path == null) return;
      setState(() => _importing = true);
      final bytes = await File(path).readAsBytes();
      final plugin = await rules.previewBytes(bytes);
      if (!mounted) return;
      final confirmed = await _confirmInstall(plugin);
      if (!confirmed) return;
      await rules.install(plugin, source: path);
      if (mounted) showToast(context, '已安装「${plugin.name}」');
    } catch (error) {
      if (mounted) {
        showToast(context, '导入失败：$error', duration: const Duration(seconds: 4));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _importFromUrl() async {
    final rules = _rules;
    if (rules == null || _importing) return;
    final controller = TextEditingController();
    String? url;
    try {
      url = await showAppDialog<String>(
        context: context,
        builder: (dialogContext) => AppAlertDialog(
          title: const Text('从链接导入'),
          content: SizedBox(
            width: 480,
            child: AppTextField(
              controller: controller,
              hint: 'https://example.com/plugin.json',
              autofocus: true,
            ),
          ),
          actions: [
            MiuixTextButton(
              '取消',
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            MiuixTextButton(
              '获取',
              colors: MiuixButtonDefaults.buttonColorsPrimary(dialogContext),
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
    if (url == null || url.isEmpty || !mounted) return;

    setState(() => _importing = true);
    try {
      final plugin = await rules.previewUrl(url);
      if (!mounted) return;
      final confirmed = await _confirmInstall(plugin);
      if (!confirmed) return;
      await rules.install(plugin, source: url);
      if (mounted) showToast(context, '已安装「${plugin.name}」');
    } catch (error) {
      if (mounted) {
        showToast(context, '导入失败：$error', duration: const Duration(seconds: 4));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<bool> _confirmInstall(JsonRulePlugin plugin) async {
    final result = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AppAlertDialog(
        title: const Text('确认安装插件'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                plugin.name,
                style: AppThemeHost.of(dialogContext)
                    .text
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (plugin.description.isNotEmpty) ...[
                const SizedBox(height: Style.sm),
                Text(plugin.description),
              ],
              const SizedBox(height: Style.sm),
              Text(
                '类型：${plugin.isFeed ? '推荐流' : '弹幕'} · '
                '${plugin.rules.length} 条规则 · v${plugin.version}',
              ),
              if (plugin.capabilities.isNotEmpty) ...[
                const SizedBox(height: Style.xs),
                Text(
                  '能力：${plugin.capabilities.map((c) => c.label).join('、')}',
                ),
              ],
              const SizedBox(height: Style.sm),
              Text(
                '规则插件只包含声明式 JSON，不执行外部代码。',
                style: AppThemeHost.of(dialogContext).text.bodySmall?.copyWith(
                      color: AppThemeHost.of(dialogContext).colors.outline,
                    ),
              ),
            ],
          ),
        ),
        actions: [
          MiuixTextButton(
            '取消',
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          MiuixTextButton(
            '安装',
            colors: MiuixButtonDefaults.buttonColorsPrimary(dialogContext),
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    return result == true;
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
