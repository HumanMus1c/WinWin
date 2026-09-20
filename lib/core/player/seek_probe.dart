import 'dart:convert';
import 'dart:io';

import 'package:winwin/core/log/sync_trace.dart';
import 'package:winwin/services/logger.dart';

/// Seek 音画同步取证变体（A/B 对照矩阵，见计划 §Phase 1）。
enum SeekVariant {
  /// E0 基线：现状逻辑（冻结 → 主 seek → 事后重挂时间预算 → 解冻）。
  baseline,

  /// E1：关闭 demux 包缓存（`demux.buffer.ranges=0`），验证缓存是否让外挂音轨不归位。
  noCache,

  /// E2：seek 窗口不做 pause 冻结（保持播放），验证暂停态是否让音轨忽略 seek。
  noPause,

  /// E3 主路线候选：快退时先把外挂音轨重挂到干净状态，再做单次主 seek。
  audioPremount,

  /// E4 兜底路线候选：快退改为整体重开定位（setMedia + prepare(position)）。
  reopen,

  /// E5：快退 flags 改用 `fromStart|keyFrame|Backward`（当前为 Accurate）。
  kfBackward,

  /// E6 主路线候选：音轨前置重挂 + 不暂停（静音，让旧音频缓冲自然排空）
  /// + 解冻前轮询等待主时钟真正收敛到目标。
  converge,
}

/// Seek 取证探针（诊断专用，验证通过后整体移除）。
///
/// 开关与变体来自 `Documents/logs/seek_probe.json`：
/// ```json
/// {
///   "enabled": true,
///   "variant": "baseline",
///   "autoSeek": {
///     "enabled": true,
///     "warmupSec": 6,
///     "targetsSec": [20, 60, 25, 70, 30, 75]
///   }
/// }
/// ```
/// 每次 seek 记录一行请求、若干阶段/事件、一串 position 采样（带推进速率），
/// 最后输出结论行（`dragBack`/`catchUp`/`audioSlow`/`frameLateMs`），
/// 全部经 [SyncTrace] 同步落盘到 `Documents/logs/trace.log`。
/// `autoSeek` 打开后由播放页自动执行脚本化 seek 序列（无需人工点击）。
abstract final class SeekProbe {
  static SeekVariant variant = SeekVariant.baseline;
  static bool enabled = false;

  /// 脚本化 seek 序列：播放稳定后依次跳到这些绝对位置（秒），步间隔 4.6s。
  static bool autoSeekEnabled = false;
  static int autoSeekWarmupSec = 6;
  static List<int> autoSeekTargets = const [20, 60, 25, 70, 30, 75];
  static bool _autoStarted = false;

  /// 单会话轮数：每轮重新读取配置文件（可在应用运行中热切换 variant），
  /// 轮间隔 [roundGapSec] 秒。
  static int autoSeekRounds = 1;
  static int roundGapSec = 15;
  static int _lastConfigStamp = 0;

  /// 轮次变体序列：配置后每轮按序切换变体（一次会话跑完整矩阵，无需人工干预）。
  static List<SeekVariant> variantSequence = const [];

  /// 轮首应用序列变体（未配置序列则沿用配置文件里的 variant）。
  static void applyRoundVariant(int round) {
    if (variantSequence.isEmpty) return;
    variant = variantSequence[round % variantSequence.length];
  }

  /// 首次调用返回 true（保证自动序列在本进程内只跑一次）。
  static bool markAutoStarted() {
    if (_autoStarted) return false;
    _autoStarted = true;
    return true;
  }

  /// 快退是否使用 `KeyFrame|Backward` 定位（E5）。
  static bool get backwardKeyFrame => variant == SeekVariant.kfBackward;

  /// 快退是否走「音轨前置重挂 + 单次 seek」（E3 / E6）。
  static bool get premountAudioBeforeSeek =>
      variant == SeekVariant.audioPremount || variant == SeekVariant.converge;

  /// 快退是否走「整体重开定位」（E4）。
  static bool get reopenOnBackward => variant == SeekVariant.reopen;

