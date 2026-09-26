import 'package:dio/dio.dart';

/// Dio 异常 → 友好中文文案（移植自 PiliPlus 的 `getErrorMessage`，见复盘第十轮）。
///
/// 背景：`CommonListController` 此前直接 `Error(e.toString())`，弱网首屏失败时页面会
/// 原样显示 `DioException [receive timeout]: The request took longer than 0:00:30...`。
/// 此函数把网络异常统一映射为可读文案，供各页面/控制器复用。
String dioErrorMessage(Object e) {
  if (e is! DioException) return e.toString();
  return switch (e.type) {
    DioExceptionType.badCertificate => '证书有误！',
    DioExceptionType.badResponse => '服务器异常，请稍后重试！',
    DioExceptionType.cancel => '请求已被取消，请重新请求',
    DioExceptionType.connectionError => '连接错误，请检查网络设置',
    DioExceptionType.connectionTimeout => '网络连接超时，请检查网络设置',
    DioExceptionType.receiveTimeout => '响应超时，请稍后重试！',
    DioExceptionType.sendTimeout => '发送请求超时，请检查网络设置',
    DioExceptionType.transformTimeout => '转换响应数据超时！',
    DioExceptionType.unknown => '网络异常，请检查网络设置',
  };
}
