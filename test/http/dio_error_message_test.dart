import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/http/dio_error_message.dart';

DioException _dio(DioExceptionType type, {int? statusCode}) {
  final options = RequestOptions(path: '/x');
  return DioException(
    requestOptions: options,
    type: type,
    response: statusCode == null
        ? null
        : Response<dynamic>(requestOptions: options, statusCode: statusCode),
  );
}

void main() {
  group('dioErrorMessage', () {
    test('弱网超时统一提示网络较慢', () {
      const expected = '网络较慢，请检查网络或更换网络环境';
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.transformTimeout,
      ]) {
        expect(dioErrorMessage(_dio(type)), expected, reason: '$type');
      }
    });

    test('连接中断提示检查网络', () {
      expect(
        dioErrorMessage(_dio(DioExceptionType.connectionError)),
        '网络连接失败，请检查网络或更换网络环境',
      );
    });

    test('HTTP 5xx 才提示服务器暂时不可用', () {
      expect(
        dioErrorMessage(
          _dio(DioExceptionType.badResponse, statusCode: 502),
        ),
        '服务器暂时不可用，请稍后重试',
      );
      expect(
        dioErrorMessage(
          _dio(DioExceptionType.badResponse, statusCode: 404),
        ),
        '请求的内容不存在',
      );
      expect(
        dioErrorMessage(
          _dio(DioExceptionType.badResponse, statusCode: 403),
        ),
        '登录状态失效或没有访问权限',
      );
    });

    test('取消不提示网络问题', () {
      expect(dioErrorMessage(_dio(DioExceptionType.cancel)), '请求已取消');
    });

    test('证书错误提示检查网络环境', () {
      expect(
        dioErrorMessage(_dio(DioExceptionType.badCertificate)),
        '安全证书校验失败，请检查网络环境',
      );
    });

    test('非 Dio 异常不暴露原始异常信息', () {
      final message = dioErrorMessage(
        Exception('SocketException: Connection failed'),
      );
      expect(message, '加载失败，请稍后重试');
      expect(message.contains('Exception'), isFalse);
    });
  });
}
