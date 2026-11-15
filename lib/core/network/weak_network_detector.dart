import 'package:dio/dio.dart';

import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/core/log/app_logger.dart';

void _showWeakNetworkPrompt(String message) {
  AppLogger.w('WeakNetwork', 'prompt: $message');
  showAppSnackBar(message);
}

/// 弱网判定与用户提示。
///
/// 信号来源：
/// - HTTP 请求总耗时 ≥ [slowRequestThreshold]，或连接/响应超时；
/// - 播放器流速持续低于期望 / 缓冲停滞（由 PlayerController 上报）。
///
/// 提示策略：一次弱网「回合」只提示一次；只有连续健康信号持续
/// [healthyWindow] 后才重置回合，避免长时间弱网期间反复弹 toast。
class WeakNetworkDetector {
  WeakNetworkDetector({
    this.slowRequestThreshold = const Duration(seconds: 3),
    this.healthyWindow = const Duration(seconds: 10),
    this.promptCooldown = const Duration(seconds: 60),
    this.message = '网络较慢，请检查网络或更换网络环境',
    DateTime Function()? clock,
    void Function(String message)? onPrompt,
  }) : _clock = clock ?? DateTime.now,
       _onPrompt = onPrompt ?? _showWeakNetworkPrompt;

  /// 全局单例：HTTP 与播放器共用同一弱网回合。
  static final WeakNetworkDetector instance = WeakNetworkDetector();

  /// 慢请求判定阈值。
  final Duration slowRequestThreshold;

  /// 连续健康多久后重置弱网回合。
  final Duration healthyWindow;

  /// 两次提示之间的最小间隔（跨回合保护）。
  final Duration promptCooldown;

  final String message;
  final DateTime Function() _clock;
  final void Function(String message) _onPrompt;

  DateTime? _lastPromptAt;
  DateTime? _healthySince;
  bool _promptedThisEpisode = false;

  /// 连续慢请求计数与窗口：单次 3s 成功响应不再提示（2026-11-14 22:53 实证：
  /// 播放缓冲领先 15s 时，一条非关键 HTTP 慢请求仍弹「网络较慢」）。
  int _slowRequestStreak = 0;
  DateTime? _lastSlowRequestAt;
  static const Duration _slowRequestWindow = Duration(seconds: 60);

  /// 播放关键请求（playurl 等）：慢一次即可视为弱网；其余接口需连续两次。
  static bool _isPlaybackCriticalPath(String path) =>
      path.contains('playurl') || path.contains('/x/player/');

  /// 上报一次请求耗时（成功响应）。
  void reportRequestLatency(Duration latency, {String? path}) {
    if (latency >= slowRequestThreshold) {
      final now = _clock();
      final last = _lastSlowRequestAt;
      if (last == null || now.difference(last) > _slowRequestWindow) {
        _slowRequestStreak = 0;
      }
      _slowRequestStreak++;
      _lastSlowRequestAt = now;
      final p = path ?? '';
      final critical = _isPlaybackCriticalPath(p);
      AppLogger.w(
        'WeakNetwork',
        'slow request ${latency.inMilliseconds}ms path=$p '
        'streak=$_slowRequestStreak critical=${critical ? 1 : 0}',
      );
      if (critical || _slowRequestStreak >= 2) {
        _markWeak(
          'http path=$p latency=${latency.inMilliseconds}ms '
          'streak=$_slowRequestStreak critical=${critical ? 1 : 0}',
        );
      }
    } else if (latency <= const Duration(milliseconds: 1500)) {
      _slowRequestStreak = 0;
      _markHealthy();
    }
  }

  /// 上报请求超时/连接错误。
  void reportTimeout({String? path}) =>
      _markWeak('timeout path=${path ?? '-'}');

  /// 上报播放器弱网（流速不健康或缓冲停滞）。
  void reportPlaybackWeak() => _markWeak('playback');

  /// 上报播放器健康（流速正常且未缓冲）。
  void reportPlaybackHealthy() => _markHealthy();

  /// 重置全部状态（测试/诊断用）。
  void reset() {
    _lastPromptAt = null;
    _healthySince = null;
    _promptedThisEpisode = false;
  }

  void _markWeak(String source) {
    _healthySince = null;
    if (_promptedThisEpisode) return;
    final now = _clock();
    final last = _lastPromptAt;
    if (last != null && now.difference(last) < promptCooldown) return;
    _promptedThisEpisode = true;
    _lastPromptAt = now;
    AppLogger.w('WeakNetwork', 'trigger source=$source');
    _onPrompt(message);
  }

  void _markHealthy() {
    final now = _clock();
    final since = _healthySince ??= now;
    if (now.difference(since) >= healthyWindow) {
      _promptedThisEpisode = false;
      _healthySince = null;
    }
  }
}

/// Dio 拦截器：采集请求总耗时与超时类型，驱动 [WeakNetworkDetector]。
///
/// 放在拦截器链末尾，使第一次网络失败即可上报；重试请求复用同一
/// `_weakNetworkStartedAt`，因此成功响应的耗时包含重试等待。
class WeakNetworkInterceptor extends Interceptor {
  WeakNetworkInterceptor({WeakNetworkDetector? detector})
    : _detector = detector ?? WeakNetworkDetector.instance;

  final WeakNetworkDetector _detector;

  static const String _startedAtKey = '_weakNetworkStartedAt';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startedAtKey] ??= DateTime.now().millisecondsSinceEpoch;
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final startedAt = response.requestOptions.extra[_startedAtKey];
    if (startedAt is int) {
      _detector.reportRequestLatency(
        Duration(
          milliseconds: DateTime.now().millisecondsSinceEpoch - startedAt,
        ),
        path: response.requestOptions.path,
      );
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        _detector.reportTimeout(path: err.requestOptions.path);
      default:
        break;
    }
    handler.next(err);
  }
}
