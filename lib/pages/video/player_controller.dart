import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:fvp/mdk.dart' as mdk;

import 'package:winwin/core/account/account.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/core/cache/play_url_cache.dart';
import 'package:winwin/core/log/sync_trace.dart';
import 'package:winwin/core/log/app_logger.dart';
import 'package:winwin/core/player/hls_manifest.dart';
import 'package:winwin/core/player/seek_probe.dart';
import 'package:winwin/core/player/sponsorblock_usecase.dart';
import 'package:winwin/core/policy/cdn_policy.dart';
import 'package:winwin/core/policy/stream_selection_policy.dart';
import 'package:winwin/core/policy/video_load_policy.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/grpc/bilibili/community/service/dm/v1.pb.dart'
    hide SubtitleItem;
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/pgc.dart';
import 'package:winwin/http/video.dart';
import 'package:winwin/models/common/audio_normalization.dart';
import 'package:winwin/models/common/video_type.dart';
import 'package:winwin/models/video/play_info.dart';
import 'package:winwin/models/video/play_url.dart';
import 'package:winwin/pages/danmaku/controller.dart';
import 'package:winwin/pages/video/subtitle_controller.dart';
import 'package:winwin/plugin/canvas_danmaku/canvas_danmaku.dart';

/// WinWin 播放器控制器（fvp / mdk 内核）。
///
/// 采用 PiliPlus 的「全局单例 mdk.Player + 引用计数」方案：
/// 多个视频详情页共享同一个 [mdk.Player] 实例，切换视频时仅在该实例上
/// 重新 `media = url` + `prepare`（与 [switchQuality] 同理），
/// 从根本上避免两个 Player 实例并存导致的资源冲突。
///
/// 引用计数 [_playerCount] 管理单例生命周期：每个 controller 构造时递增，
/// dispose 时递减，归零时才真正释放 [mdk.Player]。
///
/// 对外暴露的 ValueNotifier 供 [PlayerPanel] 及详情页 UI 监听。
/// 渲染面：mdk 将解码帧注册为 Flutter Texture，面板监听
/// [textureId] 拿到 id 后用 `Texture(textureId:)` 绘制，
/// [videoSize] 用于保持视频帧宽高比（等效 BoxFit.contain）。
class WinWinPlayerController {
  WinWinPlayerController({
    required this.bvid,
    required this.cid,
    this.epId,
    this.seasonId,
    this.seasonType,
  }) : volume = ValueNotifier(Pref.desktopVolume) {
    _playerCount++;
    _sharedPlayer ??= _createPlayer();
    initDanmaku();
    attachListeners(); // 内部启动轮询（_startPolling）
  }

  final String bvid;
  final int cid;
  final int? epId;
  final int? seasonId;
  final int? seasonType;

  /// 是否为番剧 / 影视（PGC）播放。
  bool get isBangumi => epId != null && epId! > 0;

  /// 当前播放流的业务类型。
  VideoType get videoType => isBangumi ? VideoType.pgc : VideoType.ugc;

  /// 稿件 avid（由详情页 load 完成后设置，供心跳上报使用）。
  int? aid;

  // ── 全局单例 mdk 播放器（跨页面共享，参照 PiliPlus PlPlayerController）──
  static mdk.Player? _sharedPlayer;
  static int _playerCount = 0;

  /// 方案 3 最小验证（docs 2.9）：第二实例专放音轨——视频/音频各自都是
  /// 「主媒体 seek」（本项目实测唯一可靠的 seek 路径）。验证期硬编码开启，
  /// 回退 = 回滚到本笔之前的快照。
  static mdk.Player? _audioPlayer;
  static const bool _dualPlayerAudio = true;

  /// 共享 player 延迟销毁时长：等引擎光栅线程排空对视频纹理的合成，
  /// 避开 fvp ReleaseRT 立即销毁纹理对象与光栅并发的崩溃竞态（见 dispose）。
  static const Duration _sharedTeardownDelay = Duration(milliseconds: 400);

  /// 当前 controller 访问的播放器（即全局单例）。
  mdk.Player? get _player => _sharedPlayer;

  // ── 对外状态（ValueNotifier）──
  final ValueNotifier<bool> playing = ValueNotifier(false);
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> duration = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> buffered = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> seekPosition = ValueNotifier(Duration.zero);
  final ValueNotifier<bool> buffering = ValueNotifier(false);
  final ValueNotifier<String?> error = ValueNotifier(null);
  final ValueNotifier<bool> ready = ValueNotifier(false);
  final ValueNotifier<double> volume;

  /// 视频播放是否已自然结束（到达片尾）。
  final ValueNotifier<bool> completed = ValueNotifier(false);
  bool get isCompleted => completed.value;

  /// 当前显示/交互进度：若正在 seek 或拖动，返回 seekPosition，否则返回 position。
  Duration get currentProgress =>
      _isSeeking ? seekPosition.value : position.value;

  /// mdk 注册的 Flutter Texture id，供面板 `Texture(textureId:)` 渲染。
  /// 首帧就绪前 / 画质切换重建纹理期间为 null。
  final ValueNotifier<int?> textureId = ValueNotifier(null);

  /// 视频帧尺寸（含像素宽高比修正），供面板按宽高比显示。
  final ValueNotifier<ui.Size?> videoSize = ValueNotifier(null);

  /// 当前播放倍速（1.0 为原速）。
  final ValueNotifier<double> playbackSpeed = ValueNotifier(1.0);

  /// 画质列表版本号：每次 `_playUrl` 赋值后递增，供面板重建画质按钮。
  final ValueNotifier<int> qualityVersion = ValueNotifier(0);

  /// 上一次生效的倍速，用于弹幕时长联动（先乘旧倍速还原基准再除新倍速）。
  double _lastPlaybackSpeed = 1.0;

  /// seek 计数器：弹幕层监听后清空画面上的弹幕。
  final ValueNotifier<int> seekCount = ValueNotifier(0);

  /// seek 执行状态：用于在底层 seek 期间抑制轮询覆盖进度，杜绝进度条跳变回弹。
  int _seekSeq = 0;
  bool _isSeeking = false;
  int? _seekTargetMs;
  DateTime? _seekStartTime;
  bool get isSeeking => _isSeeking;
  int? get seekTargetMs => _seekTargetMs;

  /// 当前是否有底层 native player.seek 正在执行（串行化防并发，根除 fvp Completer 错位）。
  bool _nativeSeekInFlight = false;

  /// 排队等待执行的最新 Seek 目标时间戳（毫秒）。
  int? _queuedSeekTargetMs;

  /// 双轨快退的外部音轨重挂窗口标志：窗口内底层存在时钟「跳回」瞬态的
  /// 锁竞争风险（2026-09-20 00:11 死锁实证），期间禁止同步 FFI 读取 position。
  bool _audioRemountInFlight = false;

  /// 取证变体 E2 的冻结期静音标志：解冻时恢复。
  bool _seekWindowMuted = false;

  /// 最近一次底层 native seek 完成返回的时间点，用于保障观察期平滑结算。
  DateTime? _nativeSeekDoneTime;

  /// 短时连续快速 Seek 请求防抖合并定时器（35ms）。
  Timer? _seekDebounceTimer;

  /// 外部拖动开始（对标 PiliPlus onSeekStart）
  void onSeekStart(int seekFromMs) {
    _isSeeking = true;
    _seekTargetMs = seekFromMs;
    _seekStartTime = DateTime.now();
    seekPosition.value = Duration(milliseconds: seekFromMs);
  }

  /// 外部拖动更新（对标 PiliPlus onDragUpdate）
  void onSeekUpdate(int seekToMs) {
    _seekTargetMs = seekToMs;
    seekPosition.value = Duration(milliseconds: seekToMs);
  }

  /// 外部拖动结束（对标 PiliPlus onSeekEnd）
  void onSeekEnd() {
    // 保持锁定，由底层 seek 实际出帧结算或超时看门狗解除
  }

  /// 弹幕重建信号：didPopNext 返回本页时 ++，WinWinDanmaku 监听后重建
  /// dm（清空旧缓存重新拉取）+ clear 引擎 + 重置去重标记。等效于 PiliPlus
  /// 的 videoState 卸载-重建 PlDanmaku，但不需要销毁 DanmakuScreen（避免
  /// 引擎闪烁）。原因：PlayerPanel 始终挂载，WinWinDanmaku 不会随路由重建，
  /// 导致弹幕引擎在 pause/resume 后状态僵死，弹幕无法恢复。
  final ValueNotifier<int> danmakuReloadSignal = ValueNotifier(0);

  /// 可选倍速列表（来自 Pref.speedList）。
  List<double> get speedList => Pref.speedList;

  /// 弹幕数据控制器，生命周期绑定当前 cid 会话。
  WinWinDanmakuController? danmaku;

  /// 初始化或获取弹幕数据控制器（若已存在且未释放则直接返回，否则重新创建并预载）。
  WinWinDanmakuController getOrCreateDanmaku() {
    final dm = danmaku;
    if (dm != null && !dm.isDisposed) {
      return dm;
    }
    return initDanmaku();
  }

  /// 强制重新初始化弹幕数据控制器并异步预加载。
  WinWinDanmakuController initDanmaku() {
    danmaku?.dispose();
    final dm = WinWinDanmakuController(cid: cid);
    danmaku = dm;
    unawaited(dm.preload());
    return dm;
  }

  /// 弹幕渲染引擎控制器，由 DanmakuScreen 的 createdController 回调赋值。
  DanmakuController<DanmakuElem>? danmakuEngine;

  /// SponsorBlock 用例：段落加载 + 自动跳过。
  /// 由 [load] 完成后异步初始化；null 表示未启用或加载失败。
  SponsorBlockUseCase? sponsorBlock;

  /// 字幕控制器（Phase 4.4）：字幕加载、解析、当前行查找。
  /// 由 [setSubtitleList] 初始化可用列表后自动选择默认字幕。
  final SubtitleController subtitle = SubtitleController();

  /// 章节标记列表（Phase 4.5，来自 playInfo view_points）。
  /// 由 [setViewPoints] 设置，供面板在进度条与章节面板中渲染。
  final ValueNotifier<List<ViewPoint>> viewPointsNotifier = ValueNotifier(
    const [],
  );
  List<ViewPoint> get viewPoints => viewPointsNotifier.value;

  /// 是否启用 SponsorBlock 自动跳过（默认 true，用户可在设置中关闭）。
  bool sponsorBlockEnabled = Pref.enableSponsorBlock;

  /// 弹幕显示不透明度（0-1）：设置面板改动时写入，弹幕层监听实时刷新。
  final ValueNotifier<double> danmakuOpacity = ValueNotifier(
    Pref.danmakuOpacity,
  );

  // ── 清晰度状态 ──
  PlayUrlModel? _playUrl;
  int _currentQn = 80;

  /// 当前是否为首次加载（用于 HDR 自动升级判定）。
  bool _isInitialLoad = true;

  // 请求头：Referer + PC User-Agent（经 mdk 'avio.headers' 属性下发）。
  static const String _referer = 'https://www.bilibili.com';
  static const String _pcUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _pollTimer;
  Timer? _bufferingDebounceTimer;
  bool _disposed = false;

  /// 是否已被销毁（公开访问器，供 UI 层检查）。
  bool get disposed => _disposed;

  /// 是否正在加载/切换 media：为 true 时忽略 onEvent 的 error 事件，
  /// 避免旧 media 卸载产生的错误事件污染 [error]（真正的失败由 prepare
  /// 返回值 < 0 判断）。
  bool _loading = false;

  /// 待恢复的进度：prepare 返回 -1（already loading）时无法立即 seek，
  /// 暂存到此字段，等 onMediaStatus.buffered 事件触发后 seek。
  Duration? _pendingSeek;

  /// 待触发的 HDR 自动升级：首播 SDR 后延后到 media buffered 稳定再二次
  /// 拉流 qn=125，避免与首播的 setMedia/prepare/纹理创建并发竞态。
  PlayUrlModel? _pendingHdrUpgrade;

  /// 会话级连续已缓冲最大毫秒数：在换视频/换清晰度/重播时重置为 0。
  /// 用于单调覆盖保障，防止快退 seek 或解码器刷新导致明明已经缓冲过的进度条向左坍塌缩短。
  int _maxContinuousBufferedMs = 0;

  /// 缓冲假死计时（毫秒），用于超时检测与自愈。
  int _bufferingStallMs = 0;

  /// 用户意图播放标志（playWhenReady）：与底层瞬态解码器 playing 状态解耦。
  /// 用户点击暂停时为 false，起播/恢复时为 true。用于看门狗准确判定卡死。
  bool _userIntentPlaying = true;

  /// 上次轮询到的播放进度（毫秒），用于检测进度是否停滞。
  int _lastPolledPosMs = -1;

  /// 最近一次 Seek 实际完成返回的时间点，用于在 Seek 后短时间内屏蔽看门狗误重载。
  DateTime? _lastSeekFinishTime;

  /// 是否正在执行卡顿自愈（防重入）。
  bool _isRecovering = false;

  /// 连续自愈失败重试计数。
  int _stallRecoveryRetryCount = 0;

  /// 视频可用 CDN 候选 URL 列表（已过滤 MCDN/PCDN）。
  List<String> _videoCdnCandidates = const [];

  /// 音频可用 CDN 候选 URL 列表（已过滤 MCDN/PCDN）。
  List<String> _audioCdnCandidates = const [];

  /// 当前正在使用的 CDN 候选下标。
  int _currentCdnIndex = 0;

  /// 当前生效的视频播放直链。
  String? _currentVideoUrl;

  /// 当前生效的音频播放直链。
  String? _currentAudioUrl;

  // ── 心跳上报（Phase 4.2 & PGC/番剧支持）──
  /// 心跳定时器：每 5 秒上报一次播放进度。
  Timer? _heartBeatTimer;

  /// 上次心跳上报时的播放状态，用于检测状态变化。
  /// null 表示尚未上报过任何心跳（首次状态变化报 play_type=0）。
  bool? _lastHeartBeatPlaying;

  /// 上次上报心跳时的播放进度（秒），用于计算推进增量。
  int _lastHeartBeatPosSec = -1;

  /// 累计播放时长（秒），用于满足 "playing ≥5s" 触发条件。
  int _playingAccumSec = 0;

  /// 是否已上报过结束（play_type=3/progressSec=-1），避免重复。
  bool _reportedEnd = false;

  /// 清晰度标签列表（PlayUrlModel.acceptDescription）。
  List<String> get qualityLabels => _playUrl?.acceptDescription ?? const [];

  /// 当前清晰度 qn 在 acceptQuality 中的下标。
  int get currentQualityIndex {
    final accept = _playUrl?.acceptQuality;
    if (accept == null || accept.isEmpty) return 0;
    final idx = accept.indexOf(_currentQn);
    return idx < 0 ? 0 : idx;
  }

