import 'dart:io';

import 'package:winwin/services/logger.dart';

/// 同步崩溃安全追踪日志（诊断用）。
///
/// 与 [LogCollector]（异步落盘，进程瞬死丢尾部）不同，本类每行写完立即
/// flush：进程在任意一步被杀死时，最后一条日志即为死亡现场。
/// - 仅用于生命周期关键路径的低频埋点（返回/退出/释放），不承载业务日志。
/// - 未初始化前调用 [log] 会缓冲，init 后补写（应用启动早期场景）。
/// - 任何 IO 异常静默吞掉，绝不影响主流程。
/// - 文件超过 5MB 时轮转为 `trace.log.old`（单代覆盖），防无限增长。
abstract final class SyncTrace {
  static RandomAccessFile? _raf;
  static final List<String> _pending = [];
  static bool _initTried = false;

  /// 初始化：在 main() 早期调用（与 AppLogger.init 并列）。
  static Future<void> init() async {
    if (_initTried) return;
    _initTried = true;
    try {
      // 与 runtime.log 同目录（Documents/logs/），复用 LoggerUtils 的路径解析。
      final runtime = await LoggerUtils.getRuntimeLogsPath();
      final file = File('${runtime.parent.path}${Platform.pathSeparator}trace.log');
      _raf = file.openSync(mode: FileMode.append);
      for (final line in _pending) {
        _raf!.writeStringSync(line);
      }
      _pending.clear();
    } catch (_) {
      // 无法落盘则放弃（保留内存缓冲无害）。
    }
  }

  /// 写一条同步日志并立即 flush。
  static void log(String tag, String message) {
    final line = '${DateTime.now().toIso8601String()} $tag: $message\n';
    if (_raf != null) {
      try {
        _rotateIfNeeded();
        _raf!.writeStringSync(line);
        _raf!.flushSync();
        return;
      } catch (_) {}
    } else {
      _pending.add(line);
      if (_pending.length > 200) _pending.removeRange(0, 100);
    }
  }

  /// 文件大小上限（5MB）：超过即轮转为 `trace.log.old`（单代覆盖）。
  static const int _maxFileBytes = 5 * 1024 * 1024;

  /// 超限轮转；归档失败（如文件占用）时降级为继续追加原文件。
  static void _rotateIfNeeded() {
    final raf = _raf;
    if (raf == null) return;
    try {
      if (raf.lengthSync() <= _maxFileBytes) return;
    } catch (_) {
      return;
    }
    final path = raf.path;
    try {
      raf.closeSync();
      final old = File('$path.old');
      if (old.existsSync()) old.deleteSync();
      File(path).renameSync(old.path);
      _raf = File(path).openSync(mode: FileMode.append);
    } catch (_) {
      // 归档失败：继续使用原文件。
      try {
        _raf = File(raf.path).openSync(mode: FileMode.append);
      } catch (_) {
        _raf = null;
      }
    }
  }
}
