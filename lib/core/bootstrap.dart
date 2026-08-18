import 'package:winwin/core/account/account_service.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/core/log/startup_blackbox.dart';
import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/http/init.dart';

/// Startup bootstrap shared by `main()` and lazily-created controllers.
///
/// Must NOT be awaited before `runApp()`: the Windows runner only shows the
/// window after Flutter renders its first frame, so blocking `main()` on
/// storage/network init would leave the window hidden forever.
Future<void>? _bootstrap;

Future<void> ensureBootstrap() => _bootstrap ??= _run();

Future<void> _run() async {
  // 黑箱：bootstrap 各阶段耗时（白屏时定位是哪一步挂起）。
  final sw = Stopwatch()..start();
  StartupBlackbox.log('bootstrap', 'GStorage.init start');
  await GStorage.init();
  StartupBlackbox.log('bootstrap', 'GStorage.init done (${sw.elapsedMilliseconds}ms)');

  StartupBlackbox.log('bootstrap', 'Accounts.init start');
  await Accounts.init();
  StartupBlackbox.log('bootstrap', 'Accounts.init done (${sw.elapsedMilliseconds}ms)');

  StartupBlackbox.log('bootstrap', 'Request.init start');
  await Request.init();
  StartupBlackbox.log('bootstrap', 'Request.init done (${sw.elapsedMilliseconds}ms)');

  // 从加密缓存恢复登录态，驱动 UI 首屏展示。
  StartupBlackbox.log('bootstrap', 'account restore start');
  AccountService().restore(Pref.userInfoCache);
  StartupBlackbox.log('bootstrap', 'account restore done (${sw.elapsedMilliseconds}ms)');
}
