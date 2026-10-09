import 'package:material_ui/material_ui.dart';

import 'package:winwin/pages/setting/about_page.dart';
import 'package:winwin/pages/setting/common_setting.dart';
import 'package:winwin/pages/setting/setting_type.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/app_components.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:flutter_miuix/miuix.dart' show MiuixSmallTopAppBar;
import 'package:winwin/core/shell/app_scaffold.dart';

/// 设置主页面 — 桌面端双栏布局。
///
/// 左侧分类导航（flex 3），右侧内容区（flex 7）。
/// 移植自 PiliPlus 的 `SettingPage`，针对桌面端宽屏优化为固定双栏。
///
/// Phase 7.8：左侧导航改用 [AppGroup] / [AppListItem] 美化。
class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  SettingType _type = SettingType.styleSetting;

  static final List<_SettingEntry> _items = [
    _SettingEntry(
      type: SettingType.styleSetting,
      subtitle: '主题模式、字重、界面缩放等',
      icon: Icon(Icons.style_outlined),
    ),
    _SettingEntry(
      type: SettingType.playSetting,
      subtitle: '弹幕开关、自动播放、全屏等',
      icon: Icon(Icons.touch_app_outlined),
    ),
    _SettingEntry(
      type: SettingType.videoSetting,
      subtitle: '画质、音质、硬解、缓冲等',
      icon: Icon(Icons.video_settings_outlined),
    ),
    _SettingEntry(
      type: SettingType.extraSetting,
      subtitle: '网络、代理、日志等',
      icon: Icon(Icons.extension_outlined),
    ),
    _SettingEntry(
      type: SettingType.about,
      icon: AppIcon(AppIcons.info()),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final padding = MediaQuery.viewPaddingOf(context);
    return AppScaffold(
      topBar: MiuixSmallTopAppBar(title: '设置'),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧分类导航
          Expanded(
            flex: 3,
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: tokens.colors.outlineVariant
                        .withValues(alpha: 0.3),
                    width: 0.5,
                  ),
                ),
              ),
              child: ListView(
                padding: EdgeInsets.only(
                  left: Style.md,
                  right: Style.md,
                  top: Style.md,
                  bottom: padding.bottom + 100,
                ),
                children: [
                  // ── 分类导航 ──
                  AppGroup(
                    children: _items
                        .map((item) => _buildCategoryItem(tokens, item))
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
          // 右侧内容区
          Expanded(
            flex: 7,
            child: switch (_type) {
              .styleSetting ||
              .playSetting ||
              .videoSetting ||
              .extraSetting =>
                CommonSetting(settingType: _type, showAppBar: false),
              .about => const AboutPage(showAppBar: false),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryItem(AppTokens tokens, _SettingEntry item) {
    final isSelected = item.type == _type;
    return AppListItem(
      icon: item.icon,
      title: item.type.title,
      subtitle: item.subtitle,
      iconTint: isSelected
          ? tokens.colors.primary
          : tokens.colors.onSurfaceVariant,
      trailing: isSelected
          ? Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: tokens.colors.primary,
                shape: BoxShape.circle,
              ),
            )
          : null,
      onTap: () => setState(() => _type = item.type),
    );
  }
}

class _SettingEntry {
  final SettingType type;
  final String? subtitle;
  final Widget icon;

  const _SettingEntry({
    required this.type,
    this.subtitle,
    required this.icon,
  });
}
