import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import 'package:winwin/core/player/sponsorblock_usecase.dart';
import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/core/storage/storage_key.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/http/constants.dart';
import 'package:winwin/plugin/api/app_plugin.dart';
import 'package:winwin/plugin/api/plugin_capability.dart';
import 'package:winwin/plugin/api/plugin_manager.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/app_components.dart';

/// 空降助手（SponsorBlock）插件。
///
/// 包装既有 [SponsorBlockUseCase]：插件只负责「启用状态 + 分段类型开关」，
/// 段落拉取与自动跳过仍在播放器控制器中执行。
class SponsorBlockPlugin extends BuiltinPlugin {
  static const String pluginId = 'sponsor_block';

  static const String _configCategoriesKey = 'categories';
  static const String _configCommunityEnabledKey =
      'communityContributionEnabled';
  static const String _configUserIdKey = 'userId';

  final Map<SponsorBlockCategory, bool> _categories = {
    for (final category in SponsorBlockCategory.values)
      category: category.defaultSkipEnabled,
  };

  bool _loaded = false;
  bool _communityContributionEnabled = false;
  String _userId = '';

  /// 社区上报开关：默认关闭，首次开启后仍需在播放页逐次确认提交。
  bool get communityContributionEnabled {
    ensureLoaded();
    return _communityContributionEnabled;
  }

  /// 社区匿名用户 ID（30+ 位字母数字），用于归属贡献。
  String get userId {
    ensureLoaded();
    if (_userId.isEmpty) {
      _userId = const Uuid().v4().replaceAll('-', '');
      unawaited(_persist());
    }
    return _userId;
  }

  /// 社区服务器（与现有段落拉取共用 bsbsb.top）。
  String get communityServerUrl => HttpString.sponsorBlockBaseUrl;

  @override
  String get id => pluginId;

  @override
  String get name => '空降助手';

  @override
  String get description => '自动跳过视频中的赞助广告、自我推广与互动提醒段落（数据来自 SponsorBlock 镜像）';

  @override
  String get version => '1.0.0';

  @override
  String get author => 'BiliPai';

  @override
  Set<PluginCapability> get capabilities => {
        PluginCapability.network,
        PluginCapability.playerControl,
      };

  @override
  bool get defaultEnabled => true;

  @override
  Future<void> onEnable() async {
    _loaded = false;
    ensureLoaded();
  }

  @override
  Future<void> onDisable() async {
    // 配置保留；播放器控制器会因插件禁用而不再调用跳过逻辑。
  }

  void ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    final config = PluginManager.instance.store.config(pluginId);
    final raw = config?[_configCategoriesKey];
    if (raw is Map) {
      for (final category in SponsorBlockCategory.values) {
        final value = raw[category.name];
        if (value is bool) {
          _categories[category] = value;
        }
      }
    }
    _communityContributionEnabled =
        config?[_configCommunityEnabledKey] == true;
    final storedUserId = config?[_configUserIdKey]?.toString() ?? '';
    if (storedUserId.length >= 30) {
      _userId = storedUserId;
    } else {
      _userId = const Uuid().v4().replaceAll('-', '');
      unawaited(_persist());
    }
  }

  Future<void> _persist() {
    return PluginManager.instance.store.setConfig(pluginId, {
      _configCategoriesKey: {
        for (final entry in _categories.entries) entry.key.name: entry.value,
      },
      _configCommunityEnabledKey: _communityContributionEnabled,
      _configUserIdKey: _userId,
    });
  }

  bool isCategoryEnabled(SponsorBlockCategory category) {
    ensureLoaded();
    return _categories[category] ?? category.defaultSkipEnabled;
  }

  Future<void> setCategoryEnabled(
    SponsorBlockCategory category,
    bool enabled,
  ) async {
    ensureLoaded();
    _categories[category] = enabled;
    await _persist();
  }

  /// 社区上报开关（默认关闭）。
  Future<void> setCommunityContributionEnabled(bool enabled) async {
    ensureLoaded();
    _communityContributionEnabled = enabled;
    await _persist();
  }

  /// 把当前分段开关应用到某个播放会话的用例。
  void applyConfigTo(SponsorBlockUseCase useCase) {
    ensureLoaded();
    for (final entry in _categories.entries) {
      useCase.setSkipEnabled(entry.key, entry.value);
    }
  }

  /// 兼容迁移：旧版本只有 `enableSponsorBlock` 一个开关。
  ///
  /// 仅当插件状态缺失时执行一次，之后以插件状态为唯一事实来源。
  static Future<void> migrateLegacyEnabledState() async {
    final store = PluginManager.instance.store;
    if (store.enabledOrNull(pluginId) != null) return;
    final legacy = GStorage.setting.get(
      SettingBoxKey.enableSponsorBlock,
      defaultValue: true,
    );
    await store.setEnabled(pluginId, legacy is bool ? legacy : true);
  }

  @override
  Widget buildSettings(BuildContext context) => _SponsorBlockSettings(this);
}

