import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'package:winwin/core/log/app_logger.dart';

/// 渲染/UI 停摆看门狗（取证 + 自愈）。
///
/// 背景（2026-10-21 实机取证）：整机显示「黑屏掉线再自动恢复」（GPU 驱动更新/重置）时
/// D3D 设备丢失；若此时线程正阻塞在一次**永远等不到**的 GPU 同步调用上（本项目
/// `mdk.setGlobalOption('d3d11.sync.cpu', 1)` 的 CPU-GPU 栅栏即属此类），症状为：
///   - UI isolate 事件循环停摆 → Dart 定时器不再触发、`runtime.log` 静默；
///   - 全进程 CPU ≈ 0（线程全在 Wait）；
///   - 平台线程仍存活（窗口 Responding=True、进程不退出、无 Dart 异常、无 WER 崩溃）。
///
/// 设计：主 isolate 每秒向独立**后台 isolate** 发心跳；后台 isolate 拥有自己的事件循环，
/// 不受 UI isolate 阻塞影响，因而能在停摆发生的当下独立落盘取证（`render_stall.log`）。
/// 达到自愈阈值后执行「延时重启 + 退出恢复」，规避单实例互斥锁（
/// `Local\winwin-single-instance-v1`）竞争。
class StallWatchdog {
  StallWatchdog._();

  static SendPort? _beat;
  static bool _started = false;

  /// 取证阈值（秒）：无心跳超过该值即判定 UI isolate 停摆并开始落盘。
  static const int stallLogSec = 8;

  /// 自愈阈值（秒）：无心跳超过该值即执行自愈（延时重启 + 退出）。
  static const int recoverSec = 30;

  /// 启动看门狗（幂等）。应在 `WidgetsFlutterBinding.ensureInitialized()` 之后、
  /// `runApp` 之前调用。后台 isolate 无法使用 path_provider，故日志目录在主 isolate 解析。
  ///
  /// [autoRecover]=false 时仅取证不退出；默认 true。
  static Future<void> init({bool autoRecover = true}) async {
    if (_started) return;
    _started = true;

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

    // 主 isolate 心跳：定时器一旦因 isolate 阻塞而停止，后台即判定停摆。
    Timer.periodic(const Duration(seconds: 1), (_) {
      _beat?.send(DateTime.now().millisecondsSinceEpoch);
    });

    WidgetsBinding.instance.addObserver(_MetricsObserver());
    AppLogger.w(
      'StallWatchdog',
      'watchdog started (logDir=$logDir, autoRecover=$autoRecover)',
    );
  }
}

/// 后台监测 isolate：接收主 isolate 心跳，超阈值即落盘取证；达自愈阈值执行重启。
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
    stalling = ageSec >= StallWatchdog.stallLogSec;

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
      if (autoRecover && !recovered && ageSec >= StallWatchdog.recoverSec) {
        recovered = true;
        _append(
          logFile,
          'AUTO-RECOVER: UI isolate stalled ${ageSec.toStringAsFixed(0)}s '
          '>= ${StallWatchdog.recoverSec}s -> relaunch & exit',
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

/// 自愈动作：延时 ~3s 后重启自身，随即强制退出本进程（释放单实例互斥锁后再由新进程接管）。
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