  /// 创建全局共享的 mdk.Player（仅属性配置，监听器由 [_attachListeners] 挂载）。
  mdk.Player _createPlayer() {
    final player = mdk.Player();

    // 显式设置 video decoders（完整对齐 fvp video_player_mdk.dart Windows 推荐配置）。
    // Windows 平台首选 Microsoft 原生 Media Foundation Transform D3D11 硬解（MFT:d3d=11），
    // 其次使用 Direct3D 11 (D3D11)、DXVA、CUDA，若用户关闭硬解则仅使用纯软解。
    if (Pref.enableHA) {
      player.videoDecoders = const [
        'MFT:d3d=11',
        'D3D11',
        'DXVA',
        'CUDA',
        'hap',
        'FFmpeg',
        'dav1d',
      ];
      player.setProperty('video.decoder', 'shader_resource=0');
    } else {
      player.videoDecoders = const ['FFmpeg', 'dav1d'];
      player.setProperty('video.decoder', 'shader_resource=0');
    }
    player.setProperty('avformat.strict', 'experimental');
    player.setProperty('avformat.safe', '0');
    player.setProperty('avformat.rtsp_transport', 'tcp');
    player.setProperty('avformat.extension_picky', '0');
    player.setProperty('avformat.allowed_segment_extensions', 'ALL');

    // 网络流断线自动重连与超时配置（对齐 fvp 官方 video_player_mdk.dart）：
    // B站 CDN 在客户端由于缓冲满暂停读取时可能在 60s 左右主动切断连接。
    // avio.reconnect: 遇断开自动发起新 Range 请求重连。
    // reconnect_on_network_error: 偶发网络波动或丢包时重试。
    // reconnect_on_http_error: 瞬态 4xx/5xx 错误时重试。
    // avio.timeout / avio.rw_timeout: FFmpeg 设置 5s 超时防死锁（微秒），加快弱网及死链逃生自愈。
    // 注意：严禁开启 avio.reconnect_streamed 与 reconnect_at_eof，两者专用于不可 seek 的直播流，
    // 会导致点播快退时 FFmpeg 误判流类型而拒绝发送精准 HTTP Range 偏移，造成网络停滞！
    player.setProperty('avio.reconnect', '1');
    player.setProperty('avio.reconnect_delay_max', '5');
    player.setProperty('avio.reconnect_on_network_error', '1');
    player.setProperty('avio.reconnect_on_http_error', '4xx,5xx');
    player.setProperty('avio.timeout', '5000000');
    player.setProperty('avio.rw_timeout', '5000000');

    // 音画同步（A/V Sync）配置，依据 MDK 官方 Global-Options 文档（wiki/Global-Options）：
    // - avsync.audio.adaptive 保持默认 0（不启用）：实测（2026-09-20 实机复测）该选项在
    //   视频落后（含网络缓冲停顿）时主动放慢音频，玩家可听到明显「慢放」异响；且 09-19
    //   的 A/B 取证已确认它对 seek 时钟不归位无根治作用（仅放大现象，B 组 rate≈0.53x），
    //   故关闭，交由播放器默认同步策略 + 后续 seek 时钟归位修复处理。
    // - avsync.audio.duration_diff 保持默认 800ms（音视频时长差 ≤800ms 时才以音频时钟为主）。
    // 注意：早期使用的字符串属性 avsync.audio='true' 会在 mdk 0.38.0 解析时抛
    // std::invalid_argument 导致 Release 必崩（见 docs/进入视频播放页崩溃根因与修复.md），
    // 已废弃；此处使用官方 int32 全局选项（与 d3d11.sync.cpu 同路径，无崩溃风险）。
    mdk.setGlobalOption('avsync.audio.adaptive', 0);

    // 读缓冲水位：MDK 官方明确「maxMs 越大越好，不影响延迟」（默认 1000/4000ms）。
    // 实测（2026-09-20）默认水位下自然播放与 seek 后均易因缓冲耗尽停顿（mdk 缓冲期会
    // 暂停主时钟，观感为长时间卡住 + 音频异常），故把预留量提高到 30s，用内存换停顿时长
    // 与频率；min 保持 1000ms（缓冲恢复判据，过大会拉长每次停顿后的恢复等待）。
    player.setBufferRange(min: 1000, max: SeekProbe.bufferMaxMs);

    if (kDebugMode) {
      // ===== 音画同步 Seek 取证（临时，取证结束后移除）=====
      // 转发 MDK 内部日志（播放状态 position/fps/cache 等）到 Debug 控制台
      // （仅 flutter run 可见，不落盘避免污染 runtime.log）。
      mdk.setLogHandler((level, msg) {
        debugPrint('[MDK:$level] $msg');
      });
      mdk.setGlobalOption('log', mdk.LogLevel.warning);
      mdk.setGlobalOption('log.status', 2);
      // ==================================================
    }

    // 启用解复用器包缓存（MDK 官方推荐 ranges=16）：
    // 允许在内存中缓存解复用后的物理数据包。当向后或向前短距离 Seek 时，
    // 解复用器直接从内存命中历史包，无需发起网络 Range 请求，大幅加速出帧并杜绝转圈。
    player.setProperty('demux.buffer.ranges', SeekProbe.demuxBufferRanges);
    player.setProperty('demux.buffer.protocols', 'http,https');

    // Windows 平台开启 D3D11 CPU-GPU 纹理同步屏障，杜绝 Flutter Texture 渲染表面的时序撕裂与新旧画面闪烁
    if (Platform.isWindows) {
      mdk.setGlobalOption('d3d11.sync.cpu', 1);
    }

    // 保持底层播放内核在视频播放完毕后不释放资源（对标 MDK 官方 keep_open 规范）：
    // 默认 keep_open=0 时，播放完毕 MDK 会自动调用 set(State::Stopped) 释放解码器和渲染管线，
    // 导致底层状态被销毁、seek(0) 报错（-3 Unloaded / -6 NotReady）且无法重新拉流。
    // 设置 keep_open=1 时，播放完毕自动转入 State::Paused 并置位 MediaStatus.end，
    // 保持解码器与网络上下文活跃，确保重播与 seek(0) 秒开且零死锁，
    // 且 EOS 时 position 自然收敛到总时长，进度条能走到头。
    // 注：本次崩溃排查（docs/进入视频播放页崩溃根因与修复.md）已证实 keep_open='1' 为数值
    // 字符串，不触发 mdk 0.38.0 的非数值解析崩溃（肇事属性是 avsync.audio，已废弃），
    // 故在此安全恢复。
    player.setProperty('keep_open', '1');

    final initialFilter = AudioNormalization.parse(
      null,
      AudioNormalization.getParamFromConfig(Pref.audioNormalization),
    );
    if (initialFilter.isNotEmpty) {
      player.setProperty('audio.avfilter', initialFilter);
    }

    player.volume = volume.value / 100.0;
    return player;
  }

  /// 创建第二实例（纯音频轨）并挂状态/媒体状态取证监听。
  ///
  /// 生命周期与全局静态实例一致（首次进入双播放器模式时创建），监听常驻：
  /// 2026-09-24 事件中第二实例全程零埋点，无法判断其 EOS/暂停是否参与了误判。
  mdk.Player _createAudioPlayer() {
    final p = mdk.Player();
    p.onStateChanged.listen((event) {
      SeekProbe.note(
        'AUDIO state ${event.oldValue} -> ${event.newValue}',
      );
    });
    p.onMediaStatus.listen((event) {
      SeekProbe.note(
        'AUDIO status ${event.oldValue} -> ${event.newValue}',
      );
    });
    SeekProbe.note('AUDIO instance created');
    return p;
  }

  /// 视频播放自然结束统一收敛处理（对标 PiliPlus stream.completed & BiliPai STATE_ENDED）。
  ///
  /// [source] 记录触发源，便于回溯误判来源（四个调用点：mediaStatus.end /
  /// statePaused / pollNearEnd / stallRecovery）。
  ///
  /// 片尾位置门控（2026-09-24 事件修复）：mdk 会在 seek、预读触达流末尾等
  /// **非自然播完**场景瞬时置位 `MediaStatus.end`（实证：2026-09-24T23:09:06
  /// 一次普通前进 seek 中即出现 `buffered+seeking → buffered+end`）。若不校验
  /// 位置，这种瞬态信号会把进度归一到片尾 + 置 completed + 暂停播放器，观感
  /// 即「视频瞬间回到播放完毕/重播态」。故位置不在片尾（< 时长-1500ms）时
  /// 只落取证行、绝不改状态、绝不暂停播放。
  void _handlePlaybackEnded({required String source}) {
    if (_disposed) return;
    // Seek 执行期间底层 PTS 与解码器状态瞬态刷新，严禁误判播放完毕，彻底消灭重播态/暂停态跳变
    if (_isSeeking || _nativeSeekInFlight || _queuedSeekTargetMs != null) {
      return;
    }
    if (completed.value) return;
    final p = _player;
    final durMs = duration.value.inMilliseconds;
    final rawPosMs = p?.position ?? position.value.inMilliseconds;
    if (durMs <= 0 || rawPosMs < durMs - 1500) {
      SeekProbe.note(
        'FAKE-END source=$source pos=$rawPosMs dur=$durMs '
        'status=${p?.mediaStatus} state=${p?.state} '
        'playing=${playing.value ? 1 : 0} seek=${_isSeeking ? 1 : 0} '
        'inFlight=${_nativeSeekInFlight ? 1 : 0} '
        'queued=${_queuedSeekTargetMs ?? -1}',
      );
      return;
    }
    completed.value = true;
    playing.value = false;
    buffering.value = false;
    // 完成态进度归一：受音画微差影响，底层 PTS 可能停在总时长之前（音频先播完、
    // 视频后到位），将 position 收敛到 duration，保证进度条与时间显示走到头
    // （与主流播放器 EOS 显示行为一致；轮询侧已做 completed 冻结防回拖）。
    if (position.value.inMilliseconds < durMs) {
      position.value = Duration(milliseconds: durMs);
    }
    _userIntentPlaying = false;
    _bufferingStallMs = 0;
    _maybeReportPlaybackEnd();
    if (p != null && p.state == mdk.PlaybackState.playing) {
      p.state = mdk.PlaybackState.paused;
    }
    SeekProbe.note(
      'ENDED source=$source pos=$rawPosMs dur=$durMs state=${p?.state}',
    );
    AppLogger.w(
      'PlayerController',
      'Playback completed ($source) at ${rawPosMs}ms/$durMs ms',
    );
  }

  /// 将本 controller 的事件监听挂载到共享 [_sharedPlayer]。
  /// 每个 controller 实例持有自己的订阅，dispose 时由 [detachListeners] 移除。
  /// 供页面 [RouteAware.didPopNext] 重新挂载（参照 PiliPlus addStatusLister）。
  void attachListeners() {
    final player = _sharedPlayer;
    if (player == null) return;
    _subscriptions
      ..add(
        player.onStateChanged.listen((event) {
          if (_disposed) return;
          final isPlaying = event.newValue == mdk.PlaybackState.playing;
          // 取证：播放器状态变迁全量落盘（不受 seek 探针窗口限制；零额外 FFI 读取）
          SeekProbe.note(
            'STATE ${event.oldValue} -> ${event.newValue} '
            'uiPos=${position.value.inMilliseconds} '
            'playing=${playing.value ? 1 : 0} '
            'completed=${completed.value ? 1 : 0} seek=${_isSeeking ? 1 : 0} '
            'inFlight=${_nativeSeekInFlight ? 1 : 0} '
            'queued=${_queuedSeekTargetMs ?? -1} '
            'intent=${_userIntentPlaying ? 1 : 0}',
          );
          // 方案 3 最小验证：播放/暂停镜像到音频实例（冻结窗口内的内部 paused
          // 也会同步给音频实例，两侧行为保持一致）。
          final ap0 = _audioPlayer;
          if (ap0 != null) {
            try {
              if (isPlaying && ap0.state != mdk.PlaybackState.playing) {
                ap0.state = mdk.PlaybackState.playing;
              } else if (!isPlaying &&
                  ap0.state == mdk.PlaybackState.playing) {
                ap0.state = mdk.PlaybackState.paused;
              }
            } catch (_) {}
          }
          // pause-during-seek 冻结窗口：seek 流程内部切换的 paused 态不向 UI 广播
          // （播放按钮/弹幕保持播放中，加载态由 buffering 转圈承载），seek 结束统一恢复。
          // 若用户在冻结窗口内主动暂停（_userIntentPlaying=false），则正常广播暂停态。
          final inSeekFreeze =
              _isSeeking || _nativeSeekInFlight || _queuedSeekTargetMs != null;
          if (isPlaying || !inSeekFreeze || !_userIntentPlaying) {
            playing.value = isPlaying;
          }
          if (isPlaying) {
            completed.value = false;
          } else if (event.newValue == mdk.PlaybackState.stopped ||
              event.newValue == mdk.PlaybackState.paused) {
            if (inSeekFreeze) {
              return;
            }
            // 播放器到达流末尾自然停止（keep_open=1 时 MDK 在所有帧渲染完成后转入 paused，keep_open=0 时转入 stopped）
            final durMs = duration.value.inMilliseconds;
            final posMs = player.position;
            if (!_loading &&
                ready.value &&
                durMs > 0 &&
                posMs >= durMs - 1500) {
              _handlePlaybackEnded(source: 'statePaused');
            } else {
              // 取证：暂停/停止事件被片尾门控拒绝（用于回溯「暂停但不该判完成」的场景）
              SeekProbe.note(
                'STATE-STOP-NOTEND pos=$posMs dur=$durMs '
                'loading=${_loading ? 1 : 0} ready=${ready.value ? 1 : 0}',
              );
            }
          }
        }),
      )
      ..add(
        player.onEvent.listen((ev) {
          if (_disposed || _loading || _isRecovering) return;
          // 取证：关键事件（含 render.video/1st_frame = 视频首帧上屏时刻）
          SeekProbe.event(ev.category, ev.detail, ev.error);
          // 取证：视频解码/渲染相关事件常开记录（判定是否存在「每次 seek 都触发」的信号）
          if (ev.category == 'render.video' ||
              ev.category == 'video' ||
              ev.category == 'decoder.video') {
            SeekProbe.note(
              'EVT ${ev.category}/${ev.detail} code=${ev.error}',
            );
          }
          // NOTE: for 'reader.buffering' the error field is progress [0,100],
          // not an error code; real mdk failures carry negative codes.
          // -1 语义同 prepare 的 -1（already loading/open），不是硬错误：
          // 共享 player 切换 media 时 setMedia 已触发 open，onEvent "open" 返回 -1
          // 表示"已在加载"。仅对 < -1 的硬错误报错（与 prepare 判断一致）。
          if (ev.error < -1) {
            AppLogger.e(
              'PlayerController',
              'onEvent error: code=${ev.error} detail=${ev.detail}',
            );
            // 参照 BiliPai PlayerErrorRecoveryPolicy：网络断开/错误时优先触发自愈重连或切线，
            // 而非直接向用户弹窗中断播放。
            if (ready.value &&
                _userIntentPlaying &&
                _stallRecoveryRetryCount < 3) {
              AppLogger.w(
                'PlayerController',
                'Triggering stream self-healing after onEvent error',
              );
              unawaited(_recoverStalledStream(isNetworkError: true));
              return;
            }
            error.value = '播放错误 ${ev.error}: ${ev.detail}';
          }
        }),
      )
      ..add(
        player.onMediaStatus.listen((event) {
          if (_disposed) return;
          final oldValue = event.oldValue;
          final newValue = event.newValue;
          SeekProbe.event('mediastatus', '$oldValue -> $newValue', 0);
          // 取证：媒体状态变迁全量落盘（不受 seek 探针窗口限制）。`end` 位在本项目
          // 存在「seek 中瞬时置位」现象（2026-09-24 实证），必须全量留痕才能回溯。
          SeekProbe.note(
            'STATUS $oldValue -> $newValue '
            'uiPos=${position.value.inMilliseconds} '
            'dur=${duration.value.inMilliseconds} '
            'playing=${playing.value ? 1 : 0} '
            'completed=${completed.value ? 1 : 0} seek=${_isSeeking ? 1 : 0} '
            'inFlight=${_nativeSeekInFlight ? 1 : 0} '
            'queued=${_queuedSeekTargetMs ?? -1}',
          );

          // 监听流结束标志（keep_open=1 下 MDK 置位 MediaStatus.end）
          if (!oldValue.test(mdk.MediaStatus.end) &&
              newValue.test(mdk.MediaStatus.end)) {
            if (!_isSeeking &&
                !_nativeSeekInFlight &&
                _queuedSeekTargetMs == null) {
              _handlePlaybackEnded(source: 'mediaStatus.end');
            } else {
              // 冻结窗口内置位：属 seek 瞬态，忽略（位置门控在 _handlePlaybackEnded 内二次把关）
              SeekProbe.note('END-FLIP-IN-SEEKWINDOW (ignored)');
            }
          }

          // 缓冲中 / 缓冲完成（监听 stalled 标志，对标 mdk stalled 解码空仓状态与 buffered 就绪状态）。
          // 防抖保护：Seek 瞬间底层必然产生几十毫秒的瞬态空仓，引入 350ms 防抖门限，
          // 彻底杜绝菊花转圈在屏幕中央瞬时闪烁。
          final wasStalled = oldValue.test(mdk.MediaStatus.stalled);
          final isStalled = newValue.test(mdk.MediaStatus.stalled);
          if (!wasStalled && isStalled) {
            if (!completed.value && !_isSeeking) {
              _bufferingDebounceTimer?.cancel();
              _bufferingDebounceTimer = Timer(
                const Duration(milliseconds: 350),
                () {
                  if (!_disposed && !completed.value && !_isSeeking) {
                    buffering.value = true;
                  }
                },
              );
            }
          } else if (!isStalled && wasStalled) {
            _bufferingDebounceTimer?.cancel();
            buffering.value = false;
            _bufferingStallMs = 0;
          }
          if (!oldValue.test(mdk.MediaStatus.buffered) &&
              newValue.test(mdk.MediaStatus.buffered)) {
            _bufferingDebounceTimer?.cancel();
            buffering.value = false;
            _bufferingStallMs = 0;
            _stallRecoveryRetryCount = 0;
            AppLogger.i(
              'PlayerController',
              'onMediaStatus: buffered (duration=${player.mediaInfo.duration}ms)',
            );
            // media 加载完成：获取正确的 duration 和 videoSize。
            // 避免切换 media 时拿到旧 media 的值（B 的 duration 比 A 长，
            // 导致时间轴超出 A 的长度）。
            final ms = player.mediaInfo.duration;
            if (ms > 0) duration.value = Duration(milliseconds: ms);
            unawaited(
              player.textureSize.then((size) {
                if (!_disposed && size != null) videoSize.value = size;
              }),
            );
            // 处理待恢复的进度：prepare 返回 -1 时无法立即 seek，
            // 暂存到此；media buffered 后 seek 生效。
            final pending = _pendingSeek;
            if (pending != null && pending > Duration.zero) {
              _pendingSeek = null;
              unawaited(player.seek(position: pending.inMilliseconds));
            }
            // 触发待执行的 HDR 自动升级：首播 SDR buffered 稳定后再二次拉流，
            // 避免与首播的 setMedia/prepare/纹理创建并发竞态。
            final pendingHdr = _pendingHdrUpgrade;
            if (pendingHdr != null) {
              _pendingHdrUpgrade = null;
              unawaited(_maybeUpgradeToHdr(pendingHdr));
            }
          }
          // NOTE: 切换 media 时旧 media 会触发 invalid 状态，这是正常行为而非
          // 真正的加载失败。真正的加载失败由 prepare() 返回值 < 0 判断并设置
          // error，此处不再因 invalid 事件误报错误（参照 PiliPlus 不依赖
          // media status invalid 设 error 的做法）。
        }),
      );
    // mdk 内部 updateTexture() 会更新 player.textureId，镜像到对外 notifier。
    player.textureId.addListener(_syncTextureId);
    // 复用单例时 texture 可能已存在，立即同步一次。
    textureId.value = player.textureId.value;
    // 启动轮询：didPopNext 重新挂载监听后恢复 position/duration 同步。
    // detachListeners 时会暂停，避免页面不可见时持续写入 position
    // （会把共享 player 播放 B 视频的进度写入 A 页面 controller，污染状态）。
    _startPolling();
    // Phase 4.2：didPopNext 返回本页时恢复心跳上报（仅当播放器已就绪）。
    if (ready.value) _startHeartBeat();
  }

