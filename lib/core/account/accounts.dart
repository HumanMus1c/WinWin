import 'package:hive_ce/hive.dart';

import 'package:winwin/core/account/account.dart';
import 'package:winwin/core/account/login_utils.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/models/common/account_type.dart';

abstract final class Accounts {
  static late final Box<LoginAccount> account;

  /// One slot per [AccountType]; initially all anonymous.
  static final List<Account> accountMode = List.filled(
    AccountType.values.length,
    AnonymousAccount(),
  );

  static bool get mainEqVideo => main == video;
  static Account get main => accountMode[AccountType.main.index];
  static Account get video => accountMode[AccountType.video.index];
  static Account get heartbeat => accountMode[AccountType.heartbeat.index];
  static Account get history {
    final heartbeat = Accounts.heartbeat;
    if (heartbeat is AnonymousAccount) {
      return Accounts.main;
    }
    return heartbeat;
  }

  static Future<void> init() async {
    account = await Hive.openBox<LoginAccount>(
      'account',
      compactionStrategy: (int entries, int deletedEntries) {
        return deletedEntries > 2;
      },
    );
  }

  static Future<void> refresh() {
    for (final a in account.values) {
      for (final t in a.type) {
        accountMode[t.index] = a;
      }
    }
    return Future.wait(
      (accountMode.toSet()..removeWhere((i) => i.activated)).map(
        Request.buvidActive,
      ),
    );
  }

  static Future<void> clear() async {
    await account.clear();
    for (int i = 0; i < AccountType.values.length; i++) {
      accountMode[i] = AnonymousAccount();
    }
    await AnonymousAccount().delete();
  }

  static Future<void> deleteAll(Set<Account> accounts) async {
    for (int i = 0; i < AccountType.values.length; i++) {
      if (accounts.contains(accountMode[i])) {
        accountMode[i] = AnonymousAccount();
      }
    }
    await Future.wait(accounts.map((i) => i.delete()));
  }

  static Future<void> set(AccountType key, Account account) async {
    final oldAccount = accountMode[key.index]..type.remove(key);
    accountMode[key.index] = account..type.add(key);
    await Future.wait([?account.onChange(), ?oldAccount.onChange()]);
    // 移植自 PiliPlus：设置账号时先激活 buvid3，再触发登录/登出回调。
    // buvid 激活是 web API（如 /x/web-interface/nav）正常工作的前提。
    if (!account.activated) await Request.buvidActive(account);
    switch (key) {
      case AccountType.main:
        await (account.isLogin
            ? LoginUtils.onLoginMain()
            : LoginUtils.onLogoutMain());
        break;
      default:
        break;
    }
  }

  @pragma('vm:prefer-inline')
  static Account get(AccountType key) {
    return accountMode[key.index];
  }
}
