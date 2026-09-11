import 'package:flutter/material.dart';

import 'package:winwin/theme/inherited_ui_style.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/app_components.dart';

/// 关于页面。
///
/// 移植自 PiliPlus 的 `AboutPage`，精简为桌面端版本。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  Widget build(BuildContext context) {
    InheritedUiStyle.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: showAppBar ? AppBar(title: const Text('关于')) : null,
      body: ListView(
        padding: const EdgeInsets.all(Style.lg),
        children: [
          _buildHeader(theme),
          const SizedBox(height: Style.lg),
          _buildInfoSection(theme),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Center(
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Style.radiusLg),
              color: theme.colorScheme.primaryContainer,
            ),
            child: Icon(
              Icons.play_circle_filled,
              size: 48,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: Style.md),
          Text(
            'WinWin',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: Style.xs),
          Text(
            'BiliPai Desktop Port',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: Style.sm),
          Text(
            '版本 0.1.0',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(ThemeData theme) {
    return const AppGroup(
      children: [
        AppListItem(
          icon: Icons.code,
          title: '项目说明',
          subtitle: 'WinWin 是基于 PiliPlus 的 Bilibili 桌面客户端移植版，使用 Flutter + fvp/mdk 内核构建。',
        ),
        AppListItem(
          icon: Icons.source_outlined,
          title: '开源协议',
          subtitle: 'GPL-3.0',
        ),
      ],
    );
  }
}