  /// 移除本 controller 的事件监听（不释放共享 player）。
  /// 供页面 [RouteAware.didPushNext] 移除监听，避免旧页面被新 media 的事件
  /// 污染（参照 PiliPlus removeStatusLister / removePositionListener）。
  void detachListeners() {
    _sharedPlayer?.textureId.removeListener(_syncTextureId);
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    // 暂停轮询：didPushNext 后页面不可见，停止 position/duration 轮询，
    // 避免把共享 player（正在播 B 视频）的进度写入本 controller（A 页面）。
    _pollTimer?.cancel();
    _pollTimer = null;
    // 暂停心跳：页面不可见时停止上报，避免把共享 player 的进度误报为本页进度。
    _heartBeatTimer?.cancel();
    _heartBeatTimer = null;
    _bufferingStallMs = 0;
    _isSeeking = false;
    _seekTargetMs = null;
    _seekStartTime = null;
    _lastSeekFinishTime = null;
    // 方案 3：页面不可见时同步第二实例；退出（dispose）则直接停止，杜绝声音残留。
    final apDetach = _audioPlayer;
    if (apDetach != null) {
      try {
        apDetach.state = _disposed
            ? mdk.PlaybackState.stopped
            : mdk.PlaybackState.paused;
      } catch (_) {}
    }
    if (_seekWindowMuted) {
      _sharedPlayer?.mute = false;
      _seekWindowMuted = false;
    }
  }

  void _syncTextureId() {
    final player = _player;
    if (_disposed || player == null) return;
    textureId.value = player.textureId.value;
  }

  /// mdk 没有 position/duration 流，用 100ms 轮询更新 ValueNotifier。
  /// 100ms 轮询使进度条指示器更丝滑，并与弹幕分桶时间精确吻合。
  /// duration 不在此获取：切换 media 时 mediaInfo.duration 可能返回旧值
  /// （B 的 duration 比 A 长，导致时间轴超出 A 的长度）。duration 改为
  /// 在 onMediaStatus.buffered 事件中获取，确保是新 media 的值。
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      // 存活心跳（关键取证）：置于最前端、零 FFI 读取，任何早退分支都不影响其
      // 落盘。心跳一断即证明 UI isolate 被同步 FFI 读取阻塞（定时器随之停摆），
      // 末条心跳的 phase 直接指向卡死前最后完成的轮询阶段。
      SeekProbe.beat(
        ready: ready.value,
        playing: playing.value,
        completed: completed.value,
        buffering: buffering.value,
        uiPosMs: position.value.inMilliseconds,
        uiDurMs: duration.value.inMilliseconds,
        seeking: _isSeeking,
        nativeSeekInFlight: _nativeSeekInFlight,
        queuedTargetMs: _queuedSeekTargetMs,
        userIntent: _userIntentPlaying,
      );
      SeekProbe.pollBegin();
      final player = _player;
      if (_disposed || player == null || !ready.value) {
        SeekProbe.markPhase('skip-notready');
        SeekProbe.pollEnd();
        return;
      }

      // 若正在 seek 过程中，底层 player.position 仍可能返回旧 PTS，
      // 保持当前 target 进度，避免进度条来回跳变抖动；同时屏蔽卡顿看门狗误判。
      if (_isSeeking) {
        final target = _seekTargetMs ?? position.value.inMilliseconds;
        // 重挂窗口内不读底层 position：时钟「跳回」瞬态存在锁竞争风险
        //（2026-09-20 00:11 死锁实证，同步 FFI 读取可永久阻塞 isolate），
        // 用 target 代替——落地判定已由 hasNativeReturned 门控，不受影响。
        final currentPosMs = _audioRemountInFlight ? target : player.position;
        SeekProbe.markPhase('seek-wait');
        SeekProbe.pollStage('after-position', 'v=$currentPosMs target=$target');
        if (SeekProbe.rawDue()) {
          SeekProbe.raw(
            'seek pos=$currentPosMs target=$target state=${player.state} '
            'status=${player.mediaStatus} inFlight=${_nativeSeekInFlight ? 1 : 0} '
            'queued=${_queuedSeekTargetMs ?? -1}',
          );
        }

        // 取证：采样 position 轨迹与推进速率（重挂窗口内不读底层 position）
        if (!_audioRemountInFlight) {
          SeekProbe.tick(currentPosMs);
        }

        // 仅在底层 native seek 真正执行完成（_nativeSeekDoneTime != null）且无排队请求后，才进入落地判定
        final doneTime = _nativeSeekDoneTime;
        final hasNativeReturned =
            !_nativeSeekInFlight &&
            _queuedSeekTargetMs == null &&
            doneTime != null;

        // 判定真正落地条件：
        // 1. native seek 已返回成功；
        // 2. 底层 player.position 已经同步推进到目标物理关键帧附近（允许 2500ms 容差）；
        // 3. 若已返回超过 400ms 且目标点为 0，即便底层 PTS 采样有微小时滞，也判定已落地，避免 3 秒僵死；
        // 4. 严禁基于短超时（如 200ms）强行解除 seek 锁，否则底层未上屏的旧 PTS 会瞬间覆盖 UI 进度条导致弹跳！
        final isNearTarget = (currentPosMs - target).abs() <= 2500;
        final isTargetZeroSettled =
            hasNativeReturned &&
            target == 0 &&
            DateTime.now().difference(doneTime) >
                const Duration(milliseconds: 400);
        final hasLanded =
            hasNativeReturned && (isNearTarget || isTargetZeroSettled);

        final isTimeout =
            _seekStartTime != null &&
            DateTime.now().difference(_seekStartTime!) >
                const Duration(milliseconds: 3000);

        if (hasLanded || isTimeout) {
          if (isTimeout && !hasLanded) {
            AppLogger.w(
              'PlayerController',
              'Seek timeout for target $target ms (currentPos=$currentPosMs), releasing seek lock',
            );
          }
          _isSeeking = false;
          _seekTargetMs = null;
          _seekStartTime = null;
          _nativeSeekDoneTime = null;
          // 若已确认到达目标，同步底层采样基准；若硬超时且未落地，以 target 为基准，避免旧高位 PTS 污染
          _lastPolledPosMs = hasLanded ? currentPosMs : target;
          SeekProbe.markPhase('seek-landed');
        } else {
          // 底层 seek 执行中或纹理未排空，维持目标进度，屏蔽旧 PTS 覆盖导致的回跳
          _bufferingStallMs = 0;
          SeekProbe.markPhase('seek-pending');
          SeekProbe.pollEnd();
          return;
        }
      }

      final posMs = player.position;
      SeekProbe.pollStage('after-position', 'v=$posMs');
      SeekProbe.markPhase('pos-read');
      SeekProbe.tick(posMs);
      final newPos = Duration(milliseconds: posMs);
      // 完成态冻结进度：音画微差会导致底层 PTS 停在总时长之前，禁止轮询
      // 把 _handlePlaybackEnded 已归一到 duration 的进度再往回拖（音频先播完场景）。
      final completedFrozen =
          completed.value &&
          duration.value.inMilliseconds > 0 &&
          posMs < duration.value.inMilliseconds;
      if (!completedFrozen && position.value != newPos) {
        position.value = newPos;
      }
      // 进度推进检测：若播放进度在前进，清零卡顿计时并解除缓冲态。
      // 每轮无条件更新 _lastPolledPosMs 为最新采样位置，杜绝快退时高位死锁。
      final isPosAdvancing = _lastPolledPosMs >= 0 && posMs > _lastPolledPosMs;
      _lastPolledPosMs = posMs;
      if (isPosAdvancing) {
        _bufferingStallMs = 0;
        if (buffering.value) {
          buffering.value = false;
        }
      }

      final durMs = duration.value.inMilliseconds;
      if (durMs > 0) {
        int calculatedBufMs = 0;
        try {
          final ranges = player.bufferedTimeRanges();
          if (ranges.isNotEmpty) {
            // 1. 优先查找覆盖当前播放点（允许前置/后置 1500ms 容差）的物理缓冲区间
            dynamic activeRange;
            for (final r in ranges) {
              final s = r.start.inMilliseconds;
              final e = r.end.inMilliseconds;
              if (posMs >= s - 1500 && posMs <= e + 1500) {
                activeRange = r;
                break;
              }
            }
            if (activeRange != null) {
              calculatedBufMs = activeRange.end.inMilliseconds;
            } else {
              // 2. 若没有直接覆盖的区间，查找位于当前播放位置之后的第一个连续区间
              for (final r in ranges) {
                final s = r.start.inMilliseconds;
                if (s >= posMs &&
                    (calculatedBufMs == 0 || s < calculatedBufMs)) {
                  calculatedBufMs = r.end.inMilliseconds;
                  break;
                }
              }
              // 3. 兜底：若所有区间都在当前点之前，取所有区间中最远 end
              if (calculatedBufMs == 0) {
                for (final r in ranges) {
                  if (r.end.inMilliseconds > calculatedBufMs) {
                    calculatedBufMs = r.end.inMilliseconds;
                  }
                }
              }
            }
          }
        } catch (_) {}

        // 兜底：若 bufferedTimeRanges 返回空或异常，使用 player.buffered() 相对估算
        if (calculatedBufMs <= 0) {
          final bufMs = player.buffered();
          if (bufMs > 0) {
            calculatedBufMs = posMs + bufMs;
          }
        }

        // 单调保障（对标 PiliPlus）：如果当前播放位置依然在历史已缓冲的最大覆盖线以内，
        // 缓冲进度绝不允许因快退 Seek 或解码器队列刷新而向左坍塌缩短！
        if (posMs <= _maxContinuousBufferedMs &&
            calculatedBufMs < _maxContinuousBufferedMs) {
          calculatedBufMs = _maxContinuousBufferedMs;
        }

        if (calculatedBufMs > _maxContinuousBufferedMs) {
          _maxContinuousBufferedMs = calculatedBufMs;
        }

        if (calculatedBufMs > 0) {
          final targetBuf = Duration(
            milliseconds: calculatedBufMs.clamp(0, durMs),
          );
          if (buffered.value != targetBuf) {
            buffered.value = targetBuf;
          }
        }
      }
      SeekProbe.markPhase('buffered');
      SeekProbe.pollStage(
        'after-buffered',
        'v=$posMs b=${buffered.value.inMilliseconds}',
      );
      // 采样过滤（2026-09-25）：seek 落地后 3s 内的 position 属回跳/追赶瞬态，
      // 计入统计会污染 stalls/avgRate（实测落地后 1.6s 的样本仍被算成 2.8s 停顿）。
      final monitorSettled =
          _lastSeekFinishTime == null ||
          DateTime.now().difference(_lastSeekFinishTime!) >
              const Duration(seconds: 3);
      if (monitorSettled) {
        SeekProbe.monitorTick(posMs, buffered.value.inMilliseconds);
      }
      // 常态原始读数（5s 节流）：与零风险心跳互补，给出底层真实 state/status
      // 与第二实例状态——2026-09-24 事件中该行会直接落在「完成态冻结」分支内。
      if (SeekProbe.rawDue()) {
        final ap = _audioPlayer;
        SeekProbe.raw(
          'pos=$posMs dur=$durMs buf=${buffered.value.inMilliseconds} '
          'state=${player.state} status=${player.mediaStatus} '
          'adv=${isPosAdvancing ? 1 : 0} playing=${playing.value ? 1 : 0} '
          'completed=${completed.value ? 1 : 0} '
          'audio=${ap == null ? '-' : (_audioRemountInFlight ? 'remount' : '${ap.state}@${ap.position}')}',
        );
      }
      final isNearEnd = durMs > 0 && posMs >= durMs - 200;
      if (!_isSeeking &&
          !_nativeSeekInFlight &&
          _queuedSeekTargetMs == null &&
          isNearEnd &&
          !isPosAdvancing &&
          !playing.value) {
        SeekProbe.markPhase('near-end-ended');
        SeekProbe.pollEnd();
        _handlePlaybackEnded(source: 'pollNearEnd');
        return;
      }

