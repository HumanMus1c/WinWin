import 'package:flutter/material.dart';

import 'package:winwin/pages/setting/about_page.dart';
import 'package:winwin/pages/setting/common_setting.dart';
import 'package:winwin/pages/setting/setting_type.dart';

/// 设置主页面 — 桌面端双栏布局。
///
/// 左侧分类导航（flex 3），右侧内容区（flex 7）。
/// 移植自 PiliPlus 的 `SettingPage`，针对桌面端宽屏优化为固定双栏。
class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  SettingType _type = SettingType.styleSetting;

  static const List<_SettingEntry> _items = [
    _SettingEntry(
      type: SettingType.styleSetting,
      subtitle: '主题模式、字重、界面缩放等',
      icon: Icons.style_outlined,
    ),
    _SettingEntry(
      type: SettingType.playSetting,
      subtitle: '弹幕开关、自动播放、全屏等',
      icon: Icons.touch_app_outlined,
    ),
    _SettingEntry(
      type: SettingType.videoSetting,
      subtitle: '画质、音质、硬解、缓冲等',
      icon: Icons.video_settings_outlined,
    ),
    _SettingEntry(
      type: SettingType.extraSetting,
      subtitle: '网络、代理、日志等',
      icon: Icons.extension_outlined,
    ),
    _SettingEntry(
      type: SettingType.about,
      icon: Icons.info_outline,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final padding = MediaQuery.viewPaddingOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
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
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.3),
                    width: 0.5,
                  ),
                ),
              ),
              child: ListView(
                padding: EdgeInsets.only(bottom: padding.bottom + 100),
                children: _items
                    .map((item) => _buildCategoryTile(theme, item))
                    .toList(),
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

  Widget _buildCategoryTile(ThemeData theme, _SettingEntry item) {
    final isSelected = item.type == _type;
    return ListTile(
      tileColor: isSelected ? theme.colorScheme.onInverseSurface : null,
      onTap: () => setState(() => _type = item.type),
      leading: Icon(item.icon),
      title: Text(
        item.type.title,
        style: theme.textTheme.titleMedium,
      ),
      subtitle: item.subtitle == null
          ? null
          : Text(
              item.subtitle!,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
    );
  }
}

class _SettingEntry {
  final SettingType type;
  final String? subtitle;
  final IconData icon;

  const _SettingEntry({
    required this.type,
    this.subtitle,
    required this.icon,
  });
}
