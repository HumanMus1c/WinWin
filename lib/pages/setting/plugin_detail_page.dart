import 'package:flutter/widgets.dart';

import 'package:winwin/core/shell/app_scaffold.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/plugin/api/app_plugin.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/app_components.dart';

/// 内置插件详情：身份信息 + 能力清单 + 插件自带设置区。
class PluginDetailPage extends StatelessWidget {
  const PluginDetailPage({super.key, required this.plugin});

  final BuiltinPlugin plugin;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final padding = MediaQuery.viewPaddingOf(context);
    return AppScaffold(
      title: plugin.name,
      reserveTopStrip: true,
      body: ListView(
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
                icon: _iconFor(plugin.id),
                title: plugin.name,
                subtitle: 'v${plugin.version} · ${plugin.author}',
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
          if (plugin.capabilities.isNotEmpty) ...[
            const SizedBox(height: Style.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Style.lg),
              child: Wrap(
                spacing: Style.sm,
                runSpacing: Style.sm,
                children: [
                  for (final capability in plugin.capabilities)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Style.md,
                        vertical: Style.xs,
                      ),
                      decoration: BoxDecoration(
                        color: tokens.colors.surfaceContainerHigh,
                        borderRadius:
                            BorderRadius.circular(Style.radiusFull),
                      ),
                      child: Text(
                        capability.label,
                        style: tokens.text.labelSmall?.copyWith(
                          color: tokens.colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: Style.xl),
          plugin.buildSettings(context),
        ],
      ),
    );
  }

  Widget _iconFor(String pluginId) {
    return switch (pluginId) {
      'sponsor_block' => AppIcon(AppIcons.sponsorBlock()),
      'bilipai_feed_filter' => AppIcon(AppIcons.filter()),
      'eye_protection' => AppIcon(AppIcons.eyeCare()),
      'home_feed_anonymizer' => AppIcon(AppIcons.incognito()),
      _ => AppIcon(AppIcons.plugin()),
    };
  }
}
