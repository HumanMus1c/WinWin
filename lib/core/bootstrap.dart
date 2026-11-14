import 'dart:async';

import 'package:winwin/core/account/account_service.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/core/account/login_utils.dart';
import 'package:winwin/core/log/app_logger.dart';
import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/plugin/api/plugin_manager.dart';
import 'package:winwin/plugin/builtin/builtin_plugins.dart';
import 'package:winwin/plugin/builtin/sponsor_block/sponsor_block_plugin.dart';
import 'package:winwin/plugin/rules/rule_plugin_manager.dart';
import 'package:winwin/utils/wbi_sign.dart';

/// Startup bootstrap shared by `main()` and lazily-created controllers.
///
/// Must NOT be awaited before `runApp()`: the Windows runner only shows the
/// window after Flutter renders its first frame, so blocking `main()` on
/// storage/network init would leave the window hidden forever.
Future<void>? _bootstrap;

Future<void> ensureBootstrap() {
  return _bootstrap ??= _run().catchError((Object error, StackTrace stackTrace) {
    _bootstrap = null;
    throw error;
  });
}

Future<void> _run() async {
  await GStorage.init();
  // 兼容迁移：旧「显示托盘图标 / 退出时最小化」两项合并为 closeToTray。
  await Pref.migrateLegacyTrayKeys();
  await Accounts.init();
  await Request.init();

  // 插件系统（Phase 6）：状态恢复 → 旧 SponsorBlock 开关迁移 → 注册内置插件
  // → 加载规则插件。任一步失败都不阻断启动，仅记录日志。
  try {
    await PluginManager.initialize();
    await SponsorBlockPlugin.migrateLegacyEnabledState();
    await PluginManager.instance.registerAll(builtinPlugins);
    await RulePluginManager.initialize();
  } catch (error, stackTrace) {
    AppLogger.e(
      'bootstrap',
      'plugin system init failed',
      error: error,
      stackTrace: stackTrace,
    );
  }

  // 从加密缓存恢复登录态，驱动 UI 首屏展示。
  AccountService().restore(Pref.userInfoCache);
  if (Accounts.main.isLogin &&
      (AccountService().userInfo == null ||
          AccountService().userInfo?.isLogin != true)) {
    unawaited(LoginUtils.onLoginMain());
  }

  // 预取 WBI 签名密钥（不阻塞启动）：首个 WBI 签名请求（playInfo /
  // videoUrl 等）不再额外串行等待一次 /x/web-interface/nav 往返，
  // 缩短视频打开首帧关键路径。失败静默（WbiSign 内部已兜底空密钥）。
  unawaited(Future<void>.sync(WbiSign.getWbiKeys));
}