class _SponsorBlockSettings extends StatefulWidget {
  const _SponsorBlockSettings(this.plugin);

  final SponsorBlockPlugin plugin;

  @override
  State<_SponsorBlockSettings> createState() => _SponsorBlockSettingsState();
}

class _SponsorBlockSettingsState extends State<_SponsorBlockSettings> {
  @override
  void initState() {
    super.initState();
    widget.plugin.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: Style.lg, bottom: Style.sm),
          child: Text(
            '自动跳过的段落类型',
            style: tokens.text.labelMedium?.copyWith(
              color: tokens.colors.outline,
            ),
          ),
        ),
        AppGroup(
          children: [
            for (final category in SponsorBlockCategory.values)
              if (category != SponsorBlockCategory.unknown)
                AppListItem(
                  icon: AppIcon(AppIcons.sponsorBlock()),
                  title: category.label,
                  subtitle: category.defaultSkipEnabled
                      ? '默认开启'
                      : '默认关闭，可按需开启',
                  trailing: AppSwitch(
                    value: widget.plugin.isCategoryEnabled(category),
                    onChanged: (value) async {
                      setState(() {
                        unawaited(
                          widget.plugin.setCategoryEnabled(category, value),
                        );
                      });
                    },
                  ),
                  onTap: () {
                    final next =
                        !widget.plugin.isCategoryEnabled(category);
                    setState(() {
                      unawaited(
                        widget.plugin.setCategoryEnabled(category, next),
                      );
                    });
                  },
                ),
          ],
        ),
        const SizedBox(height: Style.lg),
        Padding(
          padding: const EdgeInsets.only(left: Style.lg, bottom: Style.sm),
          child: Text(
            '社区上报',
            style: tokens.text.labelMedium?.copyWith(
              color: tokens.colors.outline,
            ),
          ),
        ),
        AppGroup(
          children: [
            AppListItem(
              icon: AppIcon(AppIcons.sponsorBlock(active: true)),
              title: '允许上报社区片段',
              subtitle: '默认关闭；开启后每次提交仍需在播放页确认',
              trailing: AppSwitch(
                value: widget.plugin.communityContributionEnabled,
                onChanged: (value) async {
                  await widget.plugin.setCommunityContributionEnabled(value);
                  if (mounted) setState(() {});
                },
              ),
              onTap: () async {
                await widget.plugin.setCommunityContributionEnabled(
                  !widget.plugin.communityContributionEnabled,
                );
                if (mounted) setState(() {});
              },
            ),
            AppListItem(
              icon: AppIcon(AppIcons.info()),
              title: '社区用户 ID',
              subtitle:
                  '${widget.plugin.userId.substring(0, 8)}… · 用于归属你的片段贡献',
            ),
            AppListItem(
              icon: AppIcon(AppIcons.link()),
              title: '社区服务器',
              subtitle: widget.plugin.communityServerUrl,
            ),
          ],
        ),
        const SizedBox(height: Style.lg),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Style.lg),
          child: Text(
            '段落数据来自 bsbsb.top 镜像。无段落数据或网络失败时不会影响正常播放。',
            style: tokens.text.bodySmall?.copyWith(
              color: tokens.colors.outline,
            ),
          ),
        ),
      ],
    );
  }
}