  /// seek 窗口是否暂停播放（E2/E6 不暂停，改为静音让旧音频缓冲排空）。
  static bool get pauseDuringSeek =>
      variant != SeekVariant.noPause && variant != SeekVariant.converge;

  /// 是否沿用基线的「时间预算重挂舞步 + 800ms 事后自愈」（仅 E0/E1）。
  static bool get legacyRemountDance =>
      variant == SeekVariant.baseline || variant == SeekVariant.noCache;

  /// 解冻前是否轮询等待主时钟收敛到目标（E6）。
  static bool get convergeBeforeUnfreeze => variant == SeekVariant.converge;

  /// demux 包缓存范围数（E1 置 0）。
  static String get demuxBufferRanges =>
      variant == SeekVariant.noCache ? '0' : '16';

  static Future<void> init() async {
    await _loadConfig();
    SyncTrace.log(
      'SeekProbe',
      'init enabled=$enabled variant=${variant.name} '
      'autoSeek=$autoSeekEnabled warmup=$autoSeekWarmupSec '
      'targets=$autoSeekTargets rounds=$autoSeekRounds gap=$roundGapSec',
    );
  }

  /// 重新读取配置（按 mtime 去重）：应用运行中可热切换 variant / 轮数。
  static Future<void> refresh() async {
    try {
      final file = await _configFile();
      if (file == null) return;
      final stamp = file.statSync().modified.millisecondsSinceEpoch;
      if (stamp == _lastConfigStamp) return;
      await _loadConfig();
      SyncTrace.log(
        'SeekProbe',
        'config reloaded variant=${variant.name} enabled=$enabled',
      );
    } catch (_) {}
  }

