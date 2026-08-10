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

  /// 主账号登录后回调：拉取用户信息（含会员权限）→ 加密持久化 → 广播。
  ///
  /// [fallbackMid]：由调用方提供的 mid（来自 QR/密码/短信登录响应）。
  ///
  /// 拉取策略：
  ///   1. 优先尝试 web nav 接口（`/x/web-interface/nav`）—— 含完整 vip 信息。
  ///   2. web nav 失败时回退到 app 端接口（`/x/v2/account/myinfo`）——
  ///      使用 access_token 鉴权，TV QR 登录的 cookie 可能不被 web 接口接受，
  ///      但 access_token 始终可用。
  ///   3. 两者都失败时使用 fallbackMid 构造最小 UserInfoModel。
  ///
  /// 返回 true 表示登录态已成功设置（完整或最小），false 表示完全失败。
  static Future<bool> onLoginMain({int? fallbackMid}) async {
    // 第一步：尝试 web nav 接口。
    final res = await UserHttp.userInfo();
    if (res case Success(:final response)) {
      if (response.isLogin == true) {
        Pref.userInfoCache = response;
        AccountService().onLogin(response);
        debugPrint('onLoginMain: web nav success, mid=${response.mid}');
        return true;
      }
      debugPrint('onLoginMain: web nav isLogin=false, trying app endpoint');
    } else if (res case Error(:final errMsg)) {
      debugPrint('onLoginMain: web nav error: $errMsg, trying app endpoint');
    }

    // 第二步：web nav 失败，回退到 app 端接口。
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

    // 第三步：两者都失败，使用 fallbackMid 设置最小登录态。
    if (fallbackMid != null && fallbackMid > 0) {
      final minimal = UserInfoModel(isLogin: true, mid: fallbackMid);
      AccountService().onLogin(minimal);
      debugPrint('onLoginMain: using minimal model with mid=$fallbackMid');
      return true;
    }

    // 没有 fallbackMid 时（如启动时 cookie 过期检查），且 web nav 返回
    // "账号未登录"，删除账号。
    if (res case Error(:final errMsg)) {
      if (errMsg == '账号未登录') {
        final account = Accounts.main;
        if (account.isLogin) {
          await Accounts.deleteAll({account});
        }
      }
    }
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