      // 若已处于播放完毕状态，或已到达片尾 1 秒内，绝对禁止触发缓冲与卡死看门狗。
      if (completed.value || (durMs > 0 && posMs >= durMs - 1000)) {
        buffering.value = false;
        _bufferingStallMs = 0;
        SeekProbe.markPhase('completed-frozen');
        SeekProbe.pollEnd();
        return;
      }

      // 卡死看门狗（Watchdog，参照 BiliPai resolvePlaybackStallRecoveryDecision）：
      // 1. 用户意图播放（_userIntentPlaying，非手动暂停，且未播放完毕）；
      // 2. 若播放进度正常推进（isPosAdvancing），坚决维持非缓冲态；
      // 3. 仅在播放停滞（!isPosAdvancing）且脱离 seek 保护期时检测底层 stalled（解码空仓）或累计停滞达 1 秒；
      // 4. Seek 落地后 3 秒保护期内绝对禁止触发重载，防止高码率流首次缓冲网络延迟被误杀；
      // 5. 达到 10 秒真卡死门限且底层无任何缓冲水位（buffered <= 0）时，才触发自愈。
      SeekProbe.markPhase('watchdog');
      // 方案 3（docs 2.9）：双实例漂移校正——音频侧滞后则提速 3%、超前则减速 3%，
      // 偏差 >1.5s 直接硬定位；seek 期与任一实例非播放态一律跳过（避开瞬态）。
      final apd = _audioPlayer;
      if (apd != null &&
          !_isSeeking &&
          !_nativeSeekInFlight &&
          _queuedSeekTargetMs == null) {
        try {
          if (player.state == mdk.PlaybackState.playing &&
              apd.state == mdk.PlaybackState.playing) {
            final sinceSeek = _lastSeekFinishTime == null
                ? 1 << 30
                : DateTime.now()
                      .difference(_lastSeekFinishTime!)
                      .inMilliseconds;
            final apPosMs = apd.position;
            final decision = SeekProbe.driftDecision(
              posMs,
              apPosMs,
              sinceSeekMs: sinceSeek,
            );
            // 三态处理（2026-09-25）：action -1＝节流期保持现状（严禁复位速率，
            // 旧实现把节流 0 与死区 0 一起复位，导致修正占空比 ~2%、偏差累积到
            // 0.9~1.5s 后硬跳）；action 1＝比例控速；action 0＝死区内复位。
            if (decision.action == 2) {
              SeekProbe.note(
                'DRIFT-HARD drift=${apPosMs - posMs} video=$posMs '
                'audio=$apPosMs -> audio seek',
              );
              unawaited(apd.seek(position: posMs));
              apd.playbackRate = 1.0;
            } else if (decision.action == 1) {
              if ((apd.playbackRate - decision.rate).abs() >= 0.005) {
                SeekProbe.note(
                  'DRIFT-APPLY rate=${decision.rate.toStringAsFixed(4)} '
                  'drift=${apPosMs - posMs} video=$posMs audio=$apPosMs '
                  'sinceSeek=$sinceSeek',
                );
              }
              apd.playbackRate = decision.rate;
            } else if (decision.action == 0) {
              if ((apd.playbackRate - 1.0).abs() > 0.001) {
                SeekProbe.note(
                  'DRIFT-APPLY rate=1.0000 reset drift=${apPosMs - posMs} '
                  'video=$posMs audio=$apPosMs',
                );
                apd.playbackRate = 1.0;
              }
            }
          }
        } catch (_) {}
      }
      SeekProbe.markPhase('drift');
      SeekProbe.pollStage('after-drift');
      final isSeekRecent =
          _lastSeekFinishTime != null &&
          DateTime.now().difference(_lastSeekFinishTime!) <
              const Duration(seconds: 3);

      if (_userIntentPlaying && playing.value && !_isSeeking) {
        if (isPosAdvancing) {
          _bufferingStallMs = 0;
          if (buffering.value) {
            buffering.value = false;
          }
        } else if (!isSeekRecent) {
          final status = player.mediaStatus;
          final isStalled = status.test(mdk.MediaStatus.stalled);
          if (isStalled) {
            _bufferingStallMs += 100;
            if (!buffering.value) buffering.value = true;
          } else {
            _bufferingStallMs += 100;
            if (_bufferingStallMs >= 1000 && !buffering.value) {
              buffering.value = true;
            }
          }
        }
      }