  static Future<File?> _configFile() async {
    try {
      final runtime = await LoggerUtils.getRuntimeLogsPath();
      final file = File(
        '${runtime.parent.path}${Platform.pathSeparator}seek_probe.json',
      );
      return file.existsSync() ? file : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _loadConfig() async {
    try {
      final file = await _configFile();
      if (file == null) return;
      _lastConfigStamp = file.statSync().modified.millisecondsSinceEpoch;
      final raw = jsonDecode(await file.readAsString());
      if (raw is Map) {
        enabled = raw['enabled'] != false;
        final name = raw['variant']?.toString() ?? 'baseline';
        variant = SeekVariant.values.firstWhere(
          (e) => e.name == name,
          orElse: () => SeekVariant.baseline,
        );
        final auto = raw['autoSeek'];
        if (auto is Map) {
          autoSeekEnabled = auto['enabled'] == true;
          autoSeekWarmupSec =
              int.tryParse('${auto['warmupSec']}') ?? autoSeekWarmupSec;
          autoSeekRounds =
              int.tryParse('${auto['roundsPerSession']}') ?? autoSeekRounds;
          roundGapSec = int.tryParse('${auto['roundGapSec']}') ?? roundGapSec;
          final seq = auto['variantSequence'];
          if (seq is List) {
            variantSequence = seq
                .map(
                  (e) => SeekVariant.values.firstWhere(
                    (v) => v.name == '$e',
                    orElse: () => SeekVariant.baseline,
                  ),
                )
                .toList();
          }
          final targets = auto['targetsSec'];
          if (targets is List) {
            final parsed = targets
                .map((e) => int.tryParse('$e') ?? -1)
                .where((e) => e >= 0)
                .toList();
            if (parsed.isNotEmpty) autoSeekTargets = parsed;
          }
        }
      }
    } catch (_) {}
  }

  /// 自动序列：第 [round] 轮开始（variant 已在轮首刷新）。
  static void probeRound(int round) {
    SyncTrace.log(
      'SeekProbe',
      'PROBE ROUND $round variant=${variant.name}',
    );
  }

  /// 自动序列：即将执行第 [index] 步（目标 [targetMs]）。
  static void probeStep(int index, int targetMs) {
    SyncTrace.log(
      'SeekProbe',
      'PROBE step=$index/${autoSeekTargets.length} targetMs=$targetMs',
    );
  }

  /// 自动序列执行完毕。
  static void probeDone() {
    SyncTrace.log('SeekProbe', 'PROBE DONE variant=${variant.name}');
  }

  /// 媒体信息快照：音视频轨时长差决定 mdk 是否以音频时钟为主时钟
  /// （`avsync.audio.duration_diff` 默认 800ms）。
  static void mediaSnapshot({
    required int videoDurMs,
    required int audioDurMs,
    required int videoTracks,
    required int audioTracks,
    required int mediaDurMs,
  }) {
    if (!enabled) return;
    SyncTrace.log(
      'SeekProbe',
      'SEEK#$_seq MEDIA vDur=$videoDurMs aDur=$audioDurMs '
      'diff=${videoDurMs - audioDurMs} vTracks=$videoTracks '
      'aTracks=$audioTracks dur=$mediaDurMs',
    );
  }

  // ── 当前 seek 事件（单条，串行 seek 足够）──
  static final Stopwatch _clock = Stopwatch();
  static bool _active = false;
  static int _seq = 0;
  static int _targetMs = 0;
  static bool _backward = false;
  static int _deadlineMs = 0;
  static int _lastTickMs = -1000;
  static final List<int> _sampleT = [];
  static final List<int> _samplePos = [];
  static int? _seekReturnT;
  static int? _seekReturnPos;
  static int? _unfreezeT;
  static String _unfreezeReason = '-';
  static int? _firstFrameT;
  static int? _firstFrameTs;

  static int get nowMs => _clock.elapsedMilliseconds;

  /// 采样窗口：seek 派发后持续 4000ms（覆盖「解冻后拖拽/追赶」全过程）。
  static void begin({
    required int seq,
    required int targetMs,
    required int posAtRequestMs,
    required bool backward,
    required bool dualTrack,
    required bool userIntent,
    required int flags,
  }) {
    if (!enabled) return;
    if (_active) close();
    _clock
      ..reset()
      ..start();
    _active = true;
    _seq = seq;
    _targetMs = targetMs;
    _backward = backward;
    _deadlineMs = 4000;
    _lastTickMs = -1000;
    _sampleT.clear();
    _samplePos.clear();
    _seekReturnT = null;
    _seekReturnPos = null;
    _unfreezeT = null;
    _unfreezeReason = '-';
    _firstFrameT = null;
    _firstFrameTs = null;
    SyncTrace.log(
      'SeekProbe',
      'SEEK#$seq REQ variant=${variant.name} target=${targetMs}ms '
      'posAtReq=${posAtRequestMs}ms backward=${backward ? 1 : 0} '
      'dual=${dualTrack ? 1 : 0} userIntent=${userIntent ? 1 : 0} '
      'flags=$flags',
    );
  }

  static void stage(String name, [String extra = '']) {
    if (!enabled || !_active) return;
    SyncTrace.log(
      'SeekProbe',
      'SEEK#$_seq $name t=+${nowMs}ms${extra.isEmpty ? '' : ' $extra'}',
    );
  }

  static void seekReturn(
    int res, {
    required int latencyMs,
    required int posAfterMs,
    required int bufferedMs,
    required String state,
  }) {
    if (!enabled || !_active) return;
    _seekReturnT = nowMs;
    _seekReturnPos = posAfterMs;
    SyncTrace.log(
      'SeekProbe',
      'SEEK#$_seq RET res=$res latency=${latencyMs}ms '
      'posAfter=${posAfterMs}ms buffered=${bufferedMs}ms state=$state',
    );
  }

  static void event(String category, String detail, int code) {
    if (!enabled || !_active) return;
    if (category == 'render.video' && detail == '1st_frame') {
      _firstFrameT = nowMs;
      _firstFrameTs = code;
    }
    SyncTrace.log(
      'SeekProbe',
      'SEEK#$_seq EVT t=+${nowMs}ms $category/$detail code=$code',
    );
  }

  static void unfreeze(String reason) {
    if (!enabled || !_active) return;
    _unfreezeT = nowMs;
    _unfreezeReason = reason;
    SyncTrace.log('SeekProbe', 'SEEK#$_seq UNFREEZE t=+${nowMs}ms reason=$reason');
  }

  /// 轮询采样：记录 position 轨迹（100ms 节流），到期结算。
  static void tick(int posMs) {
    if (!enabled || !_active) return;
    final t = nowMs;
    if (t - _lastTickMs >= 90) {
      _lastTickMs = t;
      _sampleT.add(t);
      _samplePos.add(posMs);
    }
    if (t >= _deadlineMs) close();
  }

  static void close() {
    if (!enabled || !_active) return;
    _active = false;
    _clock.stop();

    final retT = _seekReturnT;
    var posMin = 1 << 62;
    var posMax = -(1 << 62);
    var rateMin = double.infinity;
    var rateMax = -double.infinity;
    final buf = StringBuffer();
    for (var i = 0; i < _sampleT.length; i++) {
      buf.write('+${_sampleT[i]}:${_samplePos[i]} ');
      if (retT != null && _sampleT[i] >= retT) {
        if (_samplePos[i] < posMin) posMin = _samplePos[i];
        if (_samplePos[i] > posMax) posMax = _samplePos[i];
      }
      // 300ms 滑动窗口推进速率
      for (var j = i - 1; j >= 0; j--) {
        final dt = _sampleT[i] - _sampleT[j];
        if (dt < 300) continue;
        final r = (_samplePos[i] - _samplePos[j]) / dt;
        if (r < rateMin) rateMin = r;
        if (r > rateMax) rateMax = r;
        break;
      }
    }
    final hasRange = posMin <= posMax;
    // 快退：时钟回跳旧位置表现为「跑回目标之上」；快进：表现为「落回目标之下」。
    final driftBack = hasRange &&
        (_backward
            ? posMax > _targetMs + 2500
            : posMin < _targetMs - 2500);
    final endT = _sampleT.isEmpty ? 0 : _sampleT.last;
    final endPos = _samplePos.isEmpty ? -1 : _samplePos.last;
    final settled = endPos >= 0 && (endPos - _targetMs).abs() <= 1500;
    // 末段 600ms 稳态推进速率（排除回跳瞬态）
    var steadyRate = double.nan;
    for (var i = _sampleT.length - 1; i >= 0; i--) {
      final dt = endT - _sampleT[i];
      if (dt < 600) continue;
      steadyRate = (_samplePos.last - _samplePos[i]) / dt;
      break;
    }
    final catchUp = rateMax.isFinite && rateMax >= 1.5;
    final audioSlow = rateMin.isFinite && rateMin <= 0.7;
    final frameLateMs = _firstFrameT == null
        ? -1
        : _firstFrameT! - (_unfreezeT ?? nowMs);

    SyncTrace.log('SeekProbe', 'SEEK#$_seq SAMPLES $buf');
    SyncTrace.log(
      'SeekProbe',
      'SEEK#$_seq END variant=${variant.name} target=$_targetMs '
      'backward=${_backward ? 1 : 0} posAfter=${_seekReturnPos ?? -1} '
      'posMin=${hasRange ? posMin : -1} posMax=${hasRange ? posMax : -1} '
      'endPos=$endPos settled=${settled ? 1 : 0} '
      'steadyRate=${steadyRate.isFinite ? steadyRate.toStringAsFixed(2) : '-'} '
      'rateMin=${rateMin.isFinite ? rateMin.toStringAsFixed(2) : '-'} '
      'rateMax=${rateMax.isFinite ? rateMax.toStringAsFixed(2) : '-'} '
      'unfreeze=$_unfreezeReason unfreezeT=${_unfreezeT ?? -1} '
      'firstFrameT=${_firstFrameT ?? -1} firstFrameTs=${_firstFrameTs ?? -1} '
      'frameLateMs=$frameLateMs driftBack=${driftBack ? 1 : 0} '
      'catchUp=${catchUp ? 1 : 0} audioSlow=${audioSlow ? 1 : 0}',
    );
  }
}
