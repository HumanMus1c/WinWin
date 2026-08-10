import 'dart:async' show FutureOr;

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:winwin/core/account/account.dart';
import 'package:winwin/core/account/account_service.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/user.dart';
import 'package:winwin/models/user/user_info.dart';
import 'package:winwin/utils/utils.dart';
import 'package:crypto/crypto.dart' show Digest;

abstract final class LoginUtils {
  /// No-op stub: in PiliPlus this pushed cookies into the system WebView.
  /// WinWin does not embed a WebView in Phase 1.
  static FutureOr<void> setWebCookie([Account? account]) async {
    debugPrint('setWebCookie: skipped (no WebView in Phase 1)');
  }

  /// 主账号登录后回调：拉取用户信息 → 加密持久化 → 广播登录态。
  ///
  /// 拉取策略（三级回退）：
  ///   1. web nav（`/x/web-interface/nav`，cookie 鉴权，含 vip 信息）
  ///   2. app 端（`/x/v2/account/myinfo`，access_token 鉴权）
  ///   3. 最小模型（仅 mid + isLogin=true）
  ///
  /// **不会删除账号**——即使所有 API 都失败，也用最小模型设置登录态，
  /// 保证用户看到登录成功。账号删除仅在 [onLogoutMain] 中执行。
  static Future<bool> onLoginMain({int? fallbackMid}) async {
    // 自动从 Accounts.main 获取 fallbackMid。
    fallbackMid ??= Accounts.main.mid > 0 ? Accounts.main.mid : null;

    // 第一步：web nav（cookie 鉴权）。
    final res = await UserHttp.userInfo();
    if (res case Success(:final response)) {
      if (response.isLogin == true) {
        Pref.userInfoCache = response;
        AccountService().onLogin(response);
        debugPrint('onLoginMain: web nav success, mid=${response.mid}');
        return true;
      }
      debugPrint('onLoginMain: web nav isLogin=false');
    } else if (res case Error(:final errMsg)) {
      debugPrint('onLoginMain: web nav error: $errMsg');
    }

    // 第二步：app 端接口（access_token 鉴权）。
    final appRes = await UserHttp.userInfoApp();
    if (appRes case Success(:final response)) {
      if (response.isLogin == true) {
        Pref.userInfoCache = response;
        AccountService().onLogin(response);
        debugPrint('onLoginMain: app endpoint success, mid=${response.mid}');
        return true;
      }
    } else if (appRes case Error(:final errMsg)) {
      debugPrint('onLoginMain: app endpoint error: $errMsg');
    }

    // 第三步：最小模型兜底——绝不删除账号。
    if (fallbackMid != null && fallbackMid > 0) {
      final minimal = UserInfoModel(isLogin: true, mid: fallbackMid);
      AccountService().onLogin(minimal);
      debugPrint('onLoginMain: using minimal model, mid=$fallbackMid');
      return true;
    }

    debugPrint('onLoginMain: all methods failed, no fallbackMid');
    return false;
  }

  /// 主账号登出回调：清理持久化账号 + 清空缓存 + 广播登出态。
  static Future<void> onLogoutMain() async {
    final account = Accounts.main;
    if (account.isLogin) {
      await Accounts.deleteAll({account});
    }
    Pref.userInfoCache = null;
    AccountService().onLogout();
  }

  static String generateBuvid() {
    final md5Str = Digest(
      List.generate(16, (_) => Utils.random.nextInt(256)),
    ).toString();
    return 'XY${md5Str[2]}${md5Str[12]}${md5Str[22]}$md5Str';
  }

  static String get buvid => Pref.buvid;

  static String genDeviceId() {
    // https://github.com/bilive/bilive_client/blob/2873de0532c54832f5464a4c57325ad9af8b8698/bilive/lib/app_client.ts#L62
    final time = DateTime.now();

    final List<int> bytes = [
      ...Iterable.generate(16, (_) => Utils.random.nextInt(256)),
      _dec2bcd(time.year ~/ 100),
      _dec2bcd(time.year % 100),
      _dec2bcd(time.month),
      _dec2bcd(time.day),
      _dec2bcd(time.hour),
      _dec2bcd(time.minute),
      _dec2bcd(time.second),
      ...Iterable.generate(8, (_) => Utils.random.nextInt(256)),
    ];
    final check = (bytes.sum & 0xFF).toRadixString(16).padLeft(2, '0');

    return Digest(bytes).toString() + check;
  }

  static int _dec2bcd(int dec) {
    assert(0 <= dec && dec < 100);
    return ((dec ~/ 10) << 4) | (dec % 10);
  }
}

extension _IntSum on List<int> {
  int get sum => fold(0, (a, b) => a + b);
}
