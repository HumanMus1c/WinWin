import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/http/init.dart';

/// Startup bootstrap shared by `main()` and lazily-created controllers.
///
/// Must NOT be awaited before `runApp()`: the Windows runner only shows the
/// window after Flutter renders its first frame, so blocking `main()` on
/// storage/network init would leave the window hidden forever.
Future<void>? _bootstrap;

Future<void> ensureBootstrap() => _bootstrap ??= _run();

Future<void> _run() async {
  await GStorage.init();
  await Accounts.init();
  await Request.init();
}
