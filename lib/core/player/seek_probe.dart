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

  /// 常态流监控：定位「自然播放频繁缓冲/追赶」的客观数据（停顿次数与时长、平均速率）。
  static bool monitorEnabled = false;
  static int monitorPeriodMs = 500;
  static int monitorReportSec = 5;
  static final List<int> _monT = [];
  static final List<int> _monPos = [];
  static int _monStallEpisodes = 0;
  static int _monStallMs = 0;
  static bool _monInStall = false;
  static int _monLastReportT = 0;
  static int _monBufMin = 1 << 30;
  static int _monBufMax = 0;

  /// 监控/心跳专用单调时钟。
  ///
  /// 严禁复用 [_clock]：探针秒表只在 seek 窗口内 start/stop，窗口外恒停在 ≤4000ms，
  /// 导致 `t - _monLastReportT >= 5000` 永假——2026-09-24 重播后快进事件期间
  /// MON 心跳一条未落盘，常态证据全部丢失。此处独立计时，进程内恒走。
  static final Stopwatch _monClock = Stopwatch()..start();

  /// 轮询阶段标记：由轮询回调各阶段写入，供心跳行携带（零 FFI，绝不阻塞）。
  static String _pollPhase = 'init';
  static String get pollPhase => _pollPhase;
  static void markPhase(String phase) {
    _pollPhase = phase;
  }

  static int _beatIndex = 0;
  static int _beatLastMs = -(1 << 30);

  /// 存活心跳（关键取证）：每 [monitorReportSec] 秒一行，**零 FFI 读取**
  /// （只读 ValueNotifier 缓存与控制器自身标志），且在轮询回调最前端调用，
  /// 不受任何早退分支影响。价值：日志一旦缺失心跳即可判定 UI isolate 被
  /// 同步 FFI 读取阻塞（定时器随之停止），且末条心跳的 `phase` 给出卡死前
  /// 最后完成的轮询阶段。
  static void beat({
    required bool ready,
    required bool playing,
    required bool completed,
    required bool buffering,
    required int uiPosMs,
    required int uiDurMs,
    required bool seeking,
    required bool nativeSeekInFlight,
    required int? queuedTargetMs,
    required bool userIntent,
  }) {
    if (!enabled || !monitorEnabled) return;
    final t = _monClock.elapsedMilliseconds;
    if (t - _beatLastMs < monitorReportSec * 1000) return;
    _beatLastMs = t;
    _beatIndex++;
    // 顺带结算上一窗口的采样统计（monitorTick 只采样不落盘）。
    final winT = _monLastReportT == 0 ? t : t - _monLastReportT;
    final adv = _monPos.length >= 2 ? _monPos.last - _monPos.first : 0;
    final avgRate = winT > 0 ? adv / winT : 0.0;
    SyncTrace.log(
      'SeekProbe',
      'BEAT #$_beatIndex t=+${t}ms phase=$_pollPhase '
      'uiPos=$uiPosMs uiDur=$uiDurMs '
      'ready=${ready ? 1 : 0} playing=${playing ? 1 : 0} '
      'completed=${completed ? 1 : 0} buffering=${buffering ? 1 : 0} '
      'seeking=${seeking ? 1 : 0} inFlight=${nativeSeekInFlight ? 1 : 0} '
      'queued=${queuedTargetMs ?? -1} intent=${userIntent ? 1 : 0} '
      'samples=${_monT.length} avgRate=${avgRate.toStringAsFixed(2)} '
      'stalls=$_monStallEpisodes stallMs=$_monStallMs '
      'bufMin=${_monBufMin == 1 << 30 ? -1 : _monBufMin} bufMax=$_monBufMax',
    );
    _monT.clear();
    _monPos.clear();
    _monStallEpisodes = 0;
    _monStallMs = 0;
    _monInStall = false;
    _monBufMin = 1 << 30;
    _monBufMax = 0;
    _monLastReportT = t;
  }

  /// 每 [monitorPeriodMs] 采样一次；停滞（1s 内位置推进 < 50ms）计为一次停顿。
  /// 只累计统计，不落盘（报告统一由 [beat] 输出）。
  static void monitorTick(int posMs, int bufferedMs) {
    if (!enabled || !monitorEnabled) return;
    final t = _monClock.elapsedMilliseconds;
    if (_monT.isNotEmpty && t - _monT.last < monitorPeriodMs) return;
    _monT.add(t);
    _monPos.add(posMs);
    if (bufferedMs < _monBufMin) _monBufMin = bufferedMs;
    if (bufferedMs > _monBufMax) _monBufMax = bufferedMs;
    // 停滞判定：与前 1s 前的采样比较
    if (_monT.length >= 3) {
      final back = _monT.length - 3;
      final dt = t - _monT[back];
      if (dt >= 1000) {
        final adv = posMs - _monPos[back];
        final stalled = adv < 50;
        if (stalled && !_monInStall) {
          _monInStall = true;
          _monStallEpisodes++;
        } else if (!stalled && _monInStall) {
          _monInStall = false;
        }
        if (stalled) _monStallMs += dt;
      }
    }
  }

  // ── pollTrace：逐 tick 阶段埋点（默认关，仅卡死取证期打开）──
  /// 每 tick 写 4~5 条短行 `POLL#n <stage> dt=<自本 tick 起点耗时>`：若 isolate
  /// 阻塞在某个同步 FFI 读取上，最后一条 POLL 行即直接指向卡死的那次读取，
  /// 且 dt 序列给出阻塞前的耗时恶化趋势。
  static bool pollTrace = false;
  static int pollSlowMs = 300;
  static int _pollTick = 0;
  static int _pollTickStartMs = 0;
  static int _pollSlowCount = 0;

  static void pollBegin() {
    if (!enabled) return;
    _pollTick++;
    _pollTickStartMs = _monClock.elapsedMilliseconds;
    if (!pollTrace) return;
    SyncTrace.log('SeekProbe', 'POLL#$_pollTick enter t=${_pollTickStartMs}ms');
  }

  static void pollStage(String stage, [String extra = '']) {
    if (!enabled || !pollTrace) return;
    SyncTrace.log(
      'SeekProbe',
      'POLL#$_pollTick $stage dt=${_monClock.elapsedMilliseconds - _pollTickStartMs}ms'
      '${extra.isEmpty ? '' : ' $extra'}',
    );
  }

  /// tick 结束：pollTrace 下补 done 行；无 pollTrace 时兜底记录异常慢 tick。
  static void pollEnd() {
    if (!enabled) return;
    final dt = _monClock.elapsedMilliseconds - _pollTickStartMs;
    if (dt >= pollSlowMs) {
      _pollSlowCount++;
      SyncTrace.log(
        'SeekProbe',
        'POLL#$_pollTick SLOW dt=${dt}ms count=$_pollSlowCount',
      );
    } else if (pollTrace) {
      SyncTrace.log('SeekProbe', 'POLL#$_pollTick done dt=${dt}ms');
    }
  }

  // ── RAW：常态原始读数（5s 节流；字段由控制器侧组装）──
  static int _rawLastMs = -(1 << 30);

  /// 监控采样窗口重置：seek 落地/解冻时调用，避免「回跳 + 追赶」瞬态样本混入
  /// stalls/avgRate 统计（实测落地后 1.6s 的样本仍被判为 2.8s 停顿）。
  static void resetMonitorWindow() {
    _monT.clear();
    _monPos.clear();
    _monStallEpisodes = 0;
    _monStallMs = 0;
    _monInStall = false;
    _monBufMin = 1 << 30;
    _monBufMax = 0;
  }

  /// RAW 行是否到期。供控制器在**读取底层 FFI 之前**判定，避免每 tick 多读。
  static bool rawDue() {
    if (!enabled) return false;
    return _monClock.elapsedMilliseconds - _rawLastMs >=
        monitorReportSec * 1000;
  }

  /// 写一条 RAW 行（5s 节流）：与零风险心跳互补，给出底层真实 state/status、
  /// 缓冲水位与第二实例状态。
  static void raw(String line) {
    if (!enabled) return;
    final t = _monClock.elapsedMilliseconds;
    if (t - _rawLastMs < monitorReportSec * 1000) return;
    _rawLastMs = t;
    SyncTrace.log('SeekProbe', 'RAW #$_pollTick $line');
  }

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

  /// 读缓冲上限（ms）：用于 A/B 验证缓冲水位对卡顿的影响。
  static int bufferMaxMs = 30000;

  /// seek 前是否强制重建音轨（实测会破坏音频时钟→极慢播放，默认关闭）。
  static bool flushAudioOnSeek = false;

  /// 快退是否改用「重开媒体 + 带位置打开」（第四笔方案）：mdk 的 seek 不 flush
  /// 陈旧音频队列，而带位置打开无任何陈旧队列（项目首播/续播同源路径）。
  static bool reopenOnBackwardSeek = false;

  /// MPD 单源模式：把双 CDN URL 合成一个本地 MPD 播放（验证单 timeline 是否
  /// 同时解决 seek/缓冲/追赶问题）。默认关闭，仅验证用。
  static bool manifestModeEnabled = false;

  /// 探针自由日志（与 seek 事件无关的一次性记录）。
  static void note(String message) {
    if (!enabled) return;
    SyncTrace.log('SeekProbe', message);
  }

  /// 方案 3：双实例漂移校正判定（比例控制 + 三态节流）。
  ///
  /// 2026-09-25 定因修复：旧实现把「节流期无决策」与「偏差在死区内」都返回 0，
  /// 而调用处对 0 的处理是复位 `playbackRate = 1.0` ⇒ 每次修正只生效约一个 tick
  /// （~100ms）即被复位（稳定期占空比 ~2%，等效修正 ≈0.06%）；实测偏差以
  /// ~0.78%/s 单向增长到 0.9~1.5s，随后触发硬定位（音频瞬跳 1.5~3.5s，可闻）。
  /// 现改为三态返回（record）：
  /// - `action == 2`：偏差 > [driftHardMs]，需硬定位到视频位置；
  /// - `action == 1`：按 `rate` 调整第二实例速率（比例控制，限幅 ±[maxRateDelta]）；
  /// - `action == 0`：偏差 ≤ [driftDeadZoneMs]，速率复位 1.0；
  /// - `action == -1`：**节流期，保持现状**（严禁复位速率）。
  static DateTime? _driftLastAt;

  /// 比例增益：1ms 偏差 → 0.00008 速率修正（125ms→1%，375ms 起饱和到 3% 上限）。
  /// 受底层固有 ~0.8% 速率差限制，残余偏差会稳定在死区附近而非 0。
  static const double driftGain = 0.00008;

  /// 速率修正限幅（±3%：兼顾收敛速度与听感）。
  static const double maxRateDelta = 0.03;

  /// 死区（ms）：|drift| ≤ 死区视为已对齐，速率复位。
  static const int driftDeadZoneMs = 150;

  /// 硬定位阈值（ms）。
  static const int driftHardMs = 1500;

  /// 决策周期（ms）：seek 后 3s 内 250ms 快速收敛，其后 1s 持续跟踪。
  static const int driftSeekPeriodMs = 250;
  static const int driftStablePeriodMs = 1000;

  static ({int action, double rate}) driftDecision(
    int videoPosMs,
    int audioPosMs, {
    required int sinceSeekMs,
  }) {
    if (!enabled) return (action: -1, rate: 1.0);
    final now = DateTime.now();
    final periodMs = sinceSeekMs < 3000
        ? driftSeekPeriodMs
        : driftStablePeriodMs;
    final last = _driftLastAt;
    if (last != null && now.difference(last).inMilliseconds < periodMs) {
      return (action: -1, rate: 1.0);
    }
    _driftLastAt = now;
    final drift = audioPosMs - videoPosMs;
    if (drift.abs() > driftHardMs) {
      SyncTrace.log(
        'SeekProbe',
        'DRIFT hard drift=$drift v=$videoPosMs a=$audioPosMs',
      );
      return (action: 2, rate: 1.0);
    }
    if (drift.abs() <= driftDeadZoneMs) {
      return (action: 0, rate: 1.0);
    }
    // 音频超前（drift>0）需降速，滞后（drift<0）需提速
    var rate = 1.0 - drift * driftGain;
    if (rate > 1.0 + maxRateDelta) rate = 1.0 + maxRateDelta;
    if (rate < 1.0 - maxRateDelta) rate = 1.0 - maxRateDelta;
    return (action: 1, rate: rate);
  }

  /// P0 A/B（2026-09-25）：seek 是否改「精确落点」（去掉 KeyFrame，前后向均生效）。
  /// 默认关＝保持 keyFrame 快速定位（落点落在最近关键帧，误差 -4.8s~+4.3s，观感为
  /// 「seek 到底后又回退一段」，见复盘 §8）；打开后落点准，代价是需从关键帧解码到目标。
  /// 历史实证「Accurate 在**外挂音轨/单源清单**配置下快退间歇不生效」——当前为双实例
  /// （主实例纯视频 DASH、主媒体 seek）配置，需在新配置下重新 A/B 判定。
  static bool accurateSeek = false;

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
        final mon = raw['monitor'];
        if (mon is Map) {
          monitorEnabled = mon['enabled'] == true;
          monitorPeriodMs =
              int.tryParse('${mon['periodMs']}') ?? monitorPeriodMs;
          monitorReportSec =
              int.tryParse('${mon['reportSec']}') ?? monitorReportSec;
        }
        final bufMax = int.tryParse('${raw['bufferMaxMs']}');
        if (bufMax != null && bufMax > 0) bufferMaxMs = bufMax;
        manifestModeEnabled = raw['manifestMode'] == true;
        flushAudioOnSeek = raw['flushAudioOnSeek'] == true;
        reopenOnBackwardSeek = raw['reopenOnBackwardSeek'] == true;
        pollTrace = raw['pollTrace'] == true;
        accurateSeek = raw['accurateSeek'] == true;
        final slow = int.tryParse('${raw['pollSlowMs']}');
        if (slow != null && slow > 0) pollSlowMs = slow;
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
    // 以「落点 + 真实经过时间」为期望轨迹判定漂移：
    // 正常播放 4s 窗口本来就会前进 4s，不能直接拿 posMax 与 target 比。
    // aheadMax：领先期望轨迹的最大值（快退时表现为「回跳 seek 前位置」）；
    // behindMax：落后期望轨迹的最大值（时钟卡住 / 未归位）。
    final anchor = (_seekReturnPos ?? -1) > 0 ? _seekReturnPos! : _targetMs;
    var aheadMax = 0;
    var behindMax = 0;
    for (var i = 0; i < _sampleT.length; i++) {
      if (retT == null || _sampleT[i] < retT) continue;
      final expected = anchor + (_sampleT[i] - retT);
      final over = _samplePos[i] - expected;
      if (over > aheadMax) aheadMax = over;
      if (-over > behindMax) behindMax = -over;
    }
    final driftBack = aheadMax > 1500;
    final noProgress = behindMax > 1500;
    final endT = _sampleT.isEmpty ? 0 : _sampleT.last;
    final endPos = _samplePos.isEmpty ? -1 : _samplePos.last;
    final settled = retT != null &&
        endPos >= 0 &&
        (endPos - (anchor + (endT - retT))).abs() <= 1500;
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
      'aheadMax=$aheadMax behindMax=$behindMax '
      'steadyRate=${steadyRate.isFinite ? steadyRate.toStringAsFixed(2) : '-'} '
      'rateMin=${rateMin.isFinite ? rateMin.toStringAsFixed(2) : '-'} '
      'rateMax=${rateMax.isFinite ? rateMax.toStringAsFixed(2) : '-'} '
      'unfreeze=$_unfreezeReason unfreezeT=${_unfreezeT ?? -1} '
      'firstFrameT=${_firstFrameT ?? -1} firstFrameTs=${_firstFrameTs ?? -1} '
      'frameLateMs=$frameLateMs driftBack=${driftBack ? 1 : 0} '
      'noProgress=${noProgress ? 1 : 0} '
      'catchUp=${catchUp ? 1 : 0} audioSlow=${audioSlow ? 1 : 0}',
    );
  }
}
