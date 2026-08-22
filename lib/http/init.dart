import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:winwin/core/account/account.dart';
import 'package:winwin/core/account/account_mgr.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/core/account/login_utils.dart';
import 'package:winwin/core/log/api_blackbox.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/http/api.dart';
import 'package:winwin/http/constants.dart';
import 'package:winwin/http/retry_interceptor.dart';
import 'package:winwin/utils/utils.dart';

/// Minimal Dio wrapper modeled after PiliPlus's `Request`.
/// Phase 2 will add HTTP/2 support, brotli/gzip decoding, etc.
class Request {
  static final Request _instance = Request._internal();
  factory Request() => _instance;
  Request._internal();

  static late final AccountManager accountManager;
  static late final Dio dio;

  /// Call once at startup (after `GStorage.init()` and `Accounts.init()`).
  static Future<void> init() async {
    accountManager = AccountManager();
    // Build in a local first: reading the late-final `dio` inside a cascade
    // (RetryInterceptor needs the client) would throw a
    // LateInitializationError before the assignment completes.
    final client = Dio(
      BaseOptions(
        baseUrl: HttpString.apiBaseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        validateStatus: (_) => true,
      ),
    );
    client.interceptors.add(_JsonDecodeInterceptor());
    client.interceptors.add(accountManager);
    client.interceptors.add(ApiBlackboxInterceptor());
    client.interceptors.add(
      RetryInterceptor(client, Pref.retryCount, Pref.retryDelay),
    );
    dio = client;

    await Accounts.refresh();
    LoginUtils.setWebCookie();
  }

  /// 激活 buvid3 cookie（移植自 PiliPlus Request.buvidActive）。
  ///
  /// TV QR 登录返回的 cookie 中 buvid3 是客户端生成的，需要通过
  /// `/x/internal/gaia-gateway/ExClimbWuzhi` 接口激活后才能被 web API
  /// （如 `/x/web-interface/nav`）接受。未激活的 buvid3 会导致 web nav
  /// 返回 isLogin=false，这是"登录成功但数据未同步"的根本原因。
  static Future<void> buvidActive(Account account) async {
    if (account.activated) return;
    account.activated = true;
    try {
      final String randPngEnd = base64.encode([
        ...Iterable<int>.generate(32, (_) => Utils.random.nextInt(256)),
        0, 0, 0, 0, 73, 69, 78, 68,
        ...Iterable<int>.generate(4, (_) => Utils.random.nextInt(256)),
      ]);

      final jsonData = json.encode({
        '3064': 1,
        '39c8': '333.1387.fp.risk',
        '3c43': {
          'adca': 'Linux',
          'bfe9': randPngEnd.substring(randPngEnd.length - 50),
        },
      });

      await Request().post(
        Api.activateBuvidApi,
        data: {'payload': jsonData},
        options: Options(
          extra: {'account': account},
          contentType: Headers.jsonContentType,
        ),
      );
    } catch (_) {}
  }

  static void _ensureJsonDecoded(Response res) {
    final data = res.data;
    if (data is String) {
      final str = data.trim();
      if ((str.startsWith('{') && str.endsWith('}')) ||
          (str.startsWith('[') && str.endsWith(']'))) {
        try {
          res.data = jsonDecode(str);
        } catch (_) {}
      }
    }
  }

  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    return dio.get<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
    );
  }

  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    return dio.post<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
  }
}

class _JsonDecodeInterceptor extends Interceptor {
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    Request._ensureJsonDecoded(response);
    handler.next(response);
  }
}
