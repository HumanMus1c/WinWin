import 'package:flutter/foundation.dart';

import 'package:winwin/services/logger.dart';

import 'log_collector.dart';

/// 统一日志入口，业务代码应优先使用此类而非直接调用 [logger]。
///
/// 混合方案：
/// - 控制台输出：委托全局 [logger]（ProductionFilter + 级别阈值）。
/// - 内存缓冲 + 落盘：委托 [LogCollector]（BiliPai 思想）。
///
/// 级别门控（BiliPai 思想）：
/// - d/i：受 `enableVerboseLog`（kDebugMode && 用户 opt-in）门控，release 默认静默。
/// - w/e：始终进缓冲，release 也留线索（补 PiliPai 缺口）。
///
/// 用法：
///   AppLogger.d('PlayerController', 'prepare ret=$ret, url=$url');
///   AppLogger.e('PlayerController', 'open failed', error: e, stackTrace: s);
abstract final class AppLogger {
  /// verbose 开关：kDebugMode 且用户在设置中开启。
  /// L7 阶段接入 Pref.enableVerboseLog；在此之前用 kDebugMode 兜底。
  static bool get enableVerboseLog => kDebugMode;

  /// 落盘开关：始终开启（w/e 级别落盘开销极小，且是线上排查的唯一线索）。
  /// BiliPai 思想：release 也缓冲 w/e + 落盘。L7 阶段接入 Pref 开关后可细化。
  static bool get enablePersistence => true;

  /// 初始化 LogCollector（幂等）。应在 main() 早期调用。
  static Future<void> init() async {
    await LogCollector.init(persistenceEnabled: enablePersistence);
  }

  /// debug 级别：受 verbose 门控。
  static void d(String tag, String message) {
    if (!enableVerboseLog) return;
    logger.d('$tag: $message');
    LogCollector.add(level: 'D', tag: tag, message: message);
  }

  /// info 级别：受 verbose 门控。
  static void i(String tag, String message) {
    if (!enableVerboseLog) return;
    logger.i('$tag: $message');
    LogCollector.add(level: 'I', tag: tag, message: message);
  }

  /// warning 级别：始终输出 + 缓冲。
  static void w(String tag, String message) {
    logger.w('$tag: $message');
    LogCollector.add(level: 'W', tag: tag, message: message);
  }

  /// error 级别：始终输出 + 缓冲。可选附 error/stackTrace。
  static void e(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    logger.e('$tag: $message', error: error, stackTrace: stackTrace);
    final full = error != null
        ? stackTrace != null
            ? '$message | $error\n$stackTrace'
            : '$message | $error'
        : message;
    LogCollector.add(level: 'E', tag: tag, message: full);
  }

  /// 崩溃快照：把最近日志写入字符串，供崩溃 Report 附加。
  /// （L5 阶段 JsonFileHandler 调用）
  static String crashSnapshot({int count = 500}) {
    return LogCollector.crashSnapshot(count: count);
  }
}
