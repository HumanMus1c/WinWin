import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'package:winwin/core/log/sync_trace.dart';
import 'package:winwin/services/logger.dart';

/// 页面转场探针：记录每次转场的**用时**与**逐帧性能消耗**（诊断/回归用）。
///
/// 开关与配置来自 `Documents/logs/transition_probe.json`（与 SeekProbe 同惯例，
/// 默认关闭 = 零开销）：
/// ```json
/// { "enabled": true, "verbose": false }
/// ```
/// - `enabled`：false/缺省时 [begin]/[end] 为空操作，也不注册帧回调；
/// - `verbose`：true 时额外逐帧打印 build/raster 明细。
///
/// 每次转场在动画结束时输出一行结论（经 [SyncTrace] 同步落盘
/// `Documents/logs/trace.log`，grep `TransitionProbe`）：
/// - `ms`：实际用时（动画 forward/reverse 开始 → completed/dismissed 的墙钟）；
/// - `cfg`：该路由配置的转场时长（对照用，判断是否按时长跑满）；
/// - `frames` / `fps`：窗口内帧数与实测帧率；
/// - `build(avg/max/jank)`：UI 线程构建耗时（平均/最差/超 16.7ms 帧数）；
/// - `raster(avg/max/jank)`：光栅线程耗时（同上）——转场卡顿主要看 raster；
/// - `route` / `dir`：路由标签与方向（push/pop）。
class TransitionProbe {
  TransitionProbe._();

  /// 单例（由转场核 `MiuixPageTransition` 驱动）。
  static final TransitionProbe instance = TransitionProbe._();

  /// 是否启用（由配置文件决定；测试可直接置位）。
  static bool enabled = false;

  /// 是否逐帧输出明细。
  static bool verbose = false;

  /// 60Hz 帧预算（ms）：判断 jank 的阈值。
  static const double frameBudgetMs = 1000 / 60;

  bool _attached = false;
  bool _recording = false;
  String _label = 'unknown';
  String _direction = 'push';
  int _configuredMs = 0;
  int _startMs = 0;
  int _frames = 0;
  double _buildSum = 0;
  double _rasterSum = 0;
  double _buildMax = 0;
  double _rasterMax = 0;
  int _buildJank = 0;
  int _rasterJank = 0;

  /// 最近若干次转场结论（供测试/自查读取；最多保留 50 条）。
  final List<String> reports = <String>[];

  /// 读取配置并（启用时）挂载帧耗时回调；在 `main()` 中调用一次。
  static Future<void> init() async {
    await _loadConfig();
    if (enabled) {
      instance._attach();
    }
    SyncTrace.log(
      'TransitionProbe',
      'init enabled=$enabled verbose=$verbose',
    );
  }

  static Future<void> _loadConfig() async {
    try {
      final runtime = await LoggerUtils.getRuntimeLogsPath();
      final file = File(
        '${runtime.parent.path}${Platform.pathSeparator}transition_probe.json',
      );
      if (!file.existsSync()) return;
      final raw = jsonDecode(await file.readAsString());
      if (raw is Map) {
        enabled = raw['enabled'] == true;
        verbose = raw['verbose'] == true;
      }
    } catch (_) {
      // 配置缺失/损坏时保持默认（关闭）。
    }
  }

  void _attach() {
    if (_attached) return;
    _attached = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    if (!_recording) return;
    for (final FrameTiming timing in timings) {
      final double buildMs = timing.buildDuration.inMicroseconds / 1000.0;
      final double rasterMs = timing.rasterDuration.inMicroseconds / 1000.0;
      _record(buildMs: buildMs, rasterMs: rasterMs);
      if (verbose) {
        SyncTrace.log(
          'TransitionProbe',
          'frame $_direction $_label #$_frames '
          'build=${buildMs.toStringAsFixed(2)} '
          'raster=${rasterMs.toStringAsFixed(2)}',
        );
      }
    }
  }

  void _record({required double buildMs, required double rasterMs}) {
    _frames++;
    _buildSum += buildMs;
    _rasterSum += rasterMs;
    if (buildMs > _buildMax) _buildMax = buildMs;
    if (rasterMs > _rasterMax) _rasterMax = rasterMs;
    if (buildMs > frameBudgetMs) _buildJank++;
    if (rasterMs > frameBudgetMs) _rasterJank++;
  }

  /// 转场开始（动画状态进入 forward=push / reverse=pop 时调用）。
  void begin(String label, {required bool reverse, int configuredMs = 0}) {
    if (!enabled) return;
    _recording = true;
    _label = label;
    _direction = reverse ? 'pop' : 'push';
    _configuredMs = configuredMs;
    _startMs = DateTime.now().millisecondsSinceEpoch;
    _frames = 0;
    _buildSum = 0;
    _rasterSum = 0;
    _buildMax = 0;
    _rasterMax = 0;
    _buildJank = 0;
    _rasterJank = 0;
  }

  /// 转场结束（动画 completed/dismissed 时调用）：输出结论行。
  void end() {
    if (!enabled || !_recording) return;
    _recording = false;
    final int ms = DateTime.now().millisecondsSinceEpoch - _startMs;
    final String line = summary(ms);
    reports.add(line);
    if (reports.length > 50) {
      reports.removeAt(0);
    }
    SyncTrace.log('TransitionProbe', line);
  }

  /// 组装结论行（[visibleForTesting] 便于对账聚合口径）。
  @visibleForTesting
  String summary(int ms) {
    final int n = _frames;
    final double avgBuild = n == 0 ? 0 : _buildSum / n;
    final double avgRaster = n == 0 ? 0 : _rasterSum / n;
    final double fps = ms <= 0 ? 0 : n * 1000 / ms;
    return 'transition route=$_label dir=$_direction '
        'ms=$ms cfg=${_configuredMs}ms frames=$n fps=${fps.toStringAsFixed(1)} '
        'build(avg=${avgBuild.toStringAsFixed(2)} '
        'max=${_buildMax.toStringAsFixed(2)} jank=$_buildJank) '
        'raster(avg=${avgRaster.toStringAsFixed(2)} '
        'max=${_rasterMax.toStringAsFixed(2)} jank=$_rasterJank)';
  }

  /// 是否正在记录（[visibleForTesting]）。
  @visibleForTesting
  bool get isRecording => _recording;

  /// 手动注入一帧耗时（[visibleForTesting]：单测不依赖真实渲染管线）。
  @visibleForTesting
  void recordFrame({required double buildMs, required double rasterMs}) {
    if (!_recording) return;
    _record(buildMs: buildMs, rasterMs: rasterMs);
  }
}
