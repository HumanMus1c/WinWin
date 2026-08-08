import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 全局 logger 单例。
///
/// 混合方案（PiliPlus 骨架 + BiliPai 增强）：
/// - ProductionFilter：release 也按 level 过滤（非 DevelopmentFilter 的 debug-only）。
/// - PrettyPrinter：带时间戳与堆栈格式化（logger 包内置）。
/// - 级别阈值：debug=.trace（全量），release=.warning（仅 warn 及以上）。
///
/// 业务代码应优先使用 [AppLogger]（lib/core/log/app_logger.dart）而非直接调用
/// 此 logger，AppLogger 在此基础上叠加内存环形缓冲 + 脱敏 + 落盘。
final logger = Logger(
  filter: ProductionFilter(),
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 8,
    dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
  ),
  level: kDebugMode ? Level.trace : Level.warning,
);

/// 日志文件路径管理。
///
/// - `.winwin_logs.json`：崩溃 Report（NDJSON，由 [JsonFileHandler] 追加写入）。
/// - `logs/runtime.log`：普通运行日志（由 [LogCollector] 异步落盘 + 滚动裁剪）。
abstract final class LoggerUtils {
  static File? _crashLogFile;
  static File? _runtimeLogFile;

  /// 崩溃 Report 文件（NDJSON）。
  static Future<File> getCrashLogsPath() async {
    if (_crashLogFile != null) return _crashLogFile!;
    final String dir = (await getApplicationDocumentsDirectory()).path;
    final String filename = p.join(dir, '.winwin_logs.json');
    final File file = File(filename);
    if (!file.existsSync()) {
      await file.create(recursive: true);
    }
    return _crashLogFile = file;
  }

  /// 普通运行日志文件（滚动裁剪）。
  static Future<File> getRuntimeLogsPath() async {
    if (_runtimeLogFile != null) return _runtimeLogFile!;
    final String dir = (await getApplicationDocumentsDirectory()).path;
    final String filename = p.join(dir, 'logs', 'runtime.log');
    final File file = File(filename);
    if (!file.existsSync()) {
      await file.create(recursive: true);
    }
    return _runtimeLogFile = file;
  }

  /// 清空所有日志（崩溃 Report + 运行日志）。
  static Future<bool> clearLogs() async {
    try {
      final crashFile = await getCrashLogsPath();
      await crashFile.writeAsBytes(const [], flush: true);
      final runtimeFile = await getRuntimeLogsPath();
      await runtimeFile.writeAsBytes(const [], flush: true);
    } catch (_) {
      return false;
    }
    return true;
  }
}
