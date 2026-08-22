import 'dart:async';
import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// 启动黑箱（Dart 侧）— 诊断"偶尔启动白屏"。
///
/// 与原生侧 blackbox（windows/runner/blackbox.cpp →
/// Documents/logs/blackbox_native.log）配合，本类写
/// Documents/logs/blackbox_dart.log。两侧时间戳均为本地墙钟毫秒，
/// 可交叉对齐还原完整启动时间线：
///
/// 原生：进程入口 → 建窗 → 引擎创建 → 首帧呈现 → Show
/// Dart：main 入口 → binding → bootstrap 各阶段 → 首帧 timing → AppRoot
///
/// 附加能力：
/// - 首帧 FrameTiming（build/raster/total/vsyncOverhead，光栅耗时异常即现形）
/// - 帧心跳：启动后 30s 内每 3s 记录累计帧数（帧数停止增长 = 渲染管线停滞）
/// - 生命周期状态变化（resumed/inactive/hidden）
///
/// 写入策略与 [SyncTrace] 相同：同步写 + 立即 flush，进程瞬死不丢尾部；
/// 未初始化前 pending 缓冲；任何 IO 异常静默吞掉。
abstract final class StartupBlackbox {
  static RandomAccessFile? _raf;
  static final List<String> _pending = [];
  static bool _initTried = false;
  static final Stopwatch _sw = Stopwatch()..start();

  static bool _timingSeen = false;
  static bool _firstFrameLogged = false;
  static int _frames = 0;
  static int _beats = 0;
  static Timer? _heartbeat;

  /// 初始化：解析 Documents/logs、滚动超限文件（>2MB → .old）、补写缓冲。
  /// 在 main() 最先调用（unawaited 即可，pending 缓冲保证事件顺序）。
  static Future<void> init() async {
    if (_initTried) return;
    _initTried = true;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}${Platform.pathSeparator}logs');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final file =
          File('${dir.path}${Platform.pathSeparator}blackbox_dart.log');
      if (file.existsSync() && file.lengthSync() > 2 * 1024 * 1024) {
        final old = File('${file.path}.old');
        if (old.existsSync()) old.deleteSync();
        file.renameSync(old.path);
      }
      final raf = file.openSync(mode: FileMode.append);
      for (final line in _pending) {
        raf.writeStringSync(line);
      }
      _pending.clear();
      _raf = raf;
    } catch (_) {
      // 无法落盘则放弃（保留内存缓冲无害）。
    }
  }

  /// 写一条黑箱日志（本地墙钟 + main 相对毫秒），立即 flush。
  static void log(String tag, String message) {
    final line =
        '${DateTime.now().toIso8601String()} [${_sw.elapsedMilliseconds}ms] '
        '$tag | $message\n';
    final raf = _raf;
    if (raf != null) {
      try {
        raf.writeStringSync(line);
        raf.flushSync();
        return;
      } catch (_) {}
    } else {
      _pending.add(line);
      if (_pending.length > 256) _pending.removeRange(0, 128);
    }
  }

  /// 挂接帧跟踪：首帧 FrameTiming + post-frame 里程碑 + 30s 帧心跳。
  /// 在 WidgetsFlutterBinding.ensureInitialized() 之后调用。
  static void attachFrameTracking() {
    WidgetsBinding.instance.addTimingsCallback(_onTimings);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_firstFrameLogged) return;
      _firstFrameLogged = true;
      var viewInfo = '';
      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isNotEmpty) {
        final v = views.first;
        viewInfo =
            ' view=${v.physicalSize.width}x${v.physicalSize.height} dpr=${v.devicePixelRatio.toStringAsFixed(2)}';
      }
      log('firstframe', 'first frame rendered (post-frame callback)$viewInfo');
    });
    _heartbeat = Timer.periodic(const Duration(seconds: 3), (_) {
      _beats++;
      log('heartbeat', 'frames=$_frames');
      if (_beats >= 10) {
        _heartbeat?.cancel();
        log('heartbeat', 'startup heartbeat finished');
      }
    });
  }

  static void _onTimings(List<FrameTiming> timings) {
    _frames += timings.length;
    if (_timingSeen) return;
    _timingSeen = true;
    final t = timings.first;
    log(
      'firstframe',
      'first FrameTiming: build=${t.buildDuration.inMilliseconds}ms '
      'raster=${t.rasterDuration.inMilliseconds}ms '
      'total=${t.totalSpan.inMilliseconds}ms '
      'vsyncOverhead=${t.vsyncOverhead.inMilliseconds}ms',
    );
  }

  /// 生命周期变化（AppLifecycleListener 回调直连）。
  static void logLifecycle(AppLifecycleState state) =>
      log('lifecycle', state.name);
}
