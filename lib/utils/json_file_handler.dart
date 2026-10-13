import 'dart:convert';
import 'dart:io';

import 'package:catcher_2/catcher_2.dart';
import 'package:catcher_2/model/platform_type.dart';
import 'package:flutter/widgets.dart';
import 'package:winwin/services/logger.dart';

/// 崩溃 Report 落盘 Handler，移植自 PiliPlus。
///
/// 把 catcher_2 的 [Report] 以 NDJSON（每行一个 JSON）追加写入
/// `.winwin_logs.json`，用静态 Future 链串行化写入避免并发；
/// 文件超过 5MB 时轮转为 `.old`（单代覆盖）。
class JsonFileHandler extends ReportHandler {
  /// 崩溃报告文件大小上限：超过即轮转为 `文件.old`（单代覆盖）。
  static const int _maxFileBytes = 5 * 1024 * 1024;

  final bool enableDeviceParameters;
  final bool enableApplicationParameters;
  final bool enableStackTrace;
  final bool enableCustomParameters;
  final bool printLogs;
  final bool handleWhenRejected;

  static Future<RandomAccessFile> _future = LoggerUtils.getCrashLogsPath()
      .then((file) => file.open(mode: FileMode.writeOnlyAppend))
      .then((raf) => raf.writeFrom(const []))
      .then(_flush);

  JsonFileHandler._({
    this.enableDeviceParameters = true,
    this.enableApplicationParameters = true,
    this.enableStackTrace = true,
    this.enableCustomParameters = true,
    this.printLogs = false,
    this.handleWhenRejected = false,
  });

  static Future<JsonFileHandler?> init({
    bool enableDeviceParameters = true,
    bool enableApplicationParameters = true,
    bool enableStackTrace = true,
    bool enableCustomParameters = true,
    bool printLogs = false,
    bool handleWhenRejected = false,
  }) async {
    try {
      await _future;
      return JsonFileHandler._(
        enableDeviceParameters: enableDeviceParameters,
        enableApplicationParameters: enableApplicationParameters,
        enableStackTrace: enableStackTrace,
        enableCustomParameters: enableCustomParameters,
        printLogs: printLogs,
        handleWhenRejected: handleWhenRejected,
      );
    } catch (e, s) {
      logger.e('Init log file', error: e, stackTrace: s);
      return null;
    }
  }

  static Future<RandomAccessFile> _flush(RandomAccessFile raf) =>
      raf.flush();

  static Future<RandomAccessFile> add(
    Future<RandomAccessFile> Function(RandomAccessFile) onValue,
  ) {
    return _future = _future.then(onValue).then(_flush);
  }

  @override
  Future<bool> handle(Report report, BuildContext? context) async {
    try {
      await _processReport(report);
      return true;
    } catch (exc, stackTrace) {
      logger.e(
        'Write Json Exception occurred',
        error: exc,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  @override
  List<PlatformType> getSupportedPlatforms() => PlatformType.values;

  @override
  bool shouldHandleWhenRejected() => handleWhenRejected;

  Future<void> _processReport(Report report) {
    if (printLogs) {
      logger.d('Writing report to file');
    }
    final json = report.toJson(
      enableDeviceParameters: enableDeviceParameters,
      enableApplicationParameters: enableApplicationParameters,
      enableStackTrace: enableStackTrace,
      enableCustomParameters: enableCustomParameters,
    );
    return add((raf) async {
      final out = await _rotateIfNeeded(raf);
      await out.writeString('${jsonEncode(json)}\n');
      return out;
    });
  }

  /// 超过上限时把崩溃报告轮转为 `.old`（单代覆盖）并返回新的写入句柄。
  ///
  /// 轮转失败（如文件占用）时回退为继续追加原文件，绝不阻断报告写入。
  static Future<RandomAccessFile> _rotateIfNeeded(RandomAccessFile raf) async {
    try {
      if (await raf.length() <= _maxFileBytes) return raf;
    } catch (_) {
      return raf;
    }
    final path = raf.path;
    try {
      await raf.close();
      final old = File('$path.old');
      if (old.existsSync()) old.deleteSync();
      File(path).renameSync(old.path);
    } catch (_) {
      // 归档失败：继续使用原文件。
    }
    return File(path).open(mode: FileMode.writeOnlyAppend);
  }
}
