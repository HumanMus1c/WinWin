import 'package:winwin/plugin/api/app_plugin.dart';

import 'eye_protection/eye_protection_plugin.dart';
import 'feed_filter/feed_filter_plugin.dart';
import 'home_feed_anonymizer/home_feed_anonymizer_plugin.dart';
import 'sponsor_block/sponsor_block_plugin.dart';

/// 内置插件清单（注册顺序 = 插件中心展示顺序）。
List<BuiltinPlugin> get builtinPlugins => [
      SponsorBlockPlugin(),
      FeedFilterPlugin(),
      EyeProtectionPlugin(),
      HomeFeedAnonymizerPlugin(),
    ];
