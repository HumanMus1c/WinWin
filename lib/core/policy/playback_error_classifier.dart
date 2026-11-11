// 播放加载错误分类（纯逻辑，无 IO）。
//
// 目的：自动重试只应作用于网络/超时/服务端 5xx 等瞬态错误；内容跳转、
// DRM、版权/地区限制、登录态失效等重试也不会成功，应直接给用户明确提示。

import 'package:dio/dio.dart';

/// 播放加载错误类别。
enum PlaybackLoadErrorKind {
  network,
  timeout,
  server,
  rateLimited,
  contentRestricted,
  drmProtected,
  loginRequired,
  cancelled,
  certificate,
  unknown,
}

/// 播放加载错误分类器。
abstract final class PlaybackErrorClassifier {
  static const List<String> _drmKeywords = ['DRM', '版权保护'];

  static const List<String> _nonRetryableKeywords = [
    '版权',
    '地区',
    '仅限',
    '专享',
    '大会员',
    '下架',
    '审核',
    '不存在',
    '已失效',
    '无法播放',
    '暂不支持',
  ];

  static const List<String> _loginKeywords = [
    '未登录',
    '请先登录',
    '登录后',
    '登录失效',
  ];

  static const List<String> _rawMessageKeywords = [
    'exception',
    'dioexception',
    'stack trace',
    'stacktrace',
    '#0 ',
  ];

  /// 判断异常是否属于可自动重试的瞬态错误。
  static bool isRetryable(Object error) {
    return switch (classify(error)) {
      PlaybackLoadErrorKind.network ||
      PlaybackLoadErrorKind.timeout ||
      PlaybackLoadErrorKind.server ||
      PlaybackLoadErrorKind.rateLimited ||
      PlaybackLoadErrorKind.unknown => true,
      _ => false,
    };
  }

  /// 判断服务端/接口文案是否属于可重试错误。
  ///
  /// 无法识别的文案默认按可重试处理，保持既有弱网退避行为。
  static bool isRetryableMessage(String? message) {
    return switch (classifyMessage(message)) {
      PlaybackLoadErrorKind.contentRestricted ||
      PlaybackLoadErrorKind.drmProtected ||
      PlaybackLoadErrorKind.loginRequired => false,
      _ => true,
    };
  }

  /// 提取可安全展示给用户的单行文案；原始异常/堆栈返回 null。
  static String? userMessage(String? message) {
    final text = message?.trim();
    if (text == null || text.isEmpty) return null;
    if (text.length > 80 || text.contains('\n') || text.contains('\r')) {
      return null;
    }
    final lower = text.toLowerCase();
    if (_rawMessageKeywords.any(lower.contains)) return null;
    return text;
  }

  /// 对异常对象分类。
  static PlaybackLoadErrorKind classify(Object error) {
    if (error is DioException) return _classifyDio(error);
    return _classifyText(error.toString());
  }

  /// 对接口文案分类。
  static PlaybackLoadErrorKind classifyMessage(String? message) {
    final text = userMessage(message);
    if (text == null) return PlaybackLoadErrorKind.unknown;
    if (_drmKeywords.any(text.contains)) {
      return PlaybackLoadErrorKind.drmProtected;
    }
    if (_loginKeywords.any(text.contains)) {
      return PlaybackLoadErrorKind.loginRequired;
    }
    if (_nonRetryableKeywords.any(text.contains)) {
      return PlaybackLoadErrorKind.contentRestricted;
    }
    return PlaybackLoadErrorKind.unknown;
  }

  static PlaybackLoadErrorKind _classifyDio(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return PlaybackLoadErrorKind.timeout;
      case DioExceptionType.connectionError:
        return PlaybackLoadErrorKind.network;
      case DioExceptionType.badCertificate:
        return PlaybackLoadErrorKind.certificate;
      case DioExceptionType.cancel:
        return PlaybackLoadErrorKind.cancelled;
      case DioExceptionType.badResponse:
        final status = error.response?.statusCode ?? 0;
        if (status == 429) return PlaybackLoadErrorKind.rateLimited;
        if (status >= 500) return PlaybackLoadErrorKind.server;
        if (status == 401 || status == 403) {
          return PlaybackLoadErrorKind.loginRequired;
        }
        if (status >= 400) return PlaybackLoadErrorKind.contentRestricted;
        return PlaybackLoadErrorKind.unknown;
      case DioExceptionType.unknown:
        final detail = error.error;
        if (detail != null) {
          final kind = _classifyText(detail.toString());
          if (kind != PlaybackLoadErrorKind.unknown) return kind;
        }
        return _classifyText(error.message ?? '');
    }
  }

  static PlaybackLoadErrorKind _classifyText(String text) {
    if (_drmKeywords.any(text.contains)) {
      return PlaybackLoadErrorKind.drmProtected;
    }
    if (_loginKeywords.any(text.contains)) {
      return PlaybackLoadErrorKind.loginRequired;
    }
    if (_nonRetryableKeywords.any(text.contains)) {
      return PlaybackLoadErrorKind.contentRestricted;
    }
    return PlaybackLoadErrorKind.unknown;
  }
}
