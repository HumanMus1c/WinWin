import 'dart:async';

import 'package:dio/dio.dart';

import 'package:winwin/core/account/account_mgr.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/core/account/login_utils.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/http/constants.dart';
import 'package:winwin/http/retry_interceptor.dart';

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
    client.interceptors.add(accountManager);
    client.interceptors.add(
      RetryInterceptor(client, Pref.retryCount, Pref.retryDelay),
    );
    dio = client;

    await Accounts.refresh();
    LoginUtils.setWebCookie();
  }

  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) {
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
  }) {
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
