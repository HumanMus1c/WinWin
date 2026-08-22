import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:winwin/services/logger.dart';

import 'log_sanitizer.dart';

/// 内存环形缓冲 + 异步落盘，参照 BiliPai LogCollector 设计。
///
/// 设计要点：
/// - 内存缓冲：1000 条 [LogEntry] 环形队列，超出自动丢弃最旧条目。
/// - 重复抑制：250ms 窗口内同 level|tag|message 指纹直接丢弃，防日志风暴。
/// - 异步落盘：单线程串行追加到 `logs/runtime.log`，不阻塞主路径。
/// - 滚动裁剪：文件超 256KB 时保留最后 128KB 再追加。
/// - 隐私脱敏：延后到落盘时执行（主路径零成本，见 [LogSanitizer]）。
///
/// Release 行为：
/// - w/e 始终进缓冲（补 PiliPlus 缺口，线上留线索）。
/// - d/i 受 [AppLogger] 的 enableVerboseLog 门控，release 默认不进缓冲。
/// - 落盘受 enableLogPersistence 双重 opt-in（见 [AppLogger]）。
class LogCollector {
  LogCollector._();

  static const int _maxBuffer = 1000;
  static const int _maxFileBytes = 256 * 1024; // 256KB
  static const int _keepBytes = 128 * 1024; // 裁剪后保留 128KB
  static const Duration _dedupWindow = Duration(milliseconds: 250);

  static final List<LogEntry> _buffer = [];
  static bool _initialized = false;
  static bool _persistenceEnabled = false;
  static File? _file;
  static final _executor = _AsyncExecutor();

  /// 初始化：创建 logs 目录、读取落盘开关。幂等。
  static Future<void> init({required bool persistenceEnabled}) async {
    if (_initialized) return;
    _initialized = true;
    _persistenceEnabled = persistenceEnabled;
    if (_persistenceEnabled) {
      try {
        _file = await LoggerUtils.getRuntimeLogsPath();
      } catch (e, s) {
        // 落盘失败不影响内存缓冲，仅记录。
        debugPrint('[LogCollector] init runtime.log failed: $e\n$s');
        _persistenceEnabled = false;
      }
    }
  }

  /// 添加一条日志到缓冲，并按需异步落盘。
  static void add({
    required String level,
    required String tag,
    required String message,
    DateTime? timestamp,
  }) {
    if (!_initialized) return;
    final now = timestamp ?? DateTime.now();

    // 重复抑制：250ms 窗口内同指纹丢弃。
    final fingerprint = '$level|$tag|$message';
    final last = _buffer.isNotEmpty ? _buffer.last : null;
    if (last != null &&
        last.fingerprint == fingerprint &&
        now.difference(last.timestamp).abs() < _dedupWindow) {
      return;
    }

    final entry = LogEntry(
      level: level,
      tag: tag,
      message: message,
      timestamp: now,
      fingerprint: fingerprint,
    );
    _buffer.add(entry);
    if (_buffer.length > _maxBuffer) {
      _buffer.removeRange(0, _buffer.length - _maxBuffer);
    }

    // 落盘：脱敏后异步追加（脱敏计算移至后台异步队列执行，主路径零成本）。
    if (_persistenceEnabled && _file != null) {
      _executor.submit(() async {
        final sanitized = LogSanitizer.sanitize(message);
        final line =
            '${entry.timestamp.toIso8601String()} [$level] $tag: $sanitized\n';
        await _appendWithRotation(line);
      });
    }
  }

  /// 读取当前内存缓冲（日志查看 UI 用）。
  static List<LogEntry> snapshot() => List.unmodifiable(_buffer);

  /// 清空内存缓冲 + 落盘文件。
  static Future<void> clear() async {
    _buffer.clear();
    if (_file != null && _file!.existsSync()) {
      await _executor.submit(() async {
        final raf = await _file!.open(mode: FileMode.write);
        await raf.truncate(0);
        await raf.close();
      });
    }
  }

  /// 崩溃快照：把最近 N 条内存缓冲（脱敏后）写入字符串，供崩溃 Report 附加。
  static String crashSnapshot({int count = 500}) {
    final entries = _buffer.length > count
        ? _buffer.sublist(_buffer.length - count)
        : _buffer;
    final sb = StringBuffer();
    sb.writeln('=== Recent logs (${entries.length} entries) ===');
    for (final e in entries) {
      final sanitized = LogSanitizer.sanitize(e.message);
      sb.writeln('${e.timestamp.toIso8601String()} [${e.level}] ${e.tag}: $sanitized');
    }
    return sb.toString();
  }

  /// 滚动裁剪 + 追加。
  static Future<void> _appendWithRotation(String line) async {
    if (_file == null) return;
    try {
      var file = _file!;
      // 超过上限：读尾部 128KB 重写。
      if (file.existsSync() && file.lengthSync() > _maxFileBytes) {
        final raf = await file.open(mode: FileMode.read);
        await raf.setPosition(file.lengthSync() - _keepBytes);
        final tail = await raf.read(_keepBytes);
        await raf.close();
        final sink = file.openWrite(mode: FileMode.write);
        sink.add(tail);
        await sink.flush();
        await sink.close();
      }
      // 追加新行。
      await file.writeAsString(line, mode: FileMode.append, flush: true);
    } catch (e) {
      // 落盘失败不抛出，避免影响主流程。
      debugPrint('[LogCollector] append failed: $e');
    }
  }
}

/// 单条内存日志记录。
@immutable
class LogEntry {
  const LogEntry({
    required this.level,
    required this.tag,
    required this.message,
    required this.timestamp,
    required this.fingerprint,
  });

  final String level;
  final String tag;
  final String message;
  final DateTime timestamp;
  final String fingerprint;

  @override
  String toString() =>
      '${timestamp.toIso8601String()} [$level] $tag: $message';
}

/// 单线程串行执行器：保证落盘顺序，避免并发写入冲突。
///
/// 不用 Isolate：Windows 桌面 Flutter 的 Isolate spawn 开销大且文件 IO
/// 本身是 native 异步，Future 链串行化已足够保证写入顺序。
class _AsyncExecutor {
  Future<void> _task = Future.value();

  Future<void> submit(Future<void> Function() task) {
    final completer = Completer<void>();
    _task = _task.then((_) async {
      try {
        await task();
      } catch (e) {
        // 吞掉异常，防止单次失败阻断后续任务。
      } finally {
        completer.complete();
      }
    });
    return completer.future;
  }
}
