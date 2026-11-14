import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart'
    show MiuixButtonDefaults, MiuixTextButton;

import 'package:winwin/common/widgets/app_dialog_shell.dart';
import 'package:winwin/core/shell/app_dialogs.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/models/video/rec_video_item.dart';
import 'package:winwin/pages/setting/widgets/normal_item.dart';
import 'package:winwin/pages/setting/widgets/select_dialog.dart';
import 'package:winwin/pages/setting/widgets/slider_dialog.dart';
import 'package:winwin/plugin/api/app_plugin.dart';
import 'package:winwin/plugin/api/plugin_capability.dart';
import 'package:winwin/plugin/api/plugin_manager.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/app_components.dart';

import 'feed_filter_policy.dart';

/// 推荐流过滤插件（移植自 BiliPai `BiliPaiFeedFilterPlugin`）。
///
/// 规则：白名单 → 已关注豁免 → 时长 → 播放量/点赞率 → 标题关键词 →
/// 屏蔽用户 → 分区关键词。
class FeedFilterPlugin extends BuiltinPlugin {
  static const String pluginId = 'bilipai_feed_filter';

  FeedFilterConfig _config = const FeedFilterConfig();
  RegExp? _titleRegex;
  RegExp? _zoneRegex;
  bool _loaded = false;

  FeedFilterConfig get config => _config;

  @override
  String get id => pluginId;

  @override
  String get name => '推荐流过滤';

  @override
  String get description =>
      '移植自 BiliPai 的推荐流过滤：时长、播放量、点赞率、标题关键词、屏蔽用户与白名单';

  @override
  String get version => '1.0.0';

  @override
  String get author => 'BiliPai';

  @override
  Set<PluginCapability> get capabilities => {
        PluginCapability.recommendationCandidates,
      };

  @override
  bool get defaultEnabled => false;

  @override
  Future<void> onEnable() async {
    _loaded = false;
    ensureLoaded();
  }

  @override
  Future<void> onDisable() async {
    _titleRegex = null;
    _zoneRegex = null;
  }

  void ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    _config = FeedFilterConfig.fromJson(
      PluginManager.instance.store.config(pluginId),
    );
    _rebuildRegexes();
  }

  Future<void> updateConfig(FeedFilterConfig next) async {
    _config = next;
    _loaded = true;
    _rebuildRegexes();
    await PluginManager.instance.store.setConfig(pluginId, next.toJson());
  }

  bool shouldShow(
    BaseRcmdVideoItemModel item, {
    FeedKind kind = FeedKind.recommend,
  }) {
    ensureLoaded();
    return FeedFilterPolicy.shouldShow(
      config: _config,
      item: item,
      kind: kind,
      titleRegex: _titleRegex,
      zoneRegex: _zoneRegex,
    );
  }

  void _rebuildRegexes() {
    _titleRegex = FeedFilterPolicy.parseBanWordToRegex(
      _config.banWordForRecommend,
    );
    _zoneRegex = FeedFilterPolicy.parseBanWordToRegex(
      _config.banWordForZone,
    );
  }

  @override
  Widget buildSettings(BuildContext context) =>
      _FeedFilterSettings(plugin: this);
}

class _FeedFilterSettings extends StatefulWidget {
  const _FeedFilterSettings({required this.plugin});

  final FeedFilterPlugin plugin;

  @override
  State<_FeedFilterSettings> createState() => _FeedFilterSettingsState();
}

class _FeedFilterSettingsState extends State<_FeedFilterSettings> {
  late FeedFilterConfig _config;

  @override
  void initState() {
    super.initState();
    widget.plugin.ensureLoaded();
    _config = widget.plugin.config;
  }

