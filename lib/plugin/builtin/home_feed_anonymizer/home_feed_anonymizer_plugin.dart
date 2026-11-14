import 'package:flutter/widgets.dart';

import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/plugin/api/app_plugin.dart';
import 'package:winwin/plugin/api/plugin_capability.dart';
import 'package:winwin/plugin/api/plugin_manager.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/app_components.dart';

/// 初见推荐插件：Web 首页推荐流不带登录 Cookie。
///
/// 对齐 BiliPai `HomeFeedAnonymizerPlugin`：仅影响 Web 推荐接口，
/// 让推荐结果更接近未登录公共热门；不影响播放、搜索、动态等其他请求。
class HomeFeedAnonymizerPlugin extends BuiltinPlugin {
  static const String pluginId = 'home_feed_anonymizer';

  @override
  String get id => pluginId;

  @override
  String get name => '初见推荐';

  @override
  String get description => '仅在 Web 首页推荐接口隐藏登录 Cookie，让推荐流更接近未登录公共热门';

  @override
  String get version => '1.0.0';

  @override
  String get author => 'BiliPai';

  @override
  Set<PluginCapability> get capabilities => {
        PluginCapability.recommendationCandidates,
        PluginCapability.network,
      };

  @override
  bool get defaultEnabled => false;

  @override
  Future<void> onEnable() async {}

  @override
  Future<void> onDisable() async {}

  /// 供推荐流控制器查询；插件未初始化或未启用时返回 false。
  static bool get active => PluginManager.enabled(pluginId);

  @override
  Widget buildSettings(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppGroup(
          children: [
            AppListItem(
              icon: AppIcon(AppIcons.incognito()),
              title: '匿名推荐',
              subtitle: '启用后，首页推荐流请求不再携带登录 Cookie',
            ),
          ],
        ),
        const SizedBox(height: Style.lg),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Style.lg),
          child: Text(
            '该插件只改变推荐流的请求身份，不会退出登录，也不影响收藏、历史、动态等需要登录态的功能。',
            style: tokens.text.bodySmall?.copyWith(
              color: tokens.colors.outline,
            ),
          ),
        ),
      ],
    );
  }
}
