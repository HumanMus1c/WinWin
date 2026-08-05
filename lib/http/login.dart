import 'dart:convert' show ascii;

import 'package:winwin/common/constants.dart';
import 'package:winwin/core/account/account.dart';
import 'package:winwin/core/account/login_utils.dart';
import 'package:winwin/http/api.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/utils/app_sign.dart';
import 'package:winwin/utils/utils.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

abstract final class LoginHttp {
  static final String deviceId = LoginUtils.genDeviceId();
  static String get buvid => LoginUtils.buvid;
  static final Map<String, String> headers = {
    'buvid': buvid,
    'env': 'prod',
    'app-key': 'android_hd',
    'user-agent': Constants.userAgent,
    'x-bili-trace-id': Constants.traceId,
    'x-bili-aurora-eid': '',
    'x-bili-aurora-zone': '',
    'bili-http-engine': 'cronet',
    'content-type': 'application/x-www-form-urlencoded; charset=utf-8',
  };

  // ---------- TV QR login ----------

  @pragma('vm:notify-debugger-on-exception')
  static Future<LoadingState<({String authCode, String url})>>
  getHDcode() async {
    final params = {
      // 'local_id': '0',
      'local_id': '0',
      'platform': 'android',
      'mobi_app': 'android_hd',
    };
    AppSign.appSign(params);
    final res = await Request().post(Api.getTVCode, queryParameters: params);

    if (res.data['code'] == 0) {
      try {
        final Map<String, dynamic> data = res.data['data'];
        return Success((authCode: data['auth_code'], url: data['url']));
      } catch (e, s) {
        return Error('$e\n\n$s');
      }
    } else {
      return Error(res.data['message']);
    }
  }

  static Future codePoll(String authCode) async {
    final params = {
      'auth_code': authCode,
      'local_id': '0',
    };
    AppSign.appSign(params);
    final res = await Request().post(Api.qrcodePoll, queryParameters: params);
    return {
      'status': res.data['code'] == 0,
      'code': res.data['code'],
      'data': res.data['data'],
      'msg': res.data['message'],
    };
  }

  // ---------- captcha ----------

  static Future queryCaptcha() async {
    final res = await Request().get(Api.getCaptcha);
    if (res.data['code'] == 0) {
      return {
        'status': true,
        'data': res.data['data'],
      };
    } else {
      return {'status': false, 'data': res.data['message']};
    }
  }

  // ---------- web key (RSA password encrypt) ----------

  static Future getWebKey() async {
    final res = await Request().get(Api.getWebKey);
    if (res.data['code'] == 0) {
      return {'status': true, 'data': res.data['data']};
    } else {
      return {'status': false, 'data': {}, 'msg': res.data['message']};
    }
  }

  // ---------- SMS code ----------

  static Future sendSmsCode({
    required Object cid,
    required String tel,
    String? geeChallenge,
    String? geeSeccode,
    String? geeValidate,
    String? recaptchaToken,
  }) async {
    int timestamp = DateTime.now().millisecondsSinceEpoch;
    final data = {
      'build': '2001100',
      'buvid': buvid,
      'c_locale': 'zh_CN',
      'channel': 'master',
      'cid': cid,
      'disable_rcmd': '0',
      'gee_challenge': ?geeChallenge,
      'gee_seccode': ?geeSeccode,
      'gee_validate': ?geeValidate,
      'local_id': buvid,
      'login_session_id': md5
          .convert(ascii.encode(buvid + timestamp.toString()))
          .toString(),
      'mobi_app': 'android_hd',
      'platform': 'android',
      'recaptcha_token': ?recaptchaToken,
      's_locale': 'zh_CN',
      'statistics': Constants.statistics,
      'tel': tel,
      'ts': (timestamp ~/ 1000).toString(),
    };
    AppSign.appSign(data);

    final res = await Request().post(
      Api.appSmsCode,
      data: data,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: headers,
      ),
    );