  Future<void> _update(FeedFilterConfig next) async {
    setState(() => _config = next);
    await widget.plugin.updateConfig(next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel('过滤规则'),
        AppGroup(
          children: [
            NormalItem(
              title: '视频时长过滤',
              subtitle: _config.minDurationForRcmd == 0
                  ? '不过滤'
                  : '隐藏时长小于 ${_config.minDurationForRcmd} 秒的视频',
              leading: AppIcon(AppIcons.timer()),
              onTap: (dialogContext, refresh) async {
                final value = await showAppDialog<double>(
                  context: dialogContext,
                  builder: (_) => AppSliderDialog(
                    title: '视频时长过滤',
                    value: _config.minDurationForRcmd.toDouble(),
                    min: 0,
                    max: 300,
                    divisions: 60,
                    suffix: ' 秒',
                  ),
                );
                if (value == null) return;
                await _update(
                  _config.copyWith(minDurationForRcmd: value.round()),
                );
                refresh();
              },
            ),
            NormalItem(
              title: '播放量过滤',
              subtitle: _config.minPlayForRcmd == 0
                  ? '不过滤'
                  : '隐藏播放量低于 ${_config.minPlayForRcmd} 的视频',
              leading: AppIcon(AppIcons.play()),
              onTap: (dialogContext, refresh) async {
                final value = await showSelectDialog<int>(
                  dialogContext,
                  title: '播放量过滤',
                  value: _config.minPlayForRcmd,
                  values: const [
                    (0, '不过滤'),
                    (50, '50'),
                    (100, '100'),
                    (500, '500'),
                    (1000, '1000'),
                    (5000, '5000'),
                  ],
                );
                if (value == null) return;
                await _update(_config.copyWith(minPlayForRcmd: value));
                refresh();
              },
            ),
            NormalItem(
              title: '点赞率过滤',
              subtitle: _config.minLikeRatioForRecommend == 0
                  ? '不过滤'
                  : '隐藏点赞率低于 ${_config.minLikeRatioForRecommend}% 的视频',
              leading: AppIcon(AppIcons.like()),
              onTap: (dialogContext, refresh) async {
                final value = await showSelectDialog<int>(
                  dialogContext,
                  title: '点赞率过滤',
                  value: _config.minLikeRatioForRecommend,
                  values: const [
                    (0, '不过滤'),
                    (1, '1%'),
                    (2, '2%'),
                    (3, '3%'),
                    (4, '4%'),
                    (5, '5%'),
                  ],
                );
                if (value == null) return;
                await _update(
                  _config.copyWith(minLikeRatioForRecommend: value),
                );
                refresh();
              },
            ),
            _SwitchRow(
              title: '已关注 UP 主豁免',
              subtitle: '推荐流中已关注的 UP 主不受过滤影响',
              icon: AppIcon(AppIcons.favorite()),
              value: _config.exemptFilterForFollowed,
              onChanged: (value) => _update(
                _config.copyWith(exemptFilterForFollowed: value),
              ),
            ),
          ],
        ),
        const SizedBox(height: Style.xl),
        _SectionLabel('关键词过滤'),
        AppGroup(
          children: [
            NormalItem(
              title: '标题关键词',
              subtitle: _config.banWordForRecommend.isEmpty
                  ? '每行一个关键词，支持正则'
                  : '已配置 ${_lineCount(_config.banWordForRecommend)} 行规则',
              leading: AppIcon(AppIcons.filter()),
              onTap: (dialogContext, refresh) async {
                final value = await _editMultiline(
                  dialogContext,
                  title: '标题关键词',
                  hint: '每行一个关键词，支持正则',
                  value: _config.banWordForRecommend,
                );
                if (value == null) return;
                await _update(_config.copyWith(banWordForRecommend: value));
                refresh();
              },
            ),
            NormalItem(
              title: '分区关键词',
              subtitle: _config.banWordForZone.isEmpty
                  ? '按分区名（tname）过滤，每行一个，支持正则'
                  : '已配置 ${_lineCount(_config.banWordForZone)} 行规则',
              leading: AppIcon(AppIcons.block()),
              onTap: (dialogContext, refresh) async {
                final value = await _editMultiline(
                  dialogContext,
                  title: '分区关键词',
                  hint: '按分区名过滤，每行一个，支持正则',
                  value: _config.banWordForZone,
                );
                if (value == null) return;
                await _update(_config.copyWith(banWordForZone: value));
                refresh();
              },
            ),
          ],
        ),
        const SizedBox(height: Style.xl),
        _SectionLabel('屏蔽用户 / 白名单'),
        AppGroup(
          children: [
            NormalItem(
              title: '屏蔽用户',
              subtitle: _config.recommendBlockedMids.isEmpty
                  ? '每行一个 UID，推荐流中隐藏其视频'
                  : '已屏蔽 ${_config.recommendBlockedMids.length} 位用户',
              leading: AppIcon(AppIcons.block()),
              onTap: (dialogContext, refresh) async {
                final value = await _editMultiline(
                  dialogContext,
                  title: '屏蔽用户',
                  hint: '每行一个 UID，或「名称 (UID)」',
                  value: FeedFilterPolicy.uidMapToEditorText(
                    _config.recommendBlockedMids,
                  ),
                );
                if (value == null) return;
                await _update(
                  _config.copyWith(
                    recommendBlockedMids:
                        FeedFilterPolicy.parseUidMap(value),
                  ),
                );
                refresh();
              },
            ),
            NormalItem(
              title: '白名单用户',
              subtitle: _config.whitelistMids.isEmpty
                  ? '每行一个 UID，白名单用户完全豁免过滤'
                  : '已豁免 ${_config.whitelistMids.length} 位用户',
              leading: AppIcon(AppIcons.people()),
              onTap: (dialogContext, refresh) async {
                final value = await _editMultiline(
                  dialogContext,
                  title: '白名单用户',
                  hint: '每行一个 UID，或「名称 (UID)」',
                  value: FeedFilterPolicy.uidMapToEditorText(
                    _config.whitelistMids,
                  ),
                );
                if (value == null) return;
                await _update(
                  _config.copyWith(
                    whitelistMids: FeedFilterPolicy.parseUidMap(value),
                  ),
                );
                refresh();
              },
            ),
          ],
        ),
        const SizedBox(height: Style.xl),
        _SectionLabel('应用于其他信息流'),
        AppGroup(
          children: [
            _SwitchRow(
              title: '热门视频',
              subtitle: '过滤器也应用于热门页',
              icon: AppIcon(AppIcons.play()),
              value: _config.applyToHotVideos,
              onChanged: (value) =>
                  _update(_config.copyWith(applyToHotVideos: value)),
            ),
            _SwitchRow(
              title: '排行榜',
              subtitle: '过滤器也应用于排行榜',
              icon: AppIcon(AppIcons.chapter()),
              value: _config.applyToRankVideos,
              onChanged: (value) =>
                  _update(_config.copyWith(applyToRankVideos: value)),
            ),
            _SwitchRow(
              title: '搜索结果',
              subtitle: '过滤器也应用于搜索页',
              icon: AppIcon(AppIcons.search()),
              value: _config.applyToSearch,
              onChanged: (value) =>
                  _update(_config.copyWith(applyToSearch: value)),
            ),
          ],
        ),
      ],
    );
  }

  static int _lineCount(String text) =>
      text.split('\n').where((line) => line.trim().isNotEmpty).length;

  Future<String?> _editMultiline(
    BuildContext context, {
    required String title,
    required String hint,
    required String value,
  }) async {
    final controller = TextEditingController(text: value);
    try {
      return await showAppDialog<String>(
        context: context,
        builder: (dialogContext) => AppAlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 480,
            child: AppTextField(
              controller: controller,
              hint: hint,
              minLines: 4,
              maxLines: 8,
            ),
          ),
          actions: [
            MiuixTextButton(
              '取消',
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            MiuixTextButton(
              '保存',
              colors: MiuixButtonDefaults.buttonColorsPrimary(dialogContext),
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final Widget icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppListItem(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: AppSwitch(value: value, onChanged: onChanged),
      onTap: () => onChanged(!value),
    );
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
