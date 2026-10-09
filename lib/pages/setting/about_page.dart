import 'package:material_ui/material_ui.dart';

import 'package:winwin/pages/onboarding/user_agreement_page.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/app_components.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/core/shell/app_dialogs.dart';
import 'package:flutter_miuix/miuix.dart' show MiuixTopAppBar;
import 'package:winwin/core/shell/app_scaffold.dart';

/// 关于页面。
///
/// 移植自 PiliPlus 的 `AboutPage`，精简为桌面端版本。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    return AppScaffold(
      topBar: showAppBar ? MiuixTopAppBar(title: '关于') : null,
      body: ListView(
        padding: const EdgeInsets.all(Style.lg),
        children: [
          _buildHeader(tokens),
          const SizedBox(height: Style.lg),
          _buildInfoSection(context, tokens),
        ],
      ),
    );
  }

  Widget _buildHeader(AppTokens tokens) {
    return Center(
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Style.radiusLg),
              color: tokens.colors.primaryContainer,
            ),
            child: AppIcon(AppIcons.play(active: true),
              size: 48,
              color: tokens.colors.primary,
            ),
          ),
          const SizedBox(height: Style.md),
          Text(
            'WinWin',
            style: tokens.text.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: Style.xs),
          Text(
            'BiliPai Desktop Port',
            style: tokens.text.bodySmall?.copyWith(
              color: tokens.colors.outline,
            ),
          ),
          const SizedBox(height: Style.sm),
          Text(
            '版本 0.1.0',
            style: tokens.text.bodySmall?.copyWith(
              color: tokens.colors.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(BuildContext context, AppTokens tokens) {
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
    showAppDialog<void>(
      context: context,
      builder: (dialogCtx) {
        final tokens = AppThemeHost.of(dialogCtx);
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
                          style: tokens.text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: AppIcon(AppIcons.clear(), size: 20),
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

