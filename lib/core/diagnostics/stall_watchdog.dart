import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'package:winwin/core/log/app_logger.dart';

/// 渲染/UI 停摆看门狗：**分级恢复**（进程内轻量恢复优先，兜底才整进程重启）。
///
/// 背景（2026-10-21 实机取证）：整机显示「黑屏掉线再自动恢复」（GPU 驱动更新/重置）时
/// D3D 设备丢失；若此时线程阻塞在一次**永远等不到**的 GPU 同步调用上（如
/// `mdk.setGlobalOption('d3d11.sync.cpu', 1)` 的 CPU-GPU 栅栏），症状为：
///   - UI isolate 事件循环停摆 → Dart 定时器停、`runtime.log` 静默；
///   - 全进程 CPU ≈ 0（线程全 Wait）；平台线程仍存活（Responding=True、不退出、无异常）。
///
/// 两条路径：
///  1. **暖路径（UI isolate 存活，仅渲染停摆）**——主 isolate 用 `addTimingsCallback`
///     跟踪"最近一次完成渲染"，在"期望出帧"（视频播放中）状态下发现 ≥[softSec] 无帧，
///     先执行**进程内轻量恢复**（重建播放器/纹理 + 强制出帧）；若 ≥[escalateSec] 仍未恢复，
///     再升级为整进程重启。
///  2. **冷路径（UI isolate 整体停摆）**——主 isolate 每秒心跳一旦停止，独立**后台 isolate**
///     （有自己事件循环，不受阻塞影响）在 ≥[coldSec] 时落盘取证并整进程重启。
///
/// 「期望出帧」由播放器在播放/暂停时用 [setRenderExpected] 声明，避免把"静止页面无重绘"
/// 误判为卡死。
class StallWatchdog {
  StallWatchdog._();

  static SendPort? _beat;
  static bool _started = false;
  static bool _autoRecover = true;

  /// 冷路径阈值（秒）：UI isolate 心跳停止多久判定整体停摆。
  static const int coldSec = 30;

  /// 暖路径取证阈值（秒）：期望出帧状态下多久无帧判定渲染停摆。
  static const int softSec = 5;

  /// 暖路径升级阈值（秒）：轻量恢复后多久仍未出帧即升级为整进程重启。
  static const int escalateSec = 15;

  static int _lastFrameMs = 0;
  static bool _renderExpected = false;
  static int _episodeStartMs = 0;
  static bool _softAttempted = false;
  static Future<void> Function(String reason)? _softRecovery;

  /// 注册「进程内轻量恢复」回调（由活动的播放器提供：重建 player + 重挂纹理）。
  /// 仅保留最后一个注册者（同一时刻通常只有一个活动播放器）。
  static void registerSoftRecovery(Future<void> Function(String reason) fn) {
    _softRecovery = fn;
  }

  static void unregisterSoftRecovery(Future<void> Function(String reason) fn) {
    if (identical(_softRecovery, fn)) _softRecovery = null;
  }

  /// 声明「当前是否应当持续出帧」（如视频正在播放）。停摆判定只在期望出帧时成立。
  static void setRenderExpected(bool v) {
    if (_renderExpected == v) return;
    _renderExpected = v;
    _lastFrameMs = DateTime.now().millisecondsSinceEpoch;
    _episodeStartMs = 0;
    _softAttempted = false;
  }

  /// 启动看门狗（幂等）。应在 `WidgetsFlutterBinding.ensureInitialized()` 之后、
  /// `runApp` 之前调用。后台 isolate 无法使用 path_provider，故日志目录在主 isolate 解析。
  static Future<void> init({bool autoRecover = true}) async {
    if (_started) return;
    _started = true;
    _autoRecover = autoRecover;
    _lastFrameMs = DateTime.now().millisecondsSinceEpoch;

    String logDir;
    try {
      final docs = await getApplicationDocumentsDirectory();
      logDir = '${docs.path}${Platform.pathSeparator}logs';
      await Directory(logDir).create(recursive: true);
    } catch (_) {
      final home = Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'] ??
          Directory.systemTemp.path;
      logDir =
          '$home${Platform.pathSeparator}Documents${Platform.pathSeparator}logs';
      try {
        await Directory(logDir).create(recursive: true);
      } catch (_) {
        logDir = Directory.systemTemp.path;
      }
    }

    final rp = ReceivePort();
    try {
      await Isolate.spawn(
        _watch,
        <String, Object>{
          'reply': rp.sendPort,
          'logDir': logDir,
          'autoRecover': autoRecover,
        },
        debugName: 'winwin_stall_watchdog',
      );
      _beat = await rp.first.timeout(const Duration(seconds: 5)) as SendPort;
    } catch (e) {
      AppLogger.w('StallWatchdog', 'spawn failed: $e');
      rp.close();
      return;
    }

    // 冷路径心跳：定时器一旦因 isolate 阻塞而停止，后台即判定整体停摆。
    Timer.periodic(const Duration(seconds: 1), (_) {
      _beat?.send(DateTime.now().millisecondsSinceEpoch);
    });

    // 暖路径：帧完成时间跟踪 + 期望出帧状态下的停摆判定。
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    Timer.periodic(const Duration(seconds: 2), (_) => _checkWarmRender());

    WidgetsBinding.instance.addObserver(_MetricsObserver());
    AppLogger.w(
      'StallWatchdog',
      'watchdog started (logDir=$logDir, autoRecover=$autoRecover, '
      'soft=${softSec}s, escalate=${escalateSec}s, cold=${coldSec}s)',
    );
  }

