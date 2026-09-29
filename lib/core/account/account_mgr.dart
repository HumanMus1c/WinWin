// Adapted from package:dio_cookie_manager and PiliPlus AccountManager.
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

import 'package:winwin/core/account/account.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/core/account/api_type.dart';
import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/http/api.dart';
import 'package:winwin/http/browser_ua.dart';
import 'package:winwin/http/constants.dart';
import 'package:winwin/models/common/account_type.dart';
import 'package:winwin/utils/app_sign.dart';

final _setCookieReg = RegExp('(?<=)(,)(?=[^;]+?=)');

class AccountManager extends Interceptor {
  AccountManager();

  /// TODO: make configurable in Phase 2 (sponsor block server).
  String blockServer = 'https://www.bsbsb.top';

  static String getCookies(List<Cookie> cookies) {
    // Sort cookies by path (longer path first).
    cookies.sort((a, b) {
      if (a.path == null && b.path == null) {
        return 0;
      } else if (a.path == null) {
        return -1;
      } else if (b.path == null) {
        return 1;
      } else {
        return b.path!.length.compareTo(a.path!.length);
      }
    });
    return cookies.map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final path = options.path;

    late final Account account =
        options.extra['account'] ?? _findAccount(path);

    if (account is NoAccount || _skipCookie(path)) return handler.next(options);

    if (!account.isLogin && path == Api.heartBeat) {
      return handler.reject(
        DioException.requestCancelled(requestOptions: options, reason: null),
        false,
      );
    }

    final isApp = path.startsWith(HttpString.appBaseUrl);

    if (isApp && options.responseType == ResponseType.bytes) {
      options.headers.addAll(account.grpcHeaders);
      return handler.next(options);
    }

    // app端不需要管理cookie
    if (isApp) {
      options.headers
        ..addAll(account.headers)
        ..['referer'] ??= HttpString.baseUrl;
      final dataPtr = (options.method == 'POST' && options.data is Map
          ? (options.data as Map).cast<String, dynamic>()
          : options.queryParameters);
      if (dataPtr.isNotEmpty) {
        if (account.accessKey != null && account.accessKey!.isNotEmpty) {
          dataPtr['access_key'] = account.accessKey!;
        }
        AppSign.appSign(dataPtr..remove('sign'));
      }
      return handler.next(options);
    } else {
      options.headers['user-agent'] ??= BrowserUa.pc;
      options.headers['referer'] ??= HttpString.baseUrl;
      // 移植自 BiliPai AppSessionCookieJar：除 loadForRequest 外，
      // 还从 LoginAccount.keyCookies 直接注入 SESSDATA/bili_jct/
      // DedeUserID 等关键 cookie，绕过 cookie_jar 的域名匹配。
      // 这解决了 TV QR 登录后 web nav 返回 isLogin=false 的问题。
      account.cookieJar
          .loadForRequest(options.uri)
          .then((jarCookies) {
            // 从 LoginAccount 直接获取关键 cookie。
            final keyCookies = account is LoginAccount
                ? account.keyCookies
                : const <Cookie>[];
            // 关键 cookie 优先：移除 jarCookies 中的同名 cookie。
            final keyNames = keyCookies.map((c) => c.name).toSet();
            final mergedCookies = [
              ...jarCookies.where((c) => !keyNames.contains(c.name)),
              ...keyCookies,
            ];

            final previousCookies =
                options.headers[HttpHeaders.cookieHeader] as String?;
            final newCookies = getCookies([
              ...?previousCookies
                  ?.split(';')
                  .where((e) => e.isNotEmpty)
                  .map(Cookie.fromSetCookieValue),
              ...mergedCookies,
            ]);
            options.headers[HttpHeaders.cookieHeader] =
                newCookies.isNotEmpty ? newCookies : '';
            handler.next(options);
          })
          .catchError((dynamic e, StackTrace s) {
            final err = DioException(
              requestOptions: options,
              error: e,
              stackTrace: s,
            );
            handler.reject(err, true);
          });
    }
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final options = response.requestOptions;
    final path = options.path;
    if (options.extra['account'] is NoAccount ||
        path.startsWith(HttpString.appBaseUrl) ||
        _skipCookie(path)) {
      return handler.next(response);
    } else {
      final future = _saveCookies(
        response,
      ).whenComplete(() => handler.next(response));
      assert(() {
        future.catchError(
          (Object e, StackTrace s) {
            throw DioException(
              requestOptions: response.requestOptions,
              error: e,
              stackTrace: s,
            );
          },
        );
        return true;
      }());
    }
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.requestOptions.responseType == ResponseType.stream) {
      return handler.next(err);
    }
    if (err.requestOptions.method != 'POST') {
      toast(err);
    }
    if (err.response != null &&
        !err.response!.requestOptions.path.startsWith(HttpString.appBaseUrl)) {
      _saveCookies(
        err.response!,
      ).whenComplete(() => handler.next(err)).catchError(
        (dynamic e, StackTrace s) {
          final error = DioException(
            requestOptions: err.response!.requestOptions,
            error: e,
            stackTrace: s,
          );
          handler.next(error);
        },
      );
    } else {
      handler.next(err);
    }
  }

  static void toast(DioException err) {
    const List<String> skipShow = [
      'heartbeat',
      'history/report',
      'roomEntryAction',
      'seg.so',
      'online/total',
      'github',
      'hdslb.com',
      'biliimg.com',
      'site/getCoin',
    ];
    String url = err.requestOptions.uri.toString();
    if (kDebugMode) debugPrint('ApiInterceptor: $url\n$err');
    if (skipShow.any((i) => url.contains(i)) ||
        (url.contains('skipSegments') && err.requestOptions.method == 'GET')) {
      // skip
    } else {
      dioError(err).then((res) {
        // 2026-09-29 起改用应用级 Material SnackBar：原 Get.snackbar 在纯
        // MaterialApp 架构下（无 GetX Overlay）既不显示，又会经
        // SnackbarController 抛出无法捕获的异步异常（15 条崩溃报告实证）。
        showAppSnackBar('请求错误：$res\n$url');
      });
    }
  }

  Future<void> _saveCookies(Response response) async {
    final Account account =
        response.requestOptions.extra['account'] ??
        _findAccount(response.requestOptions.path);
    final setCookies = response.headers[HttpHeaders.setCookieHeader];
    if (setCookies == null || setCookies.isEmpty) {
      return;
    }
    final List<Cookie> cookies = setCookies
        .map((str) => str.split(_setCookieReg))
        .expand((cookie) => cookie)
        .where((cookie) => cookie.isNotEmpty)
        .map(Cookie.fromSetCookieValue)
        .toList();
    final statusCode = response.statusCode ?? 0;
    final locations =
        response.headers[HttpHeaders.locationHeader] ?? const [];
    final isRedirectRequest = statusCode >= 300 && statusCode < 400;
    final originalUri = response.requestOptions.uri;
    final realUri = originalUri.resolveUri(response.realUri);
    await account.cookieJar.saveFromResponse(realUri, cookies);
    if (isRedirectRequest && locations.isNotEmpty) {
      final originalUri = response.realUri;
      await Future.wait(
        locations.map(
          (location) => account.cookieJar.saveFromResponse(
            // Resolves the location based on the current Uri.
            originalUri.resolve(location),
            cookies,
          ),
        ),
      );
    }
    await account.onChange();
  }

  bool _skipCookie(String path) {
    return path.startsWith(blockServer) ||
        path.contains('hdslb.com') ||
        path.contains('biliimg.com');
  }

  Account _findAccount(String path) {
    if (ApiType.loginApi.contains(path)) return AnonymousAccount();
    final account = Accounts.get(
      AccountType.values.firstWhere(
        (i) => ApiType.apiTypeSet[i]?.contains(path) == true,
        orElse: () => AccountType.main,
      ),
    );
    // WinWin 是单账号客户端，登录只绑定 main 槽位，video/heartbeat
    // 等槽位保持匿名，导致 playurl 等接口不带 SESSDATA、画质被限制在
    // 480P。槽位未绑定登录账号时回退到主账号（与 Accounts.history 的
    // 回退语义一致）。
    if (!account.isLogin && Accounts.main.isLogin) {
      return Accounts.main;
    }
    return account;
  }

  static Future<String> dioError(DioException error) async {
    switch (error.type) {
      case DioExceptionType.badCertificate:
        return '证书有误！';
      case DioExceptionType.badResponse:
        return '服务器异常，请稍后重试！';
      case DioExceptionType.cancel:
        return '请求已被取消，请重新请求';
      case DioExceptionType.connectionError:
        return '连接错误，请检查网络设置';
      case DioExceptionType.connectionTimeout:
        return '网络连接超时，请检查网络设置';
      case DioExceptionType.receiveTimeout:
        return '响应超时，请稍后重试！';
      case DioExceptionType.sendTimeout:
        return '发送请求超时，请检查网络设置';
      case DioExceptionType.transformTimeout:
        return '转换响应数据超时！';
      case DioExceptionType.unknown:
        return '网络异常 ${error.error}';
    }
  }
}