    if (res.data['code'] == 0 && res.data['data']['recaptcha_url'] == "") {
      return {'status': true, 'data': res.data['data']};
    } else {
      return {
        'status': false,
        'code': res.data['code'],
        'msg': res.data['message'],
        'data': res.data['data'],
      };
    }
  }

  // ---------- password login ----------
  // TODO: Phase 2 — add `encrypt` package and implement RSA password encryption.
  // For now the password is sent un-encrypted which will fail server-side,
  // but the call compiles and the stub is clearly marked.

  static Future loginByPwd({
    required String username,
    required String password,
    required String key,
    required String salt,
    String? geeChallenge,
    String? geeSeccode,
    String? geeValidate,
    String? recaptchaToken,
  }) async {
    // TODO: encrypt password with RSA using [key] (PubKey) + [salt] prefix.
    // final publicKey = RSAKeyParser().parse(key);
    // final passwordEncrypted =
    //     Encrypter(RSA(publicKey: publicKey)).encrypt(salt + password).base64;
    final passwordEncrypted = salt + password; // STUB — replace in Phase 2

    Map<String, String> data = {
      'bili_local_id': deviceId,
      'build': '2001100',
      'buvid': buvid,
      'c_locale': 'zh_CN',
      'channel': 'master',
      'device': 'phone',
      'device_id': deviceId,
      'device_name': 'vivo',
      'device_platform': 'Android14vivo',
      'disable_rcmd': '0',
      'dt': Uri.encodeComponent(
        // STUB: should be RSA-encrypted random string.
        Utils.generateRandomString(16),
      ),
      'from_pv': 'main.homepage.avatar-nologin.all.click',
      'from_url': Uri.encodeComponent('bilibili://pegasus/promo'),
      'gee_challenge': ?geeChallenge,
      'gee_seccode': ?geeSeccode,
      'gee_validate': ?geeValidate,
      'local_id': buvid,
      'mobi_app': 'android_hd',
      'password': passwordEncrypted,
      'permission': 'ALL',
      'platform': 'android',
      'recaptcha_token': ?recaptchaToken,
      's_locale': 'zh_CN',
      'statistics': Constants.statistics,
      'username': username,
    };
    AppSign.appSign(data);
    final res = await Request().post(
      Api.loginByPwdApi,
      data: data,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: headers,
      ),
    );

    if (res.data['code'] == 0) {
      return {
        'status': true,
        'data': res.data['data'],
        'msg': res.data['message'],
      };
    } else {
      return {
        'status': false,
        'code': res.data['code'],
        'msg': res.data['message'],
        'data': res.data['data'],
      };
    }
  }

  // ---------- SMS login ----------

  static Future loginBySms({
    required String captchaKey,
    required String tel,
    required String code,
    required Object cid,
    required String key,
  }) async {
    // TODO: encrypt `dt` with RSA using [key] (PubKey).
    // final publicKey = RSAKeyParser().parse(key);
    // final dt = Encrypter(RSA(publicKey: publicKey))
    //     .encrypt(Utils.generateRandomString(16)).base64;
    final dt = Utils.generateRandomString(16); // STUB

    Map<String, Object> data = {
      'bili_local_id': deviceId,
      'build': '2001100',
      'buvid': buvid,
      'c_locale': 'zh_CN',
      'captcha_key': captchaKey,
      'channel': 'master',
      'cid': cid,
      'code': code,
      'device': 'phone',
      'device_id': deviceId,
      'device_name': 'vivo',
      'device_platform': 'Android14vivo',
      'disable_rcmd': '0',
      'dt': Uri.encodeComponent(dt),
      'from_pv': 'main.my-information.my-login.0.click',
      'from_url': Uri.encodeComponent('bilibili://user_center/mine'),
      'local_id': buvid,
      'mobi_app': 'android_hd',
      'platform': 'android',
      's_locale': 'zh_CN',
      'statistics': Constants.statistics,
      'tel': tel,
    };
    AppSign.appSign(data);
    final res = await Request().post(
      Api.logInByAppSms,
      data: data,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: headers,
      ),
    );

    if (res.data['code'] == 0) {
      return {'status': true, 'data': res.data['data']};
    } else {
      return {
        'status': false,
        'code': res.data['code'],
        'msg': res.data['message'],
        'data': res.data['data'],
      };
    }
  }

  // ---------- safe-center (password risk-control) ----------

  static Future safeCenterGetInfo({
    required String tmpCode,
  }) async {
    final res = await Request().get(
      Api.safeCenterGetInfo,
      queryParameters: {
        'tmp_code': tmpCode,
      },
    );
    if (res.data['code'] == 0) {
      return {'status': true, 'data': res.data['data']};
    } else {
      return {
        'status': false,
        'code': res.data['code'],
        'msg': res.data['message'],
        'data': res.data['data'],
      };
    }
  }

  static Future preCapture() async {
    final res = await Request().post(Api.preCapture);

    if (res.data['code'] == 0) {
      return {'status': true, 'data': res.data['data']};
    } else {
      return {
        'status': false,
        'code': res.data['code'],
        'msg': res.data['message'],
        'data': res.data['data'],
      };
    }
  }

  static Future safeCenterSmsCode({
    String? smsType,
    required String tmpCode,
    String? geeChallenge,
    String? geeSeccode,
    String? geeValidate,
    String? recaptchaToken,
    required String refererUrl,
  }) async {
    Map<String, String> data = {
      'disable_rcmd': '0',
      'sms_type': smsType ?? 'loginTelCheck',
      'tmp_code': tmpCode,
      'gee_challenge': ?geeChallenge,
      'gee_seccode': ?geeSeccode,
      'gee_validate': ?geeValidate,
      'recaptcha_token': ?recaptchaToken,
    };
    AppSign.appSign(data);
    final res = await Request().post(
      Api.safeCenterSmsCode,
      data: data,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {
          "Referer": refererUrl,
        },
      ),
    );

    if (res.data['code'] == 0) {
      return {'status': true, 'data': res.data['data']};
    } else {
      return {
        'status': false,
        'code': res.data['code'],
        'msg': res.data['message'],
        'data': res.data['data'],
      };
    }
  }

  static Future safeCenterSmsVerify({
    String? type,
    required String code,
    required String tmpCode,
    required String requestId,
    required String source,
    required String captchaKey,
    required String refererUrl,
  }) async {
    Map<String, String> data = {
      'type': type ?? 'loginTelCheck',
      'code': code,
      'tmp_code': tmpCode,
      'request_id': requestId,
      'source': source,
      'captcha_key': captchaKey,
    };
    AppSign.appSign(data);
    final res = await Request().post(
      Api.safeCenterSmsVerify,
      data: data,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {
          "Referer": refererUrl,
        },
      ),
    );

    if (res.data['code'] == 0) {
      return {'status': true, 'data': res.data['data']};
    } else {
      return {
        'status': false,
        'code': res.data['code'],
        'msg': res.data['message'],
        'data': res.data['data'],
      };
    }
  }

  static Future oauth2AccessToken({
    required String code,
  }) async {
    final Map<String, String> data = {
      'build': '2001100',
      'buvid': buvid,
      'code': code,
      'disable_rcmd': '0',
      'grant_type': 'authorization_code',
      'local_id': buvid,
      'mobi_app': 'android_hd',
      'platform': 'android',
    };
    AppSign.appSign(data);
    final res = await Request().post(
      Api.oauth2AccessToken,
      data: data,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: headers,
      ),
    );

    if (res.data['code'] == 0) {
      return {'status': true, 'data': res.data['data']};
    } else {
      return {
        'status': false,
        'code': res.data['code'],
        'msg': res.data['message'],
        'data': res.data['data'],
      };
    }
  }

  static Future<Map> logout(Account account) async {
    final res = await Request().post(
      Api.logout,
      data: {'biliCSRF': account.csrf},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        extra: {'account': account},
      ),
    );
    return {'status': res.data['code'] == 0, 'msg': res.data['message']};
  }
}
