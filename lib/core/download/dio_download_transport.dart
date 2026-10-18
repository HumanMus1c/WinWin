// Phase 5 下载系统 · 批次2：基于 dio 的下载传输实现。
//
// 与 `Request()`（JSON API 客户端）刻意分离：下载需要直连 CDN、流式响应、
// 自定 Range 头、不套 JSON 解码与账户拦截器，因此独立持有 Dio 实例。

import 'dart:async';

import 'package:dio/dio.dart';

import 'package:winwin/core/download/download_policy.dart';
import 'package:winwin/core/download/download_transport.dart';

/// 基于 dio 的默认下载传输实现。
class DioDownloadTransport implements DownloadTransport {
  DioDownloadTransport({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                // 下载直连 CDN，无 baseUrl 拼接；
                // 超时较 API 宽松（大文件流式接收）。
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 30),
                sendTimeout: const Duration(seconds: 15),
                // 非 2xx 自行判定，交由调用方决策。
                validateStatus: (_) => true,
              ),
            );

  final Dio _dio;

  @override
  Future<DownloadRangeProbe> probe({
    required Uri url,
    required Map<String, String> headers,
  }) async {
    final response = await _dio.getUri<ResponseBody>(
      url,
      options: Options(
        headers: <String, String>{
          ...headers,
          // 探测是否支持 Range：请求首字节。
          'Range': 'bytes=0-0',
        },
        responseType: ResponseType.stream,
      ),
    );

    // 立即取消正文流，只取响应头（避免服务器忽略 Range 时拉全量）。
    final subscription = response.data?.stream.listen(
      (_) {},
      onError: (Object _) {},
    );
    await subscription?.cancel();

    final headerValues = response.headers;
    final contentRange = headerValues.value('content-range');
    final parsed = DownloadRangePolicy.parseContentRange(contentRange);
    if (parsed != null) {
      return parsed;
    }

    final contentLength = int.tryParse(
      headerValues.value('content-length') ?? '',
    );
    final acceptRanges =
        (headerValues.value('accept-ranges') ?? '').toLowerCase();
    return DownloadRangeProbe(
      totalBytes: contentLength != null && contentLength > 0
          ? contentLength
          : 0,
      supportsRanges: acceptRanges.contains('bytes'),
    );
  }

  @override
  Future<void> fetchRange({
    required Uri url,
    required Map<String, String> headers,
    int? startBytes,
    int? endBytesInclusive,
    required Future<void> Function(List<int> data, int absoluteOffset) onChunk,
    bool Function()? isCancelled,
  }) async {
    final requestHeaders = <String, String>{...headers};
    if (startBytes != null) {
      final end = endBytesInclusive == null ? '' : '$endBytesInclusive';
      requestHeaders['Range'] = 'bytes=$startBytes-$end';
    }

    final response = await _dio.getUri<ResponseBody>(
      url,
      options: Options(
        headers: requestHeaders,
        responseType: ResponseType.stream,
      ),
    );

    final status = response.statusCode ?? 0;
    if (status != 200 && status != 206) {
      throw HttpException(
        '下载请求失败：HTTP $status',
      );
    }

    final body = response.data;
    if (body == null) {
      throw HttpException('下载响应无正文');
    }

    var offset = startBytes ?? 0;
    await for (final chunk in body.stream) {
      if (isCancelled?.call() ?? false) {
        throw const DownloadCancelledException();
      }
      if (chunk.isEmpty) continue;
      await onChunk(chunk, offset);
      offset += chunk.length;
    }
  }

  @override
  void close() => _dio.close(force: true);
}

/// `dart:io` 的 `HttpException` 等价物（此处仅作错误语义标记，避免额外 import）。
class HttpException implements Exception {
  const HttpException(this.message);

  final String message;

  @override
  String toString() => 'HttpException: $message';
}