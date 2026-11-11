import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/core/policy/playback_error_classifier.dart';

DioException _dio(
  DioExceptionType type, {
  int? statusCode,
  Object? error,
}) {
  final options = RequestOptions(path: '/playurl');
  return DioException(
    requestOptions: options,
    type: type,
    error: error,
    response: statusCode == null
        ? null
        : Response<dynamic>(
            requestOptions: options,
            statusCode: statusCode,
          ),
  );
}

void main() {
  group('PlaybackErrorClassifier', () {
    test('网络超时/连接错误可重试', () {
      expect(
        PlaybackErrorClassifier.isRetryable(
          _dio(DioExceptionType.connectionTimeout),
        ),
        isTrue,
      );
      expect(
        PlaybackErrorClassifier.isRetryable(
          _dio(DioExceptionType.connectionError),
        ),
        isTrue,
      );
      expect(
        PlaybackErrorClassifier.isRetryable(
          _dio(DioExceptionType.receiveTimeout),
        ),
        isTrue,
      );
    });

    test('5xx 与 429 可重试，4xx 不重试', () {
      expect(
        PlaybackErrorClassifier.isRetryable(
          _dio(DioExceptionType.badResponse, statusCode: 500),
        ),
        isTrue,
      );
      expect(
        PlaybackErrorClassifier.isRetryable(
          _dio(DioExceptionType.badResponse, statusCode: 429),
        ),
        isTrue,
      );
      expect(
        PlaybackErrorClassifier.isRetryable(
          _dio(DioExceptionType.badResponse, statusCode: 404),
        ),
        isFalse,
      );
      expect(
        PlaybackErrorClassifier.isRetryable(
          _dio(DioExceptionType.badResponse, statusCode: 403),
        ),
        isFalse,
      );
    });

    test('取消与证书错误不重试', () {
      expect(
        PlaybackErrorClassifier.isRetryable(
          _dio(DioExceptionType.cancel),
        ),
        isFalse,
      );
      expect(
        PlaybackErrorClassifier.isRetryable(
          _dio(DioExceptionType.badCertificate),
        ),
        isFalse,
      );
    });

    test('DRM/版权/地区/登录限制文案不重试', () {
      const messages = [
        '该内容受 DRM 版权保护，当前版本暂不支持播放',
        '该视频因版权限制无法播放',
        '该内容仅限中国大陆地区播放',
        '请先登录后再播放',
      ];
      for (final message in messages) {
        expect(
          PlaybackErrorClassifier.isRetryableMessage(message),
          isFalse,
          reason: message,
        );
      }
    });

    test('无法识别的文案默认保持可重试', () {
      expect(
        PlaybackErrorClassifier.isRetryableMessage('请求过于频繁，请稍后重试'),
        isTrue,
      );
      expect(PlaybackErrorClassifier.isRetryableMessage(null), isTrue);
    });

    test('原始异常/堆栈不作为用户文案', () {
      expect(
        PlaybackErrorClassifier.userMessage(
          'DioException [unknown]: SocketException\n\n#0  main (file.dart:1)',
        ),
        isNull,
      );
      expect(PlaybackErrorClassifier.userMessage(null), isNull);
      expect(PlaybackErrorClassifier.userMessage('  '), isNull);
    });

    test('干净的服务端文案原样返回', () {
      const message = '该内容受 DRM 版权保护，当前版本暂不支持播放';
      expect(PlaybackErrorClassifier.userMessage(message), message);
      expect(
        PlaybackErrorClassifier.classifyMessage(message),
        PlaybackLoadErrorKind.drmProtected,
      );
    });

    test('未知 Dio 异常从底层错误提取 DRM 分类', () {
      final error = _dio(
        DioExceptionType.unknown,
        error: Exception('该内容受 DRM 版权保护'),
      );
      expect(
        PlaybackErrorClassifier.classify(error),
        PlaybackLoadErrorKind.drmProtected,
      );
      expect(PlaybackErrorClassifier.isRetryable(error), isFalse);
    });
  });
}