  static void _onTimings(List<FrameTiming> timings) {
    if (timings.isEmpty) return;
    // FrameTiming 为批量投递（最多 ~1s 延迟）；收到即视为"刚完成过渲染"。
    _lastFrameMs = DateTime.now().millisecondsSinceEpoch;
  }

  static void _checkWarmRender() {
    if (!_autoRecover || !_renderExpected || _lastFrameMs == 0) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final gap = now - _lastFrameMs;

    if (gap >= softSec * 1000) {
      if (_episodeStartMs == 0) {
        _episodeStartMs = now - softSec * 1000;
        _softAttempted = false;
        AppLogger.w(
          'StallWatchdog',
          'RENDER STALL: no completed frame for ${(gap / 1000).toStringAsFixed(0)}s '
          '(renderExpected=true)',
        );
      }
      if (!_softAttempted) {
        _softAttempted = true;
        final fn = _softRecovery;
        if (fn != null) {
          unawaited(Future<void>(() async {
            try {
              await fn('no-frame ${(gap / 1000).toStringAsFixed(0)}s');
            } catch (e) {
              AppLogger.w('StallWatchdog', 'soft recovery threw: $e');
            }
          }));
        } else {
          // 无播放器可重建：至少强制一次重绘（对纯引擎侧停摆是尽力而为）。
          SchedulerBinding.instance.scheduleFrame();
        }
        AppLogger.w('StallWatchdog', 'soft recovery requested');
      }
      if (now - _episodeStartMs >= escalateSec * 1000) {
        AppLogger.w(
          'StallWatchdog',
          'soft recovery ineffective (>${escalateSec}s) -> relaunch & exit',
        );
        _relaunchAndExit();
      }
    } else if (_episodeStartMs != 0) {
      AppLogger.w(
        'StallWatchdog',
        'RENDER RECOVERED after '
        '${((now - _episodeStartMs) / 1000).toStringAsFixed(1)}s',
      );
      _episodeStartMs = 0;
      _softAttempted = false;
    }
  }
}

/// 后台监测 isolate（冷路径）：接收主 isolate 心跳，超阈值即落盘取证；达阈值执行重启。
Future<void> _watch(Map<String, Object> cfg) async {
  final reply = cfg['reply'] as SendPort;
  final logDir = cfg['logDir'] as String;
  final autoRecover = cfg['autoRecover'] as bool;

  final rp = ReceivePort();
  reply.send(rp.sendPort);

  final logFile = File('$logDir${Platform.pathSeparator}render_stall.log');

  var lastBeatMs = DateTime.now().millisecondsSinceEpoch;
  var stalling = false;
  var stallStartMs = 0;
  var lastLoggedMs = 0;
  var recovered = false;

  rp.listen((msg) {
    if (msg is int) lastBeatMs = msg;
  });

  Timer.periodic(const Duration(seconds: 2), (_) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final ageMs = now - lastBeatMs;
    final ageSec = ageMs / 1000.0;
    final wasStalling = stalling;
    stalling = ageSec >= StallWatchdog.coldSec;

    if (stalling) {
      if (!wasStalling) {
        stallStartMs = now - ageMs;
        _append(logFile,
            'STALL START: no heartbeat (age~${ageSec.toStringAsFixed(0)}s)');
        lastLoggedMs = now;
      } else if (now - lastLoggedMs >= 5000) {
        _append(
          logFile,
          'STALL ongoing: age=${ageSec.toStringAsFixed(0)}s, '
          'dur=${((now - stallStartMs) / 1000).toStringAsFixed(0)}s',
        );
        lastLoggedMs = now;
      }
      if (autoRecover && !recovered && ageSec >= StallWatchdog.coldSec) {
        recovered = true;
        _append(
          logFile,
          'AUTO-RECOVER: UI isolate stalled ${ageSec.toStringAsFixed(0)}s '
          '>= ${StallWatchdog.coldSec}s -> relaunch & exit',
        );
        _relaunchAndExit();
      }
    } else if (wasStalling) {
      _append(
        logFile,
        'STALL END: recovered, total=${((now - stallStartMs) / 1000).toStringAsFixed(1)}s',
      );
    }
  });
}

/// 整进程恢复：延时 ~3s 后重启自身，随即强制退出本进程（释放单实例互斥锁后再由新进程接管）。
void _relaunchAndExit() {
  try {
    final exe = Platform.resolvedExecutable;
    final exeDir = File(exe).parent.path;
    Process.start(
      'cmd.exe',
      <String>['/c', 'ping -n 4 127.0.0.1 >nul & start "" "$exe"'],
      workingDirectory: exeDir,
      mode: ProcessStartMode.detached,
    );
  } catch (_) {}
  exit(0);
}

void _append(File f, String line) {
  try {
    f.writeAsStringSync(
      '[${DateTime.now().toIso8601String()}] $line\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {}
}

/// 视口/DPI 变更埋点：显示器切换或分辨率变更时记录到 runtime.log，
/// 便于与 `render_stall.log`、Windows Display 事件按时间线对齐。
class _MetricsObserver extends WidgetsBindingObserver {
  double? _dpr;
  Size? _size;

  @override
  void didChangeMetrics() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return;
    final view = views.first;
    final dpr = view.devicePixelRatio;
    final size = view.physicalSize;
    if (dpr != _dpr || size != _size) {
      AppLogger.w(
        'StallWatchdog',
        'didChangeMetrics: dpr=$dpr (was=$_dpr) physicalSize=$size (was=$_size)',
      );
      _dpr = dpr;
      _size = size;
    }
  }
}