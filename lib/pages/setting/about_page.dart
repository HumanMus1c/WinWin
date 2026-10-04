import 'package:material_ui/material_ui.dart';

import 'package:winwin/pages/onboarding/user_agreement_page.dart';
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
          _buildInfoSection(context, theme),
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

  Widget _buildInfoSection(BuildContext context, ThemeData theme) {
    return AppGroup(
      children: [
        AppListItem(
          icon: const Icon(Icons.code),
          title: '项目说明',
          subtitle: 'WinWin 是基于 PiliPlus 的 Bilibili 桌面客户端移植版，使用 Flutter + fvp/mdk 内核构建。',
        ),
        AppListItem(
          icon: const Icon(Icons.source_outlined),
          title: '开源协议',
          subtitle: 'GPL-3.0｜点击查看用户条款',
          onTap: () => _showAgreementClauses(context),
        ),
      ],
    );
  }

  /// 只读查看用户协议条款（复测反馈：条款在常规流程中无入口）。
  void _showAgreementClauses(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        final theme = Theme.of(dialogCtx);
        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 10, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '开源协议与用户条款',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        tooltip: '关闭',
                        onPressed: () => Navigator.pop(dialogCtx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                const Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(12, 8, 12, 16),
                    child: UserAgreementClauses(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