      if (_userIntentPlaying &&
          buffering.value &&
          !_isRecovering &&
          !_isSeeking &&
          !isSeekRecent) {
        if (_bufferingStallMs >= 10000 && player.buffered() <= 0) {
          _bufferingStallMs = 0;
          AppLogger.w(
            'PlayerController',
            'Buffering stall detected (10s) at ${posMs}ms, triggering stream recovery',
          );
          unawaited(_recoverStalledStream());
        }
      } else if (!_userIntentPlaying || isSeekRecent) {
        _bufferingStallMs = 0;
      }
      SeekProbe.markPhase('sponsor');
      // SponsorBlock 自动跳过：检查当前位置是否在可跳过段落内。
      if (sponsorBlockEnabled) {
        final target = sponsorBlock?.computeSkipTarget(posMs / 1000.0);
        if (target != null) {
          seek(Duration(milliseconds: (target * 1000).toInt()));
        }
      }
      // 播放结束检测：进度达到 duration 的 99% 视为播完，上报 -1。
      _maybeReportPlaybackEnd();
      SeekProbe.markPhase('tick-done');
      SeekProbe.pollEnd();
    });
  }

  /// 发送一次心跳（对标 PiliPlus makeHeartBeat，best-effort，失败静默）。
  Future<void> makeHeartBeat(
    int progressSec, {
    int playType = 0,
    bool isManual = false,
  }) async {
    if (!Accounts.history.isLogin || Pref.historyPause) return;
    if (_disposed && !isManual) return;
    if ((aid == null || aid! <= 0) &&
        bvid.isEmpty &&
        (epId == null || epId! <= 0)) {
      return;
    }

    _lastHeartBeatPosSec = progressSec;
    try {
      final res = await VideoHttp.heartBeat(
        aid: aid,
        bvid: bvid,
        cid: cid,
        epId: epId,
        seasonId: seasonId,
        subType: seasonType,
        videoType: videoType,
        playType: playType,
        progressSec: progressSec,
      );
      if (kDebugMode) {
        if (res case Error(:final errMsg)) {
          debugPrint('HeartBeat: report failed: $errMsg');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('HeartBeat: report exception: $e');
      }
    }
  }

  /// 启动心跳定时器（每 5 秒上报一次进度）。
  /// 在 load 成功后调用，dispose / detachListeners 时停止。
  void _startHeartBeat() {
    _heartBeatTimer?.cancel();
    _playingAccumSec = 0;
    _lastHeartBeatPlaying = null;
    _lastHeartBeatPosSec = -1;
    _reportedEnd = false;
    _heartBeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_disposed) return;
      // 未登录或用户关闭历史记录时不报。
      if (!Accounts.history.isLogin || Pref.historyPause) return;
      final isPlaying = playing.value;
      final currentPosSec = position.value.inSeconds;

      if (isPlaying) {
        _playingAccumSec += 5;
      }

      // 状态变化（playing↔paused）时上报：首次变化报 0（开始），其后 1=暂停 / 2=继续
      if (_lastHeartBeatPlaying != isPlaying) {
        final playType = _lastHeartBeatPlaying == null
            ? 0
            : (isPlaying ? 2 : 1);
        _lastHeartBeatPlaying = isPlaying;
        unawaited(makeHeartBeat(currentPosSec, playType: playType));
        return;
      }

      // 持续播放中且累计 ≥5s：上报心跳进度。
      if (isPlaying &&
          (_playingAccumSec >= 5 ||
              (currentPosSec - _lastHeartBeatPosSec).abs() >= 5)) {
        unawaited(makeHeartBeat(currentPosSec, playType: 0));
      }
    });
  }

  /// 播放结束上报：进度达到 duration 99% 时上报 play_type=3/progressSec=-1（仅一次）。
  void _maybeReportPlaybackEnd() {
    if (_reportedEnd) return;
    if (!Accounts.history.isLogin || Pref.historyPause) return;
    final dur = duration.value;
    if (dur.inSeconds <= 0) return;
    final pos = position.value;
    // 进度达到 99% 或距离结尾 1.5 秒内视为播完。
    if (pos.inMilliseconds >= dur.inMilliseconds * 0.99 ||
        (dur.inMilliseconds - pos.inMilliseconds) <= 1500) {
      _reportedEnd = true;
      unawaited(makeHeartBeat(-1, playType: 3, isManual: true));
      final effectiveAid = aid;
      if (effectiveAid != null && effectiveAid > 0) {
        unawaited(
          VideoHttp.reportHistory(aid: effectiveAid, cid: cid, progressSec: 0),
        );
      }
    }
  }

  /// 上报当前进度（页面退出/被覆盖/切集时调用）。
  Future<void> reportCurrentProgress() async {
    if (!Accounts.history.isLogin || Pref.historyPause) return;
    final posSec = position.value.inSeconds;
    if (posSec <= 0 && !completed.value) return;
    final targetProgress = completed.value ? -1 : posSec;

    // 1. 发送心跳上报（包含 PGC/UGC 完整上下文）
    await makeHeartBeat(
      targetProgress,
      playType: completed.value ? 3 : 1,
      isManual: true,
    );

    // 2. 额外上报历史进度接口（若有有效 aid）
    final effectiveAid = aid;
    if (effectiveAid != null && effectiveAid > 0) {
      try {
        await VideoHttp.reportHistory(
          aid: effectiveAid,
          cid: cid,
          progressSec: completed.value ? 0 : posSec,
        );
      } catch (_) {}
    }
  }

  /// 拉取 DASH、选流（StreamSelectionPolicy）、挂载外部音轨打开。
  ///
  /// 首次加载时由 [VideoLoadPolicy.resolveInitialStartQuality] 决定 qn
  /// （根据登录态/VIP/自动最高画质偏好），不再写死 80。
  /// [start] 指定起始播放位置（用于页面返回后恢复进度）；
  /// [autoplay] 为 false 时加载完成后保持暂停（用于之前已暂停的场景）。
  /// 失败时写入 [error]，不抛异常。
  Future<void> load({Duration? start, bool autoplay = true}) async {
    // 幂等：网络栈未初始化时兜底（main 中未等待 bootstrap）。
    await ensureBootstrap();
    // 首次加载：用 VideoLoadPolicy 决策初始画质；
    // didPopNext 恢复时复用上次记录的 _currentQn。
    int qn;
    if (_isInitialLoad) {
      qn = _resolveStartQuality();
      _currentQn = qn;
    } else {
      qn = _currentQn > 0 ? _currentQn : 80;
    }
    await _openWithQuality(
      qn: qn,
      maxQn: qn,
      start: start,
      autoplay: autoplay,
      isInitialRequest: _isInitialLoad,
    );
    _isInitialLoad = false;
  }

  /// 异步恢复到指定播放进度（playInfo 与 [load] 并行返回续播位置时调用）。
  ///
  /// 与 load(start:) 不同：调用时加载可能已在进行中（setMedia/prepare），
  /// 立即 seek 会与加载流程竞态。此处等待 media 就绪（ready 且 duration
  /// 已由 buffered 事件写入）后再 seek；加载失败则放弃恢复。
  Future<void> resumeTo(Duration position) async {
    final player = _player;
    if (player == null || _disposed || position <= Duration.zero) return;
    if (!ready.value || duration.value <= Duration.zero) {
      // 仍在加载：监听就绪信号。error 非空表示加载失败，放弃恢复。
      final done = Completer<void>();
      void check() {
        if ((ready.value && duration.value > Duration.zero) ||
            error.value != null) {
          if (!done.isCompleted) done.complete();
        }
      }

      ready.addListener(check);
      duration.addListener(check);
      error.addListener(check);
      try {
        // 兜底超时：load 被防抖吞掉等极端情况下不悬挂监听。
        await done.future.timeout(
          const Duration(seconds: 15),
          onTimeout: () {},
        );
      } finally {
        ready.removeListener(check);
        duration.removeListener(check);
        error.removeListener(check);
      }
      if (_disposed || error.value != null) return;
      if (!ready.value || duration.value <= Duration.zero) return;
    }
    await player.seek(position: position.inMilliseconds);
  }

  /// 通过 VideoLoadPolicy 解析首次加载画质。
  ///
  /// 桌面端无移动数据概念，[preferFastStartOnMobile] 恒为 false。
  int _resolveStartQuality() {
    final account = Accounts.main;
    final userInfo = Pref.userInfoCache;
    final isLogin = account.isLogin;
    final isVip = userInfo?.isVip ?? false;
    final autoHighest = Pref.autoHighestQuality;
    final auto1080p = Pref.auto1080pEnabled;
    final target = Pref.defaultVideoQa;
    return VideoLoadPolicy.resolveInitialStartQuality(
      targetQuality: target > 0 ? target : null,
      isAutoHighestQuality: autoHighest,
      isLogin: isLogin,
      isVip: isVip,
      auto1080pEnabled: auto1080p,
      preferFastStartOnMobile: false,
    );
  }

  /// 切换到指定清晰度（acceptQuality[index]），记住进度重新 open。
  /// 切换成功后持久化画质偏好到 [Pref.defaultVideoQa]。
  Future<void> switchQuality(int index) async {
    final accept = _playUrl?.acceptQuality;
    if (accept == null || index < 0 || index >= accept.length) return;
    final qn = accept[index];
    // 已是当前清晰度：不重复加载（重复 setMedia 同一 URL 会让 prepare 返回 -1）。
    if (qn == _currentQn) return;
    final remembered = position.value;
    await _openWithQuality(
      qn: qn,
      maxQn: qn,
      start: remembered,
      isInitialRequest: false,
    );
    // 持久化画质偏好。
    if (qn > 0) Pref.defaultVideoQa = qn;
  }

  Future<void> _openWithQuality({
    required int qn,
    required int maxQn,
    Duration? start,
    bool autoplay = true,
    bool isInitialRequest = false,
  }) async {
    final player = _player;
    if (player == null || _disposed) return;
    // 防抖：已有加载/切换在进行中时忽略重复请求，避免并发 prepare 导致
    // mdk 状态错乱（快速点击重试、连续切换画质时的崩溃根因）。
    if (_loading) return;
    _loading = true;
    try {
      // 不手动 state = stopped：native setMedia(url 变化) 会自动停止旧播放并
      // 重置轨道（见 generated_bindings.dart 中 setMedia 注释）。手动 stopped
      // 反而可能导致 native loaded 标志未清除，prepare 误判 "already loaded"
      // 返回 -1（共享 player 从 A 切换到 B 时正是这个症状）。

      error.value = null;
      ready.value = false;
      buffering.value = false;
      // 重置播放状态：避免异步加载完成前 UI 闪烁上一个视频的进度/时长/播放状态
      // （didPopNext 恢复、switchQuality 切换画质时进度条跳变的根因）。
      position.value = Duration.zero;
      duration.value = Duration.zero;
      buffered.value = Duration.zero;
      _maxContinuousBufferedMs = 0;
      playing.value = false;
      completed.value = false;
      _reportedEnd = false;
      _bufferingStallMs = 0;

      // 1. PlayUrlCache：先查缓存，命中且未过期则跳过 HTTP。
      final cacheKey = (epId != null && epId! > 0) ? 'ep_$epId' : bvid;
      PlayUrlModel? playUrl =
          playUrlCache.get(cacheKey, cid, requestedQuality: qn)
              as PlayUrlModel?;
      if (playUrl == null) {
        LoadingState<PlayUrlModel> result;
        if (epId != null && epId! > 0) {
          result = await PgcHttp.pgcPlayUrl(
            cid: cid,
            epId: epId,
            seasonId: seasonId,
            bvid: bvid,
            qn: qn,
          );
          // 若 PGC 接口失败且有 bvid，回退到普通视频接口
          if (result is Error && bvid.isNotEmpty) {
            result = await VideoHttp.videoUrl(
              bvid: bvid,
              cid: cid,
              qn: qn,
              voiceBalance: audioNormalizeEnabled,
            );
          }
        } else {
          result = await VideoHttp.videoUrl(
            bvid: bvid,
            cid: cid,
            qn: qn,
            voiceBalance: audioNormalizeEnabled,
          );
        }
        if (_disposed) return;
        playUrl = result.dataOrNull;
        if (playUrl == null) {
          error.value = '获取播放地址失败';
          return;
        }
        // 写入缓存（按 VideoLoadPolicy.shouldCachePlayUrlResult 判定）。
        final source = PlayUrlSource.dash;
        if (VideoLoadPolicy.shouldCachePlayUrlResult(
          source,
          null,
          requestedQuality: qn,
          returnedQuality: playUrl.quality ?? 0,
          dashVideoIds:
              playUrl.dash?.video
                  ?.map((v) => v.id ?? 0)
                  .toList(growable: false) ??
              const [],
        )) {
          playUrlCache.put(cacheKey, cid, playUrl, quality: qn);
        }
      }

      // 2. StreamSelectionPolicy：编解码器感知选流（通用硬解优先 HEVC > AVC > AV1），
      // 优先保障 100% GPU 零拷贝硬解，彻底杜绝无 AV1 专用硬解模块设备上的 CPU 软解掉帧。
      final selection = StreamSelectionPolicy.selectStreams(
        playUrl,
        maxQn: maxQn,
        capability: DeviceCodecCapability.av1,
        preferSpecialAudio: true,
      );
      final video = selection.video;
      final audio = selection.audio;

      // 提取视频候选 URL：经 CdnPolicy 过滤 MCDN/PCDN 矿渣节点并智能优选官方镜像候选列表
      _videoCdnCandidates = (video != null && video.playUrls.isNotEmpty)
          ? CdnPolicy.resolveAllUrls(video.playUrls)
          : const [];

      // 兜底：如果 DASH video 为空，检查是否有 durl（非 DASH 流，内嵌完整音画）
      bool isDurlFallback = false;
      if (_videoCdnCandidates.isEmpty) {
        final durls = playUrl.durl;
        if (durls != null &&
            durls.isNotEmpty &&
            durls.first.playUrls.isNotEmpty) {
          _videoCdnCandidates = CdnPolicy.resolveAllUrls(durls.first.playUrls);
          isDurlFallback = _videoCdnCandidates.isNotEmpty;
        }
      }

      if (_videoCdnCandidates.isEmpty) {
        error.value = '未获取到可播放的视频流';
        return;
      }

      // 提取音频候选 URL（durl 模式已内嵌音频无需外部挂载）
      _audioCdnCandidates =
          (isDurlFallback || audio == null || audio.playUrls.isEmpty)
          ? const []
          : CdnPolicy.resolveAllUrls(audio.playUrls, isAudio: true);

      _currentCdnIndex = 0;
      final videoUrl = _videoCdnCandidates.first;
      final audioUrl = _audioCdnCandidates.isNotEmpty
          ? _audioCdnCandidates.first
          : null;
      _currentVideoUrl = videoUrl;
      _currentAudioUrl = audioUrl;

      _userIntentPlaying = true;
      _lastPolledPosMs = (start ?? Duration.zero).inMilliseconds;
      _bufferingStallMs = 0;
      _stallRecoveryRetryCount = 0;

      _playUrl = playUrl;
      _currentQn = video?.id ?? playUrl.quality ?? qn;
      // 通知面板重建画质按钮（_playUrl 为普通字段，不自动触发重建）。
      qualityVersion.value++;

      if (kDebugMode) {
        debugPrint(
          'PlayStream: bvid=$bvid qn=$_currentQn codec=${selection.videoCodec.name} '
          'audio=${selection.audioKind.name} isDurl=$isDurlFallback '
          'candidates=${_videoCdnCandidates.length}',
        );
      }

      // 请求头经 'avio.headers' 属性下发，格式为 "Key: Value\r\n" 列表，
      // 对该 Player 打开的所有源（含外部音轨）生效。
      // 若已登录，附带登录态 Cookie，确保对高质量流及 CDN 防盗链的持续鉴权。
      final account = Accounts.main;
      String headers = 'Referer: $_referer\r\nUser-Agent: $_pcUserAgent\r\n';
      if (account is LoginAccount) {
        final cookies = account.keyCookies;
        if (cookies.isNotEmpty) {
          final cookieStr = cookies
              .map((c) => '${c.name}=${c.value}')
              .join('; ');
          headers += 'Cookie: $cookieStr\r\n';
        }
      }
      player.setProperty('avio.headers', headers);
      // Phase 4.7：音频归一化滤镜作为 player 属性在 prepare 前下发，
      // 避免在 media 已打开/播放中切换 avfilter 触发音频轨重初始化干扰状态。
      final filter = AudioNormalization.parse(
        playUrl.volume,
        AudioNormalization.getParamFromConfig(Pref.audioNormalization),
      );
      if (filter.isNotEmpty) {
        player.setProperty('audio.avfilter', filter);
      } else {
        player.setProperty('audio.avfilter', '');
      }

      // 1. 设置主视频 media。
      AppLogger.w(
        'PlayerController',
        'setMedia video: cdn=${Pref.defaultCDNService.name} candidates=${_videoCdnCandidates.length} videoUrl=$videoUrl audioUrl=$audioUrl',
      );

      // 单源化（验证模式，默认关闭）：
      // 方案 A = 按 sidx 分段的 HLS 清单（seek 走 HLS 原生选段+段内定位）；
      // 兜底 1 = 整段 HLS 清单；兜底 2（方案 B）= durl 合并流（单一 URL，
      // 直接走已验证可用的主媒体 seek 路径，清晰度上限较低）；
      // 三者都不可用时退回双轨（保持改动前行为）。
      final dashDurationSec = playUrl.dash?.duration ?? 0;
      String? manifestUrl;
      String sourceMode = 'dual-track';
      if (SeekProbe.manifestModeEnabled && dashDurationSec > 0) {
        final durlUrls = playUrl.durl?.isNotEmpty == true
            ? playUrl.durl!.first.playUrls
            : const <String>[];
        final durlUrl = durlUrls.isNotEmpty ? durlUrls.first : null;
        if (audioUrl != null && audioUrl.isNotEmpty) {
          final headerMap = <String, String>{};
          for (final line in headers.split('\r\n')) {
            final i = line.indexOf(':');
            if (i > 0) {
              headerMap[line.substring(0, i).trim()] =
                  line.substring(i + 1).trim();
            }
          }
          final vCodecs = video?.codecs;
          final codecs = [
            if (vCodecs != null && vCodecs.isNotEmpty) vCodecs,
            'mp4a.40.2',
          ].join(',');
          final bw = (video?.bandwidth ?? 0) + (audio?.bandwidth ?? 0);
          try {
            manifestUrl = await HlsManifest.publishSegmented(
              name: 'stream_$bvid',
              videoUrl: videoUrl,
              audioUrl: audioUrl,
              headers: headerMap,
              durationSec: dashDurationSec.toDouble(),
              bandwidth: bw,
              codecs: codecs,
            );
            if (manifestUrl != null) sourceMode = 'hls-segmented';
          } catch (e) {
            AppLogger.w('PlayerController', 'HLS 分段清单生成失败：$e');
          }
          if (manifestUrl == null) {
            try {
              manifestUrl = await HlsManifest.publish(
                name: 'stream_$bvid',
                videoUrl: videoUrl,
                audioUrl: audioUrl,
                durationSec: dashDurationSec.toDouble(),
                bandwidth: bw,
                codecs: codecs,
              );
              if (manifestUrl != null) sourceMode = 'hls-single';
            } catch (e) {
              AppLogger.w('PlayerController', 'HLS 整段清单生成失败：$e');
            }
          }
        }
        if (manifestUrl == null && durlUrl != null) {
          manifestUrl = durlUrl;
          sourceMode = 'durl';
        }
      }
      SeekProbe.note(
        'MANIFEST mode=$sourceMode url=${manifestUrl ?? '-'} '
        'vDur=${dashDurationSec}s vCodecs=${video?.codecs} '
        'vBandwidth=${video?.bandwidth} aBandwidth=${audio?.bandwidth}',
      );

      if (manifestUrl != null) {
        _currentVideoUrl = manifestUrl;
        _currentAudioUrl = null;
        _videoCdnCandidates = [manifestUrl];
        _audioCdnCandidates = const [];
        player.media = manifestUrl;
      } else if (_dualPlayerAudio && audioUrl != null && audioUrl.isNotEmpty) {
        // 方案 3 最小验证：主播放器只放纯视频 URL（不再挂外挂音轨，
        // 回到实测可靠的「主媒体 seek」），音频交给第二实例（音轨即其主媒体）。
        final ap = _audioPlayer ??= _createAudioPlayer();
        ap.setProperty('avio.headers', headers);
        ap.setProperty('keep_open', '1');
        ap.volume = volume.value / 100.0;
        player.media = videoUrl;
        ap.media = audioUrl;
        unawaited(ap.prepare());
        _currentVideoUrl = videoUrl;
        // 主播放器无外挂音轨：置空以避免双轨补救逻辑（重挂舞步/自愈）误触发。
        _currentAudioUrl = null;
        SeekProbe.note(
          'DUAL-PLAYER main=video-only second=audio-only '
          'videoUrl=$videoUrl audioUrl=$audioUrl',
        );
      } else {
        player.media = videoUrl;
        // DASH 分离音轨：以外部音轨方式挂载（prepare 之前）。
        // 参照 fvp setExternalAudio → setMedia(url, MediaType.audio) 用法：
        // native setMedia(url 变化) 会重置轨道，setMediaForType 挂载外部音轨
        // 后必须调用 setActiveTracks 显式激活，否则音频轨道不会被自动选中
        // （B站 DASH 主 media 为纯视频流，无内部音频轨，导致无声）。
        // 在 prepare 之前挂载，使 prepare 能一次性加载主视频 + 外部音轨。
        if (audioUrl != null && audioUrl.isNotEmpty) {
          player.setMedia(audioUrl, mdk.MediaType.audio);
          player.activeAudioTracks = const [0];
        }
      }

      // 2. prepare 加载首帧。
      // prepare 不传 position：prepare 返回 -1（already loading）时
      // position 参数会被 native 忽略，导致进度没恢复。改用 prepare() 只
      // 加载首帧，进度恢复统一用 seek（ret >= 0 时立即 seek，ret == -1
      // 时延迟到 onMediaStatus.buffered 事件后 seek）。
      final ret = await player.prepare();
      AppLogger.w(
        'PlayerController',
        'prepare ret=$ret (0=ok, -1=already loading, <-1=error)',
      );
      if (_disposed) return;
      // prepare 返回值语义（见 fvp player.dart 注释）：
      //   0: streams==0 无效媒体，否则成功
      //  -1: already loading or loaded（setMedia 已触发加载，无需重复 prepare）
      //  -4: 越界  -10: 内部错误
      // 共享 player 从 A 切换到 B 时，setMedia 已开始加载 B 的 media，prepare
      // 常返回 -1。这不是失败：真正的失败由 onEvent 错误事件（ev.error < 0）
      // 设置 error。仅对 < -1 的硬错误报错。
      if (ret < -1) {
        AppLogger.e(
          'PlayerController',
          'prepare failed: ret=$ret, aborting load',
        );
        error.value = '播放失败（错误码 $ret）';
        return;
      }
      // prepare 成功后再次清空 error（覆盖 setMedia 旧 media 卸载期间
      // 可能产生的残留错误事件）。
      error.value = null;

      // 3. seek 恢复进度。
      final startMs = (start ?? Duration.zero).inMilliseconds;
      if (startMs > 0) {
        if (ret >= 0) {
          // prepare 成功加载首帧：立即 seek 恢复进度。
          await player.seek(position: startMs);
          if (_disposed) return;
        } else {
          // ret == -1（already loading）：media 正在加载，无法立即 seek。
          // 暂存进度，等 onMediaStatus.buffered 事件触发后 seek。
          // duration/videoSize 也在 buffered 事件中获取，避免拿到旧 media 的值。
          _pendingSeek = start;
        }
      }

      // 创建渲染 Texture（仅首次创建 player 时需要，后续复用单例已存在的
      // texture，避免重复 updateTexture 导致渲染面重建）。
      if (player.textureId.value == null) {
        final tex = await player.updateTexture();
        if (_disposed) return;
        if (tex < 0) {
          error.value = '视频渲染面创建失败';
          return;
        }
      }

      if (_disposed) return;
      player.state = autoplay
          ? mdk.PlaybackState.playing
          : mdk.PlaybackState.paused;
      ready.value = true;
      AppLogger.w(
        'PlayerController',
        'ready=true, state=${player.state}, textureId=${player.textureId}',
      );
      // Phase 4.2：播放就绪后启动心跳定时器（每 5 秒上报进度）。
      _startHeartBeat();
      // 取证探针：按配置执行脚本化 seek 序列（诊断专用）。
      _maybeStartSeekProbe();

      // SponsorBlock 段落加载：失败不阻断播放，仅记录日志。
      if (sponsorBlockEnabled) {
        sponsorBlock ??= SponsorBlockUseCase();
        unawaited(
          sponsorBlock!.fetchSegments(bvid: bvid).then((res) {
            if (_disposed) return;
            final segments = res.dataOrNull;
            if (segments == null) return;
            if (kDebugMode && segments.isNotEmpty) {
              debugPrint(
                'SponsorBlock: loaded ${segments.length} segments for $bvid',
              );
            }
          }),
        );
      }

      // HDR 自动升级：首次 SDR 起播后，VIP + 自动最高画质 + 有
      // access_token + 当前 DASH 无 HDR 轨道时，二次拉流 qn=125。
      //
      // [DISABLED] 二次 setMedia 会中断正在播放的 SDR media，导致：
      // - 画面消失（黑屏）：新 media 替换旧 media 后纹理/解码管线重置
      // - 播放/暂停状态抖动：setMedia 重置 player.state
      // - onEvent "open" -1 误报
      // 待 mdk 共享 player 的无缝切换（无缝替换 media + 保留纹理）验证后再启用。
      // if (isInitialRequest && !_hdrUpgradeAttempted) {
      //   _hdrUpgradeAttempted = true;
      //   _pendingHdrUpgrade = playUrl;
      // }
    } catch (e) {
      if (!_disposed) error.value = '播放失败：$e';
    } finally {
      _loading = false;
    }
  }

  /// HDR 自动升级：满足条件时二次拉流 qn=125（HDR）。
  ///
  /// 升级条件（VideoLoadPolicy.shouldScheduleHdrAutoUpgrade）：
  /// 首次请求 + 自动最高画质 + VIP + 非移动数据 + 有 access_token +
  /// 当前 DASH 无 HDR 轨道(125) + 用户未手动选画质 + 未尝试过升级。
  /// 桌面端非移动数据恒为 true。失败静默（不阻断当前 SDR 播放）。
  Future<void> _maybeUpgradeToHdr(PlayUrlModel currentPlayUrl) async {
    try {
      final account = Accounts.main;
      final userInfo = Pref.userInfoCache;
      final currentIds =
          currentPlayUrl.dash?.video
              ?.map((v) => v.id ?? 0)
              .toList(growable: false) ??
          const <int>[];
      final shouldUpgrade = VideoLoadPolicy.shouldScheduleHdrAutoUpgrade(
        isInitialRequest: true,
        isAutoHighestQuality: Pref.autoHighestQuality,
        isVip: userInfo?.isVip ?? false,
        isMobileData: false,
        hasAccessToken:
            account.accessKey != null && account.accessKey!.isNotEmpty,
        currentPlayableDashVideoIds: currentIds,
        userHasExplicitQualitySelection: false,
        upgradeAlreadyAttempted: false,
      );
      if (!shouldUpgrade) return;
      // 二次拉流 qn=125（HDR）。保留当前进度。
      final remembered = position.value;
      await _openWithQuality(
        qn: 125,
        maxQn: 125,
        start: remembered,
        autoplay: playing.value,
        isInitialRequest: false,
      );
      if (kDebugMode) {
        debugPrint('PlayStream: HDR auto-upgrade attempted for $bvid');
      }
    } catch (e) {
      // 升级失败静默处理，继续 SDR 播放。
      if (kDebugMode) debugPrint('PlayStream: HDR upgrade failed: $e');
    }
  }

  /// 缓冲卡死/网络断流自愈恢复策略（深度移植自 BiliPai PlaybackStallRecoveryPolicy & PiliPlus refreshPlayer）。
  ///
  /// 核心逻辑：
  /// 1. 记录卡死断点毫秒级进度 `resumePos`；
  /// 2. 若有多条候选 CDN 镜像，自动按次序轮换切换至下一条可用镜像（多 CDN 容灾）；
  /// 3. 重新设置底层解复用器音视频源，彻底切断挂死/闲置超时失效的旧 Socket，建立全新 HTTP Range 连接；
  /// 4. 在原位 seek 恢复播放，复用现有 Texture 避免黑屏闪烁。
  Future<void> _recoverStalledStream({bool isNetworkError = false}) async {
    final player = _player;
    if (_disposed || player == null || _isRecovering || !ready.value) return;

    // 已播放完毕或已处于片尾边界，严禁触发流自愈（杜绝 EOF seek 音频回绕片头）。
    final durMs = duration.value.inMilliseconds;
    final curPosMs = player.position;
    if (completed.value || (durMs > 0 && curPosMs >= durMs - 1000)) {
      _handlePlaybackEnded(source: 'stallRecovery');
      return;
    }

    _isRecovering = true;
    _stallRecoveryRetryCount++;
    try {
      final resumePosMs = player.position;
      final resumeDuration = Duration(
        milliseconds: resumePosMs > 0 ? resumePosMs : 0,
      );

      AppLogger.w(
        'PlayerController',
        'Executing playback stall recovery (retry=$_stallRecoveryRetryCount, netErr=$isNetworkError) at ${resumeDuration.inSeconds}s',
      );

      // 1. 若有多条可用 CDN 镜像，轮换切换到下一条线路（参照 BiliPai PlaybackStallRecoveryPolicy）
      if (_videoCdnCandidates.length > 1) {
        _currentCdnIndex = (_currentCdnIndex + 1) % _videoCdnCandidates.length;
        _currentVideoUrl = _videoCdnCandidates[_currentCdnIndex];
        if (_audioCdnCandidates.isNotEmpty) {
          _currentAudioUrl =
              _audioCdnCandidates[_currentCdnIndex %
                  _audioCdnCandidates.length];
        }
        AppLogger.w(
          'PlayerController',
          'Switching CDN candidate: line=${_currentCdnIndex + 1}/${_videoCdnCandidates.length} videoUrl=$_currentVideoUrl',
        );
      }

      final videoUrl = _currentVideoUrl;
      final audioUrl = _currentAudioUrl;
      if (videoUrl == null || videoUrl.isEmpty) {
        AppLogger.e('PlayerController', 'No valid video url to recover stream');
        return;
      }

      // 2. 重新挂载媒体源并触发底层 Range 重连
      player.media = videoUrl;
      if (audioUrl != null && audioUrl.isNotEmpty) {
        player.setMedia(audioUrl, mdk.MediaType.audio);
        player.activeAudioTracks = const [0];
      }

      final ret = await player.prepare();
      if (_disposed) return;
      if (ret >= 0) {
        if (resumePosMs > 0) {
          await player.seek(position: resumePosMs);
        }
      } else {
        if (resumePosMs > 0) {
          _pendingSeek = resumeDuration;
        }
      }

      player.state = mdk.PlaybackState.playing;
      buffering.value = false;
      _bufferingStallMs = 0;
      _lastPolledPosMs = resumePosMs;
      AppLogger.w(
        'PlayerController',
        'Stream stall recovery successfully executed at ${resumeDuration.inSeconds}s',
      );
    } catch (e, s) {
      AppLogger.e(
        'PlayerController',
        'Stream stall recovery failed',
        error: e,
        stackTrace: s,
      );
    } finally {
      _isRecovering = false;
    }
  }

  void playOrPause() {
    final player = _player;
    if (player == null || _disposed) return;
    // seek 冻结窗口（内部 paused 态）：按用户意图判定实际播放方向。
    // 冻结期间底层 state 恒为 paused，若直接读 state 会把「转圈中的播放」误判为
    // 暂停态，导致点击暂停变成中途恢复（重新暴露错位窗口）。
    final inSeekFreeze =
        _isSeeking || _nativeSeekInFlight || _queuedSeekTargetMs != null;
    final bool isEffectivelyPlaying = inSeekFreeze
        ? _userIntentPlaying
        : player.state == mdk.PlaybackState.playing;
    if (isEffectivelyPlaying) {
      _userIntentPlaying = false;
      _bufferingStallMs = 0;
      player.state = mdk.PlaybackState.paused;
    } else {
      // 若处于播放完成状态（或停留在片尾），点击重播从头开始播放（对标 PiliPlus onDoubleTapCenter）
      final durMs = duration.value.inMilliseconds;
      final posMs = player.position;
      if (completed.value || (durMs > 0 && posMs >= durMs - 200)) {
        unawaited(replay());
        return;
      }
      _userIntentPlaying = true;
      _bufferingStallMs = 0;
      player.state = mdk.PlaybackState.playing;
    }
  }

  /// 重新从头开始播放。
  Future<void> replay() async {
    final player = _player;
    if (player == null || _disposed) return;
    completed.value = false;
    _userIntentPlaying = true;
    _bufferingStallMs = 0;
    _reportedEnd = false;
    _maxContinuousBufferedMs = 0;

    // 极端异常兜底：若底层播放器处于 stopped 状态，重新 load 快速拉起
    if (player.state == mdk.PlaybackState.stopped) {
      AppLogger.w('PlayerController', 'replay: player is stopped, reloading');
      await load(start: Duration.zero, autoplay: true);
      return;
    }

    seek(Duration.zero);
  }

  /// 切换播放/暂停（对标 togglePlay 接口命名）
  void togglePlay() => playOrPause();

  /// 暂停播放（不切换状态），用于页面被覆盖时保留单例资源。
  void pause() {
    final player = _player;
    if (player == null || _disposed) return;
    _userIntentPlaying = false;
    _bufferingStallMs = 0;
    if (player.state == mdk.PlaybackState.playing) {
      player.state = mdk.PlaybackState.paused;
    }
    // 方案 3：同步暂停第二实例（避免主实例暂停后音频仍在播）。
    try {
      _audioPlayer?.state = mdk.PlaybackState.paused;
    } catch (_) {}
  }

  /// 恢复播放（仅在暂停态生效），用于折叠自动暂停后展开时恢复。
  /// 与 [playOrPause] 不同，此方法不引入切换语义，避免误触其它状态。
  void play() {
    final player = _player;
    if (player == null || _disposed) return;
    final durMs = duration.value.inMilliseconds;
    final posMs = player.position;
    if (completed.value || (durMs > 0 && posMs >= durMs - 200)) {
      unawaited(replay());
      return;
    }
    _userIntentPlaying = true;
    _bufferingStallMs = 0;
    if (player.state == mdk.PlaybackState.paused ||
        player.state == mdk.PlaybackState.stopped) {
      player.state = mdk.PlaybackState.playing;
    }
  }

  void seek(Duration to) {
    final player = _player;
    if (player == null || _disposed) return;
    final durMs = duration.value.inMilliseconds;
    final clampedMs = durMs > 0
        ? to.inMilliseconds.clamp(0, durMs)
        : (to.inMilliseconds < 0 ? 0 : to.inMilliseconds);
    final clampedTo = Duration(milliseconds: clampedMs);

    // 取证：seek 请求入口（零 FFI 读取，置于所有状态改写之前）。
    // 用于区分「seek 未派发（UI 无响应/手势被吞）」与「派发后未生效/卡死」——
    // 2026-09-24 事件正是缺此埋点而无法判定。
    SeekProbe.note(
      'SEEK-REQ to=${to.inMilliseconds} clamped=$clampedMs dur=$durMs '
      'uiPos=${position.value.inMilliseconds} '
      'completed=${completed.value ? 1 : 0} playing=${playing.value ? 1 : 0} '
      'seek=${_isSeeking ? 1 : 0} inFlight=${_nativeSeekInFlight ? 1 : 0} '
      'queued=${_queuedSeekTargetMs ?? -1} intent=${_userIntentPlaying ? 1 : 0}',
    );

    // 用户明确 Seek 意图：无论此前是播放完还是暂停，立即解除完成态，保持意图起播
    completed.value = false;
    _reportedEnd = false;
    _userIntentPlaying = true;
    _bufferingStallMs = 0;
    if (clampedMs == 0) {
      _maxContinuousBufferedMs = 0;
    }

    // 立即更新对外暴露的 position 与 seekPosition，使 UI 进度条瞬时稳定在目标位置，杜绝回弹
    position.value = clampedTo;
    seekPosition.value = clampedTo;

    // 清空当前屏幕残留旧弹幕（对标 PiliPlus）
    danmakuEngine?.clear();

    final seq = ++_seekSeq;
    _isSeeking = true;
    _seekTargetMs = clampedMs;
    _seekStartTime = DateTime.now();
    _nativeSeekDoneTime = null;
    seekCount.value++;

    // 注意：严禁在片尾直接执行 player.state = playing！
    // 否则底层播放指针停留在 EOF 时立即尝试出帧会导致再次触发流结束，
    // 并冲刷掉正在派发的 seek(0)。正确的时序是由 _processSeekQueue 执行 seek 落地后，
    // 再根据 _userIntentPlaying 切换为 playing。

    if (_nativeSeekInFlight) {
      // 当前已有底层 native seek 在执行，排队保存最新目标（覆盖旧排队）
      _queuedSeekTargetMs = clampedMs;
      SeekProbe.note(
        'SEEK-QUEUE seq=$seq target=$clampedMs (native seek in flight)',
      );
      return;
    }

    // 短时防抖（35ms）：连续快速按键/拖动微调时合并请求，只向底层派发最终目标，避免底层网络与解码被无用中间请求堵死
    _seekDebounceTimer?.cancel();
    _seekDebounceTimer = Timer(const Duration(milliseconds: 35), () {
      if (_disposed) return;
      if (_nativeSeekInFlight) {
        _queuedSeekTargetMs = clampedMs;
        SeekProbe.note(
          'SEEK-QUEUE seq=$seq target=$clampedMs (in flight at debounce)',
        );
        return;
      }
      SeekProbe.note('SEEK-DISPATCH seq=$seq target=$clampedMs');
      _processSeekQueue(clampedMs, seq);
    });
  }

  /// 取证探针：自动执行脚本化 seek 序列（诊断专用，随 [SeekProbe] 一并移除）。
  /// 支持单会话多轮：每轮开始前重读配置，可热切换 variant（无需重启应用）。
  void _maybeStartSeekProbe() {
    if (_disposed || !SeekProbe.autoSeekEnabled) return;
    if (!SeekProbe.markAutoStarted()) return;
    unawaited(() async {
      await Future.delayed(Duration(seconds: SeekProbe.autoSeekWarmupSec));
      for (var round = 0; round < SeekProbe.autoSeekRounds; round++) {
        if (_disposed) return;
        await SeekProbe.refresh();
        SeekProbe.applyRoundVariant(round);
        _player?.setProperty(
          'demux.buffer.ranges',
          SeekProbe.demuxBufferRanges,
        );
        SeekProbe.probeRound(round);
        final targets = SeekProbe.autoSeekTargets;
        for (var i = 0; i < targets.length; i++) {
          if (_disposed) return;
          SeekProbe.probeStep(i, targets[i] * 1000);
          seek(Duration(seconds: targets[i]));
          await Future.delayed(const Duration(milliseconds: 4600));
        }
        if (round + 1 < SeekProbe.autoSeekRounds) {
          await Future.delayed(Duration(seconds: SeekProbe.roundGapSec));
        }
      }
      if (!_disposed) SeekProbe.probeDone();
    }());
  }

  void _processSeekQueue(int targetMs, int seq) {
    final player = _player;
    if (player == null || _disposed) return;

    _nativeSeekInFlight = true;
    // 取证：进入 seek 流程（在首次 FFI 读取之前）——若卡死发生在下方
    // `player.position` / `player.buffered()` 上，本行即为最后现场。
    SeekProbe.note('PROC seq=$seq target=$targetMs enter');
    unawaited(() async {
      try {
        // 精准分流 SeekFlags：
        // 1. 若定位到片头 0ms，使用 fromStart | keyFrame 极速出首个物理关键帧（对标 MDK 最佳实践），
        //    杜绝无 keyFrame 导致解码器从文件头逐帧解码引发数秒卡顿；
        // 2. 若向已播放过时间点快退（targetMs < currentPosMs），严禁传 inCache（MDK 官方规范明确要求
        //    inCache 的目标位置必须落在 (position, position + buffered] 正向区间内）。
        //    快退改用 Accurate（去 KeyFrame，MDK 文档：Accurate seek implies Backward，
        //    内部完整反向定位）；实证（2026-09-19）：fast keyFrame|Backward 快退仍不驱动
        //    外部音轨 demuxer，导致音频时钟不归位、视频高速追赶旧位置；
        // 3. 若向后快进且落在正向已缓冲水位内，使用 fromStart | keyFrame | inCache 从内存秒开；
        // 4. 若向后快进超出缓冲水位，使用 fromStart | keyFrame 从网络直接 Range 命中。
        final currentPosMs = player.position;
        final bufMax = player.buffered();
        final isForwardInCache =
            targetMs >= currentPosMs &&
            targetMs <= currentPosMs + bufMax &&
            bufMax > 0;
        final bool isBackward = targetMs < currentPosMs;
        final bool isDualTrack =
            _currentAudioUrl != null && _currentAudioUrl!.isNotEmpty;

        // 单源模式（HLS 合成清单，无外挂音轨）：快退同样使用 keyFrame 定位。
        // 实测（2026-09-24）：单源下 Accurate（flags=2）快退会间歇性不生效——demuxer
        // 仍停在 seek 前位置（target=25000 而 posMin=60262；target=30000 而 posAfter=70884），
        // 观感即「自动回退到原位 + 画面加速追赶」；改用 keyFrame 后与快进走同一定位路径。
        // P0 A/B（2026-09-25）：accurateSeek=true 时前后向均改精确落点（去 KeyFrame），
        // 用于验证双实例配置下 Accurate 是否可靠（keyFrame 落点误差 -4.8s~+4.3s，
        // 观感为「seek 到底后又回退一段」）。
        final bool singleSource = _currentAudioUrl == null;
        final bool useKeyFrame =
            !SeekProbe.accurateSeek && (!isBackward || singleSource);
        const int backwardBit = 0x10000;
        final int flagBits = targetMs == 0
            ? (mdk.SeekFlag.fromStart | mdk.SeekFlag.keyFrame)
            : (mdk.SeekFlag.fromStart |
                  (useKeyFrame ? mdk.SeekFlag.keyFrame : 0) |
                  (isBackward && SeekProbe.backwardKeyFrame ? backwardBit : 0) |
                  (isForwardInCache ? mdk.SeekFlag.inCache : 0));
        final flags = mdk.SeekFlag(flagBits);

        final mi = player.mediaInfo;
        final vTracks = mi.video ?? [];
        final aTracks = mi.audio ?? [];
        SeekProbe.mediaSnapshot(
          videoDurMs: vTracks.isNotEmpty ? vTracks.first.duration : 0,
          audioDurMs: aTracks.isNotEmpty ? aTracks.first.duration : 0,
          videoTracks: vTracks.length,
          audioTracks: aTracks.length,
          mediaDurMs: mi.duration,
        );
        SeekProbe.begin(
          seq: seq,
          targetMs: targetMs,
          posAtRequestMs: currentPosMs,
          backward: isBackward,
          dualTrack: isDualTrack,
          userIntent: _userIntentPlaying,
          flags: flagBits,
        );

        // ===== pause-during-seek 冻结（2026-09-19 取证定论）=====
        // 根因实证：mdk 0.38.0 双轨（主视频 + 外挂音轨）快退 seek 后，外挂音轨
        // demuxer 不归位 → 音频主时钟停留在旧位置（SEEK <= res 精确、posAfter 仍为
        // 旧值）→ 视频向旧时钟高速追赶（倍速快进观感）+ avsync.audio.adaptive
        // 压速音频（慢放观感），错位窗口 0.6~1.5s；快进出缓存时视频需网络 Range +
        // 关键帧解码数秒，期间音频（小流）先就绪出声。
        // 对策（对标 YouTube/PiliPlus 的 seek 转圈体验）：seek 全程冻结播放——
        //   暂停态音频后端立即静音（无压速慢放可闻）、视频渲染停在落点帧（无倍速
        //   追赶），两类错位统一收敛为标准「转圈 → 落地续播」；seek 落地 + 时钟
        //   归位后统一恢复。暂停态下解复用/解码/网络缓冲照常进行（不影响耗时）。
        if (_userIntentPlaying) {
          buffering.value = true; // 冻结窗口统一呈现加载转圈
          if (SeekProbe.pauseDuringSeek) {
            if (player.state == mdk.PlaybackState.playing) {
              player.state = mdk.PlaybackState.paused; // 冻结音频主时钟与视频渲染
            }
          } else {
            // 取证变体 E2：不暂停（保持播放让旧音频缓冲自然排空），仅静音
            player.mute = true;
            _seekWindowMuted = true;
          }
        }
        SeekProbe.stage(
          'freeze',
          'frozen=${player.state != mdk.PlaybackState.playing} '
          'inCache=${isForwardInCache ? 1 : 0} bufMax=$bufMax',
        );

        // 取证变体 E4：快退整体重开定位（诊断分支，自行完成落地记账后返回）
        if (SeekProbe.reopenOnBackward && isBackward && isDualTrack) {
          final videoUrl = _currentVideoUrl;
          if (videoUrl != null && videoUrl.isNotEmpty) {
            _audioRemountInFlight = true;
            try {
              SeekProbe.stage('reopen_begin');
              player.media = videoUrl;
              player.setMedia(_currentAudioUrl!, mdk.MediaType.audio);
              player.activeAudioTracks = const [0];
              final t0 = DateTime.now();
              final ret = await player.prepare(position: targetMs);
              final ms = DateTime.now().difference(t0).inMilliseconds;
              SeekProbe.stage('reopen_prepare', 'ret=$ret ms=$ms');
              SeekProbe.seekReturn(
                ret,
                latencyMs: ms,
                posAfterMs: -1,
                bufferedMs: -1,
                state: 'noread',
              );
            } finally {
              _audioRemountInFlight = false;
            }
            if (seq == _seekSeq && _queuedSeekTargetMs == null) {
              _seekTargetMs = targetMs;
              position.value = Duration(milliseconds: targetMs);
              seekPosition.value = Duration(milliseconds: targetMs);
              _lastPolledPosMs = targetMs;
              _nativeSeekDoneTime = DateTime.now();
              _lastSeekFinishTime = DateTime.now();
            }
          }
          return;
        }

        // 取证变体 E3：快退先把外挂音轨重挂到干净状态（此刻无 seek 在途，
        // 规避「seek 瞬态中 setMedia」的 isolate 死锁现场）
        if (SeekProbe.premountAudioBeforeSeek && isBackward && isDualTrack) {
          player.setMedia(_currentAudioUrl!, mdk.MediaType.audio);
          player.activeAudioTracks = const [0];
          SeekProbe.stage('premount_audio');
        }

        // 快退改用「重开媒体 + 带位置打开」（2026-09-24 第四笔）：
        // 机制定论——mdk 的 seek 不 flush 陈旧音频队列，旧材料把主时钟拖回
        // seek 前位置（Accurate/KeyFrame/Backward 三种 flags 实测均复现，
        // durl 单一源同样复现）。而「带位置打开」没有任何陈旧队列——它是项目
        // 首播/续播/切画质同源的已验证路径。为强制真正重载（同 URL setMedia
        // 可能不重载），轮换到下一条 CDN 候选 URL。代价：多花约 0.5~1.5s、
        // 丢弃读缓冲，全部藏在冻结转圈窗口内。
        if (SeekProbe.reopenOnBackwardSeek &&
            isBackward &&
            _videoCdnCandidates.isNotEmpty) {
          final n = _videoCdnCandidates.length;
          _currentCdnIndex = (_currentCdnIndex + 1) % n;
          final vUrl = _videoCdnCandidates[_currentCdnIndex];
          final aUrl = _audioCdnCandidates.isNotEmpty
              ? _audioCdnCandidates[_currentCdnIndex % _audioCdnCandidates.length]
              : null;
          SeekProbe.stage(
            'reopen',
            'cdn=$_currentCdnIndex/$n target=$targetMs',
          );
          // 最后一层手段（2026-09-24 第五笔）：mdk 文档明确 setState(Stopped) 会
          // 释放全部资源（含音频设备）。实测「重挂音轨 + 整媒体重开 + 带位置
          // prepare」后，音频输出队列里的旧材料仍被继续播放（时钟从 24.2s 走到
          // 26.7s），说明陈旧音频活在音频设备/输出管线里，只有停止-state 才能
          // 真正关闭它。故：先 stopped（关音频设备）→ 等 300ms（不读任何 player
          // 属性，避开瞬态）→ 再轮换 URL 重开 + 带位置 prepare。
          if (SeekProbe.reopenOnBackwardSeek) {
            try {
              player.state = mdk.PlaybackState.stopped;
              SeekProbe.stage('stop_before_reopen');
              await Future.delayed(const Duration(milliseconds: 300));
              if (_disposed) return;
            } catch (_) {}
          }
          player.media = vUrl;
          if (aUrl != null && aUrl.isNotEmpty) {
            player.setMedia(aUrl, mdk.MediaType.audio);
            player.activeAudioTracks = const [0];
          }
          final ret = await player.prepare(position: targetMs);
          SeekProbe.stage('reopen_prepare', 'ret=$ret');
          if (_disposed) return;
          _currentVideoUrl = vUrl;
          _currentAudioUrl = aUrl;
          if (ret < 0) {
            // 同 URL 未真正重载（prepare 返回 -1）等情形：退回普通 seek 兜底。
            await player.seek(position: targetMs, flags: flags);
            SeekProbe.stage('reopen_fallback_seek');
          }
          if (seq == _seekSeq && _queuedSeekTargetMs == null) {
            _seekTargetMs = targetMs;
            position.value = Duration(milliseconds: targetMs);
            seekPosition.value = Duration(milliseconds: targetMs);
            _lastPolledPosMs = targetMs;
            _nativeSeekDoneTime = DateTime.now();
            _lastSeekFinishTime = DateTime.now();
          }
          return;
        }


        // 已解码/已排队的音频，旧材料继续被渲染会把主时钟拖回 seek 前位置，
        // 视频只能加速追赶——该现象在**单一源（durl 合并流）**上同样复现
        //（target=120587 落点正确后跳到 346886，aheadMax=224862），故与外挂音轨无关。
        // 冻结（暂停）态下先关闭再启用音轨，强制重建音频管线丢弃陈旧数据；
        // 零网络开销，失败静默（不影响 seek 主流程）。
        if (SeekProbe.flushAudioOnSeek) {
          try {
            player.activeAudioTracks = const [];
            player.activeAudioTracks = const [0];
            SeekProbe.stage('audio_flush');
          } catch (_) {}
        }

        final seekStartedAt = DateTime.now();
        SeekProbe.note('MAIN seek seq=$seq -> $targetMs flags=$flagBits');
        final res = await player.seek(position: targetMs, flags: flags);
        if (_disposed) return;
        // 主 seek 返回时刻的时钟快照：该时机的 position 读取两次死锁取证均安全返回
        //（死点均在此之后）。除日志外，供下方「归位跳过重挂」判定复用，不重复读取。
        final posAfterMainSeek = player.position;
        SeekProbe.seekReturn(
          res,
          latencyMs: DateTime.now().difference(seekStartedAt).inMilliseconds,
          posAfterMs: posAfterMainSeek,
          bufferedMs: player.buffered(),
          state: '${player.state}',
        );
        SeekProbe.note(
          'MAIN seek ret seq=$seq res=$res posAfter=$posAfterMainSeek '
          'target=$targetMs state=${player.state}',
        );

        // 方案 3：第二实例按**主实例实际落点**齐步（2026-09-25 定因修复）。
        // 旧实现按「请求目标」定位，而主实例走 keyFrame 会落在偏差 -3.6s~+3.1s 的
        // 关键帧上 ⇒ 每次 seek 后固定产生 1.5~3.5s 音画差，随即被 DRIFT-HARD 硬拉
        // （可闻瞬跳）。改用 res 后两侧同点，seek 后无需硬定位。
        final audioTargetMs = res >= 0 ? res : targetMs;
        final apSeek = _audioPlayer;
        if (apSeek != null) {
          SeekProbe.stage(
            'audio_player_seek',
            'target=$audioTargetMs res=$res',
          );
          SeekProbe.note(
            'AUDIO seek seq=$seq -> $audioTargetMs (main landed res=$res)',
          );
          try {
            await apSeek
                .seek(position: audioTargetMs)
                .timeout(const Duration(seconds: 3));
          } catch (_) {}
        }

        if (res < 0) {
          AppLogger.w('PlayerController', 'player.seek error code: $res');
        }

        // ===== 双轨快退：外部音轨强制跟随（2026-09-19 取证定论）=====
        // 实证：seek 后视频 demuxer 归位成功（res 精确），但外部音轨 demuxer 不跟随，
        // 音频时钟(master)停在旧位置、视频被迫高速追赶；唯一有效手段是重挂外部音轨后
        // 二次 seek 目标。原先播放态下执行仍有 0.6~1.5s 可感知错位窗口（倍速追赶 +
        // 压速慢放）；现改为冻结（暂停）态下执行重挂+二次定位，并轮询等待音频主时钟
        // 归位后再统一恢复播放——错位窗口内无任何输出，用户只感知标准转圈加载。
        // 前置归位检查（2026-09-20 00:34 死锁取证）：若外挂音轨已跟随主 seek 归位
        //（position 与目标一致），重挂纯属多余，且归位瞬态调用 setMedia 存在死锁
        // 风险（实证 isolate 永久阻塞、程序无响应）——仅未归位时才重挂。
        // 取证变体：E3/E6 走音轨前置重挂、E4 走整体重开，基线的时间预算重挂
        // 舞步与 800ms 事后自愈仅在 E0/E1 变体下沿用。
        final bool legacyRemount = SeekProbe.legacyRemountDance;
        final bool clockSettledAfterMainSeek =
            (posAfterMainSeek - targetMs).abs() <= 1000;
        if (legacyRemount &&
            seq == _seekSeq &&
            _queuedSeekTargetMs == null &&
            isBackward &&
            isDualTrack &&
            clockSettledAfterMainSeek) {
          SeekProbe.stage(
            'remount_skip',
            'settled=1 posAfter=$posAfterMainSeek',
          );
        }
        if (legacyRemount &&
            seq == _seekSeq &&
            _queuedSeekTargetMs == null &&
            isBackward &&
            isDualTrack &&
            !clockSettledAfterMainSeek) {
          SeekProbe.stage(
            'remount_begin',
            'settled=0 posAfter=$posAfterMainSeek',
          );
          AppLogger.w(
            'PlayerController',
            'backward seek: force resync external audio track to $targetMs (frozen)',
          );
          // 零 FFI 读取的时间预算方案（2026-09-20 00:11 取证定论）：
          // 重挂后音频渲染管线中的旧缓冲继续被消费，master clock 被拖回
          // 旧位置（「跳回」），跳回瞬态 mdk 内部存在锁竞争窗口——期间
          // 任何同步 FFI 读取 position 都可能永久阻塞 isolate（实证程序
          // 直接无响应）。因此本段完全不读 position，改用纯时间预算驱动：
          //   1. 重挂+二次 seek：await 回调驱动完成（seek 返回≈跳回时刻）；
          //   2. 等 1200ms：覆盖「跳回→旧缓冲消费→时钟停滞」全过程；
          //   3. 停滞点二次重挂：旧缓冲已耗尽、管线干净，一次干净归位；
          //   4. 等 300ms 缓冲就绪后交由 finally 统一解冻。
          // 归位校验交给解冻后的 800ms 自愈兜底（playing 态执行，历史安全）。
          _audioRemountInFlight = true;
          try {
            player.setMedia(_currentAudioUrl!, mdk.MediaType.audio);
            player.activeAudioTracks = const [0];
            final res2 = await player
                .seek(
                  position: targetMs,
                  flags: const mdk.SeekFlag(
                    mdk.SeekFlag.fromStart | mdk.SeekFlag.keyFrame,
                  ),
                )
                .timeout(const Duration(seconds: 4));
            if (res2 < 0) {
              AppLogger.w(
                'PlayerController',
                'audio re-seek after backward seek failed: $res2',
              );
            }
            // 跳回+旧缓冲消费+停滞窗口：纯等待，零 FFI 读取。
            await Future.delayed(const Duration(milliseconds: 1200));
            final p2 = _player;
            if (!_disposed &&
                p2 != null &&
                seq == _seekSeq &&
                _queuedSeekTargetMs == null) {
              AppLogger.w(
                'PlayerController',
                'stagnation remount external audio track to $targetMs (frozen)',
              );
              SeekProbe.stage('remount2_begin');
              p2.setMedia(_currentAudioUrl!, mdk.MediaType.audio);
              p2.activeAudioTracks = const [0];
              final res3 = await p2
                  .seek(
                    position: targetMs,
                    flags: const mdk.SeekFlag(
                      mdk.SeekFlag.fromStart | mdk.SeekFlag.keyFrame,
                    ),
                  )
                  .timeout(const Duration(seconds: 4));
              if (res3 < 0) {
                AppLogger.w(
                  'PlayerController',
                  'audio re-seek (stagnation remount) failed: $res3',
                );
              }
              await Future.delayed(const Duration(milliseconds: 300));
            }
          } finally {
            _audioRemountInFlight = false;
          }
        }
        // ========================================================

        if (seq == _seekSeq && _queuedSeekTargetMs == null) {
          final landedMs = res >= 0 ? res : targetMs;
          _seekTargetMs = landedMs;
          final landedDuration = Duration(milliseconds: landedMs);
          position.value = landedDuration;
          seekPosition.value = landedDuration;
          _lastPolledPosMs = landedMs;
          _nativeSeekDoneTime = DateTime.now();
          _lastSeekFinishTime = DateTime.now();

          // ===== 音画同步 Seek 自愈兜底（2026-09-19 取证；基线等变体沿用）=====
          // 快退 seek 后外部音轨 demuxer 可能不归位（position 回跳旧位置、视频追赶），
          // 延迟 800ms 校验：若 position 仍远离目标且非 seek 竞争，重挂外部音轨并二次定位。
          if (legacyRemount &&
              _currentAudioUrl != null &&
              _currentAudioUrl!.isNotEmpty &&
              isBackward) {
            final checkTarget = targetMs;
            Future.delayed(const Duration(milliseconds: 800), () {
              if (_disposed || !_userIntentPlaying) return;
              final p = _player;
              if (p == null) return;
              final cur = p.position;
              SeekProbe.stage('selfheal', 'pos=$cur');
              if ((cur - checkTarget).abs() > 2500) {
                AppLogger.w(
                  'PlayerController',
                  'seek clock not settled (target=$checkTarget pos=$cur), resync external audio track',
                );
                p.setMedia(_currentAudioUrl!, mdk.MediaType.audio);
                p.activeAudioTracks = const [0];
                unawaited(
                  p.seek(
                    position: checkTarget,
                    flags: const mdk.SeekFlag(mdk.SeekFlag.fromStart),
                  ),
                );
              }
            });
          }
          // =================================================
        }
      } catch (e) {
        AppLogger.w('PlayerController', 'player.seek error: $e');
        SeekProbe.note('MAIN seek EXCEPTION seq=$seq target=$targetMs err=$e');
        if (seq == _seekSeq) {
          _nativeSeekDoneTime = DateTime.now();
          _lastSeekFinishTime = DateTime.now();
        }
      } finally {
        _nativeSeekInFlight = false;
        if (!_disposed) {
          final nextTarget = _queuedSeekTargetMs;
          if (nextTarget != null) {
            _queuedSeekTargetMs = null;
            SeekProbe.note(
              'SEEK-QUEUE-DRAIN seq=$_seekSeq next=$nextTarget',
            );
            _processSeekQueue(nextTarget, _seekSeq);
          } else {
            // 取证变体 E6：解冻前轮询等待主时钟真正收敛到目标，
            // 替代基线的固定时间预算（旧音频缓冲排空期间时钟会短暂「跳回」）。
            if (SeekProbe.convergeBeforeUnfreeze && seq == _seekSeq) {
              final deadline = DateTime.now().add(const Duration(seconds: 4));
              var settled = 0;
              while (!_disposed &&
                  settled < 2 &&
                  DateTime.now().isBefore(deadline)) {
                await Future.delayed(const Duration(milliseconds: 100));
                final cur = _player?.position ?? -1;
                final near = (cur - targetMs).abs() <= 1500;
                SeekProbe.stage('converge', 'pos=$cur near=${near ? 1 : 0}');
                settled = near ? settled + 1 : 0;
              }
            }
            // 队列排空：统一解除 seek 冻结——清除加载转圈并按用户意图恢复播放。
            // 注：曾试过在解冻前轮询 buffered()/mediaStatus 做「视频就绪」门控，
            // 实测反而让快退退回「时钟回跳 seek 前位置」的旧故障（aheadMax≈34s）——
            // 该轮询落在 seek 后瞬态窗口内（与历史上「瞬态读取 position 死锁」同类），
            // 已回滚；后续若再做就绪门控必须走事件驱动、且避开瞬态。
            buffering.value = false;
            if (_seekWindowMuted) {
              player.mute = false;
              _seekWindowMuted = false;
            }
            // 优化：解冻时先起音频实例、再起视频实例（实测音频侧起播延迟更大，
            // 先起可把 seek 后的初始偏差压小一档；残余由自适应校正接管）。
            final apOrder = _audioPlayer;
            if (apOrder != null && _userIntentPlaying) {
              try {
                if (apOrder.state != mdk.PlaybackState.playing) {
                  apOrder.state = mdk.PlaybackState.playing;
                }
                // 解冻瞬间的第二实例 position 恒为陈旧值 0（实测多次）：延迟 300ms
                // 再读，RAW 行（5s 节流）另有独立校准。
                unawaited(
                  Future<void>.delayed(const Duration(milliseconds: 300), () {
                    try {
                      SeekProbe.note(
                        'AUDIO settled pos=${apOrder.position} '
                        'state=${apOrder.state}',
                      );
                    } catch (_) {}
                  }),
                );
              } catch (_) {}
            }
            if (player.state != mdk.PlaybackState.playing &&
                _userIntentPlaying) {
              player.state = mdk.PlaybackState.playing;
            } else if (!_userIntentPlaying) {
              // 用户在冻结窗口内主动暂停：底层已是 paused（冻结用），
              // 显式同步 UI 播放态（onStateChanged 冻结抑制未广播该变化）。
              playing.value = false;
            }
            SeekProbe.resetMonitorWindow();
            SeekProbe.note(
              'UNFREEZE seq=$seq target=$targetMs uiPos=${position.value.inMilliseconds} '
              'state=${player.state} intent=${_userIntentPlaying ? 1 : 0}',
            );
            SeekProbe.unfreeze(
              SeekProbe.convergeBeforeUnfreeze ? 'converge' : 'queue_drained',
            );
          }
        }
      }
    }());
  }

  /// 触发弹幕重建（didPopNext 返回本页时调用）。
  void reloadDanmaku() {
    initDanmaku();
    danmakuEngine?.clear();
    danmakuReloadSignal.value++;
  }

  /// Phase 4.4：设置可用字幕列表（来自 playInfo 接口）。
  /// 自动根据 AI 偏好选择默认字幕并加载。
  void setSubtitleList(List<SubtitleItem> subtitles) {
    subtitle.setAvailable(subtitles);
    // 自动加载选中的字幕。
    final current = subtitle.current;
    if (current != null) {
      unawaited(subtitle.loadSubtitle(current));
    }
  }

  /// Phase 4.5：设置章节标记（来自 playInfo view_points）。
  void setViewPoints(List<ViewPoint> points) {
    viewPointsNotifier.value = List.unmodifiable(points);
  }

  /// Phase 4.5：查找当前播放位置（或指定秒数）对应的章节对象（无则返回 null）。
  ViewPoint? currentChapter([double? posSec]) {
    final sec = posSec ?? position.value.inSeconds.toDouble();
    final list = viewPointsNotifier.value;
    if (list.isEmpty) return null;
    for (final vp in list) {
      if (vp.contains(sec)) return vp;
    }
    for (int i = list.length - 1; i >= 0; i--) {
      if (sec >= list[i].from) return list[i];
    }
    return null;
  }

  /// Phase 4.5：查找当前播放位置对应的章节标题（无则返回 null）。
  String? currentChapterTitle([double? posSec]) =>
      currentChapter(posSec)?.title;

  // ── Phase 4.6 截图 ──

  /// 截取当前视频帧，返回 PNG 编码的字节流。
  ///
  /// mdk `snapshot()` 返回 BGRA 数据（stride = width*4），
  /// 通过 `dart:ui` 以 [ui.PixelFormat.bgra8888] 解码为 `ui.Image` 后导出为 PNG。
  /// 失败返回 null。
  Future<Uint8List?> screenshot() async {
    final player = _player;
    if (player == null || _disposed) return null;
    final bgra = await player.snapshot();
    if (bgra == null) return null;
    final size = videoSize.value;
    if (size == null || size.width <= 0 || size.height <= 0) return null;
    final w = size.width.toInt();
    final h = size.height.toInt();
    final image = ui.decodeImageFromPixelsSync(
      bgra,
      w,
      h,
      ui.PixelFormat.bgra8888,
    );
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    return png?.buffer.asUint8List();
  }

  // ── Phase 4.7 多音轨 + 音频归一化 ──

  /// 可用音频轨道列表（来自 mdk mediaInfo）。
  /// 每项为 (索引, 标题) — 标题取自 metadata['title'] 或语言代码。
  List<({int index, String title})> get audioTracks {
    final player = _player;
    if (player == null) return const [];
    final audio = player.mediaInfo.audio;
    if (audio == null || audio.isEmpty) return const [];
    return audio.map((s) {
      final meta = s.metadata;
      final title = meta['title']?.isNotEmpty == true
          ? meta['title']!
          : (meta['language']?.isNotEmpty == true
                ? meta['language']!
                : '音轨 ${s.index}');
      return (index: s.index, title: title);
    }).toList();
  }

  /// 当前激活的音频轨道索引列表（通常只有一个）。
  List<int> get activeAudioTrackIndices {
    final player = _player;
    if (player == null) return const [];
    return player.activeAudioTracks;
  }

  /// 当前激活音轨的编码标签（如 "AAC"、"FLAC"），用于控制条显示。
  /// 无可用音轨或编码信息时返回 null。
  String? get audioCodecLabel {
    final player = _player;
    if (player == null) return null;
    final audio = player.mediaInfo.audio;
    if (audio == null || audio.isEmpty) return null;
    final activeIndices = player.activeAudioTracks;
    final activeIndex = activeIndices.isNotEmpty ? activeIndices.first : 0;
    // 查找激活的音轨，找不到则取第一条。
    final stream = audio.firstWhere(
      (s) => s.index == activeIndex,
      orElse: () => audio.first,
    );
    final codec = stream.codec.codec.toLowerCase();
    if (codec.isEmpty) return null;
    // 编码名映射：FFmpeg 原始字符串 → 显示标签。
    return switch (codec) {
      'aac' => 'AAC',
      'flac' => 'FLAC',
      'mp3' => 'MP3',
      'opus' => 'OPUS',
      'ac3' => 'AC3',
      'eac3' => 'EAC3',
      'dts' => 'DTS',
      'truehd' => 'TrueHD',
      _ => codec.toUpperCase(),
    };
  }

  /// 切换音频轨道（内嵌轨道）。
  void switchAudioTrack(int index) {
    final player = _player;
    if (player == null || _disposed) return;
    player.activeAudioTracks = [index];
  }

  /// 是否启用音频归一化。
  bool get audioNormalizeEnabled => Pref.audioNormalization != '0';

  /// 开关/切换音频归一化模式（0=禁用, 1=动态压缩, 2=智能响度均衡，或自定义滤镜参数）。
  void setAudioNormalize(String config) {
    Pref.audioNormalization = config;
    final filter = AudioNormalization.parse(
      _playUrl?.volume,
      AudioNormalization.getParamFromConfig(config),
    );
    _player?.setProperty('audio.avfilter', filter);
  }

  /// 快速切换音频归一化开/关。
  void toggleAudioNormalize() {
    if (audioNormalizeEnabled) {
      setAudioNormalize('0');
    } else {
      setAudioNormalize(
        Pref.fallbackNormalization.isNotEmpty
            ? Pref.fallbackNormalization
            : '2',
      );
    }
  }

  /// 设置音量（0 ~ Pref.maxVolume，支持最大 200% 增益提升）。
  void setVolume(double v) {
    final clamped = v.clamp(0.0, Pref.maxVolume);
    volume.value = clamped;
    Pref.desktopVolume = clamped;
    _player?.volume = clamped / 100.0;
  }

  /// 设置播放倍速：下发 mdk playbackRate 并更新 [playbackSpeed]。
  ///
  /// 弹幕时长联动（移植自 PiliPlus `setPlaybackSpeed`）：当前引擎 option 的
  /// duration 已被旧倍速除过，需先乘回旧倍速还原 1x 基准，再除以新倍速得到
  /// 新的生效时长。等价于 `Pref.danmakuDuration / newSpeed`，但自包含、不
  /// 回查 Pref，仅依赖控制器自身持有的 currentOption + lastPlaybackSpeed。
  void setPlaybackSpeed(double v) {
    if (_disposed || v <= 0) return;
    _lastPlaybackSpeed = playbackSpeed.value;
    playbackSpeed.value = v;
    _player?.playbackRate = v;
    final engine = danmakuEngine;
    if (engine != null) {
      try {
        final current = engine.option;
        final baseDuration = current.duration * _lastPlaybackSpeed;
        final baseStaticDuration = current.staticDuration * _lastPlaybackSpeed;
        engine.updateOption(
          current.copyWith(
            duration: baseDuration / v,
            staticDuration: baseStaticDuration / v,
          ),
        );
      } catch (_) {}
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _queuedSeekTargetMs = null;
    _nativeSeekInFlight = false;
    _nativeSeekDoneTime = null;
    SyncTrace.log('PlayerCtrl', 'dispose enter, playerCount=$_playerCount');
    unawaited(reportCurrentProgress());
    detachListeners();
    _pollTimer?.cancel();
    _pollTimer = null;
    _bufferingDebounceTimer?.cancel();
    _bufferingDebounceTimer = null;
    _seekDebounceTimer?.cancel();
    _seekDebounceTimer = null;
    _heartBeatTimer?.cancel();
    _heartBeatTimer = null;
    sponsorBlock?.dispose();
    sponsorBlock = null;
    danmaku?.dispose();
    danmaku = null;
    danmakuEngine = null;
    // 引用计数递减，归零时才真正释放全局单例 mdk.Player。
    _playerCount--;
    if (_playerCount <= 0) {
      _playerCount = 0;
      final player = _sharedPlayer;
      _sharedPlayer = null;
      if (player != null) {
        SyncTrace.log('PlayerCtrl', 'last ref: set state=stopped');
        // 先置 stopped：停止 mdk 解码循环与渲染回调（setState 本身是异步请求，
        // 但能让渲染回调尽快停发）。
        player.state = mdk.PlaybackState.stopped;
        SyncTrace.log(
          'PlayerCtrl',
          'teardown deferred by ${_sharedTeardownDelay.inMilliseconds}ms',
        );
        // 延迟销毁共享 player（防御性措施）：
        // fvp 的 ReleaseRT 处理器在 UnregisterTexture 后立即销毁
        // TexturePlayer（D3D11 纹理/表面描述符/回调表），与引擎光栅线程的
        // 合成存在理论竞态（fvp#321 同族）。页面 dispose 发生在 pop 转场
        // 结束、纹理离开 layer tree 之后，延迟 400ms（>20 帧 @60fps）让
        // 光栅管线排空后再释放，彻底关闭该窗口。
        // 注：返回崩溃的真正根因是 Flutter 3.47 Windows 默认启用的
        // Impeller 渲染后端对外部纹理的转场缺陷（已在
        // windows/runner/main.cpp 禁用 Impeller 回退 Skia 规避），
        // 本延迟为第二道防线。无障碍桥假设已被对照实验排除。
        AppLogger.w(
          'PlayerController',
          'shared player teardown deferred by ${_sharedTeardownDelay.inMilliseconds}ms for raster drain',
        );
        Future.delayed(_sharedTeardownDelay, () {
          SyncTrace.log('PlayerCtrl', 'delayed dispose: calling fvp dispose');
          player.dispose();
          SyncTrace.log('PlayerCtrl', 'delayed dispose: fvp dispose returned');
        });
      }
      // 第二实例（纯音频）与共享主实例同生命周期：refcount 归零时一并释放
      //（2026-09-25 清理：此前仅被置 stopped，解码器/音频设备虽已释放但对象常驻；
      //  此处补对象级 dispose，避免跨会话残留）。
      final audioPlayer = _audioPlayer;
      _audioPlayer = null;
      if (audioPlayer != null) {
        try {
          audioPlayer.state = mdk.PlaybackState.stopped;
        } catch (_) {}
        Future.delayed(_sharedTeardownDelay, () {
          try {
            audioPlayer.dispose();
            SyncTrace.log('PlayerCtrl', 'second instance disposed');
          } catch (_) {}
        });
      }
    } else {
      SyncTrace.log('PlayerCtrl', 'refs remain=$_playerCount, set paused');
      _sharedPlayer?.state = mdk.PlaybackState.paused;
    }
    // 不 dispose 任何 ValueNotifier，让 GC 自动回收
    // 避免 UI 中的 ValueListenableBuilder 访问已 dispose 的 ValueNotifier
    // 导致崩溃
  }
}
