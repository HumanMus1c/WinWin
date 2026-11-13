import 'package:dio/dio.dart';

/// Dio 异常 → 面向用户的弱网/服务端提示。
///
/// 原则：
/// - 客户端超时/断网统一提示「网络较慢 / 检查网络」，不出现服务器或原始异常字样；
/// - 仅 HTTP 5xx 才提示「服务器暂时不可用」；
/// - 非 Dio 异常不向用户暴露 `Exception` / 堆栈等实现细节。
String dioErrorMessage(Object e) {
  if (e is! DioException) return '加载失败，请稍后重试';
  return switch (e.type) {
    DioExceptionType.badCertificate => '安全证书校验失败，请检查网络环境',
    DioExceptionType.badResponse => switch (e.response?.statusCode ?? 0) {
      >= 500 => '服务器暂时不可用，请稍后重试',
      401 || 403 => '登录状态失效或没有访问权限',
      404 => '请求的内容不存在',
      _ => '请求失败，请稍后重试',
    },
    DioExceptionType.cancel => '请求已取消',
    DioExceptionType.connectionError => '网络连接失败，请检查网络或更换网络环境',
    DioExceptionType.connectionTimeout => '网络较慢，请检查网络或更换网络环境',
    DioExceptionType.receiveTimeout => '网络较慢，请检查网络或更换网络环境',
    DioExceptionType.sendTimeout => '网络较慢，请检查网络或更换网络环境',
    DioExceptionType.transformTimeout => '网络较慢，请检查网络或更换网络环境',
    DioExceptionType.unknown => '网络异常，请检查网络或更换网络环境',
  };
}
