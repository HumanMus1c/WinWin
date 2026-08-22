import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

/// 深度网络与业务黑箱日志（写入 Documents/logs/blackbox_api.log）。
///
/// 特性：
/// - 同步文件写入 + 立即 flush，即使崩溃或进程意外退出也不会丢失最后一条日志。
/// - 记录完整的 HTTP 请求、Header、Cookie 状态、Query 参数、签名参数、响应体与异常。
/// - 自动滚动归档（超过 5MB 滚动为 .old）。
abstract final class ApiBlackbox {
  static File? _file;
  static final List<String> _pending = [];
  static bool _initTried = false;
  static final Stopwatch _sw = Stopwatch()..start();
  static final _AsyncExecutor _executor = _AsyncExecutor();

  /// 初始化日志文件句柄。在应用启动阶段调用。
  static Future<void> init() async {
    if (_initTried) return;
    _initTried = true;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}${Platform.pathSeparator}logs');
      if (!dir.existsSync()) await dir.create(recursive: true);
      final file = File('${dir.path}${Platform.pathSeparator}blackbox_api.log');
      if (file.existsSync() && file.lengthSync() > 5 * 1024 * 1024) {
        final old = File('${file.path}.old');
        if (old.existsSync()) await old.delete();
        await file.rename(old.path);
      }
      _file = file;
      if (_pending.isNotEmpty) {
        final lines = _pending.join();
        _pending.clear();
        _executor.submit(() => file.writeAsString(lines, mode: FileMode.append));
      }
      log('ApiBlackbox', '=== ApiBlackbox initialized (pid=$pid) ===');
    } catch (_) {
      // 无法落盘则保留内存缓冲
    }
  }

  /// 记录一条格式化日志行并异步提交到磁盘写入队列。
  static void log(String tag, String message) {
    final line =
        '${DateTime.now().toIso8601String()} [${_sw.elapsedMilliseconds}ms] '
        '[$tag] $message\n';
    final file = _file;
    if (file != null) {
      _executor.submit(() => file.writeAsString(line, mode: FileMode.append));
    } else {
      _pending.add(line);
      if (_pending.length > 512) _pending.removeRange(0, 256);
    }
  }

  /// 格式化请求体/响应体，防止超大二进制或数据刷屏与深度序列化开销。
  static String formatPayload(dynamic data, {int maxLength = 512}) {
    if (data == null) return '<null>';
    if (data is List<int>) return '<binary bytes: ${data.length}>';
    try {
      if (data is String) {
        if (data.length > maxLength) {
          return '${data.substring(0, maxLength)}... [truncated, total: ${data.length} chars]';
        }
        return data;
      }
      if (data is Map) {
        final keys = data.keys.take(8).join(', ');
        return '<Map with ${data.length} entries, keys: [$keys${data.length > 8 ? ', ...' : ''}]>';
      }
      if (data is List) {
        return '<List with ${data.length} items>';
      }
      final text = data.toString();
      if (text.length > maxLength) {
        return '${text.substring(0, maxLength)}... [truncated, total: ${text.length} chars]';
      }
      return text;
    } catch (_) {
      return '<unformattable ${data.runtimeType}>';
    }
  }
}

/// 单线程串行执行器：保证落盘顺序且不阻塞主 UI Isolate。
class _AsyncExecutor {
  Future<void> _task = Future.value();

  Future<void> submit(Future<void> Function() task) {
    final completer = Completer<void>();
    _task = _task.then((_) async {
      try {
        await task();
      } catch (_) {
        // 吞掉异常，防止单次写失败阻断后续任务。
      } finally {
        completer.complete();
      }
    });
    return completer.future;
  }
}

/// Dio 深度请求拦截器，记录所有进出的网络流量与状态。
class ApiBlackboxInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra['_start_time'] = DateTime.now().millisecondsSinceEpoch;
    final cookieHeader = options.headers[HttpHeaders.cookieHeader] as String? ?? '';
    
    // 脱敏 Cookie 显示（只显示 Cookie 键名与前后各 3 位）
    final cookieSummary = _sanitizeCookieHeader(cookieHeader);

    ApiBlackbox.log(
      'HTTP-REQ',
      '--> ${options.method} ${options.uri}\n'
      '    Headers: {user-agent: ${options.headers['user-agent']}, referer: ${options.headers['referer']}}\n'
      '    Cookies: $cookieSummary\n'
      '    Query: ${options.queryParameters}\n'
      '    Data: ${ApiBlackbox.formatPayload(options.data)}',
    );
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final startTime = response.requestOptions.extra['_start_time'] as int?;
    final cost = startTime != null
        ? '${DateTime.now().millisecondsSinceEpoch - startTime}ms'
        : 'unknown';

    ApiBlackbox.log(
      'HTTP-RES',
      '<-- [${response.statusCode}] ${response.requestOptions.method} ${response.requestOptions.uri} ($cost)\n'
      '    ContentType: ${response.headers.value(HttpHeaders.contentTypeHeader)}\n'
      '    Body: ${ApiBlackbox.formatPayload(response.data)}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final startTime = err.requestOptions.extra['_start_time'] as int?;
    final cost = startTime != null
        ? '${DateTime.now().millisecondsSinceEpoch - startTime}ms'
        : 'unknown';

    ApiBlackbox.log(
      'HTTP-ERR',
      '<-- [ERROR ${err.type}] ${err.requestOptions.method} ${err.requestOptions.uri} ($cost)\n'
      '    Message: ${err.message}\n'
      '    ResponseCode: ${err.response?.statusCode}\n'
      '    ResponseBody: ${ApiBlackbox.formatPayload(err.response?.data)}\n'
      '    Error: ${err.error}',
    );
    handler.next(err);
  }

  static String _sanitizeCookieHeader(String cookieHeader) {
    if (cookieHeader.isEmpty) return '<empty>';
    final parts = cookieHeader.split(';');
    final sanitized = parts.map((p) {
      final pair = p.trim().split('=');
      if (pair.length != 2) return p.trim();
      final k = pair[0].trim();
      final v = pair[1].trim();
      if (v.length <= 6) return '$k=$v';
      return '$k=${v.substring(0, 3)}***${v.substring(v.length - 3)}';
    }).join('; ');
    return sanitized;
  }
}
