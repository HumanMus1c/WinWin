import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:fvp/mdk.dart' as mdk;

import 'package:winwin/core/account/account.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/core/cache/play_url_cache.dart';
import 'package:winwin/core/log/sync_trace.dart';
import 'package:winwin/core/log/app_logger.dart';
import 'package:winwin/core/player/sponsorblock_usecase.dart';
import 'package:winwin/core/policy/cdn_policy.dart';
import 'package:winwin/core/policy/stream_selection_policy.dart';
import 'package:winwin/core/policy/video_load_policy.dart';
import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/core/storage/storage_key.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/grpc/bilibili/community/service/dm/v1.pb.dart' hide SubtitleItem;
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/pgc.dart';
import 'package:winwin/http/video.dart';
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
  }) {
    _playerCount++;
    _sharedPlayer ??= _createPlayer();
    attachListeners(); // 内部启动轮询（_startPolling）
  }

  final String bvid;
  final int cid;
  final int? epId;
  final int? seasonId;

  /// 稿件 avid（由详情页 load 完成后设置，供心跳上报使用）。
  int? aid;

  // ── 全局单例 mdk 播放器（跨页面共享，参照 PiliPlus PlPlayerController）──
  static mdk.Player? _sharedPlayer;
  static int _playerCount = 0;

  /// 共享 player 延迟销毁时长：等引擎光栅线程排空对视频纹理的合成，
  /// 避开 fvp ReleaseRT 立即销毁纹理对象与光栅并发的崩溃竞态（见 dispose）。
  static const Duration _sharedTeardownDelay = Duration(milliseconds: 400);

  /// 当前 controller 访问的播放器（即全局单例）。
  mdk.Player? get _player => _sharedPlayer;

  // ── 对外状态（ValueNotifier）──
  final ValueNotifier<bool> playing = ValueNotifier(false);
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> duration = ValueNotifier(Duration.zero);
  final ValueNotifier<bool> buffering = ValueNotifier(false);
  final ValueNotifier<String?> error = ValueNotifier(null);
  final ValueNotifier<bool> ready = ValueNotifier(false);
  final ValueNotifier<double> volume = ValueNotifier(80);

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

  /// 弹幕重建信号：didPopNext 返回本页时 ++，WinWinDanmaku 监听后重建
  /// dm（清空旧缓存重新拉取）+ clear 引擎 + 重置去重标记。等效于 PiliPlus
  /// 的 videoState 卸载-重建 PlDanmaku，但不需要销毁 DanmakuScreen（避免
  /// 引擎闪烁）。原因：PlayerPanel 始终挂载，WinWinDanmaku 不会随路由重建，
  /// 导致弹幕引擎在 pause/resume 后状态僵死，弹幕无法恢复。
  final ValueNotifier<int> danmakuReloadSignal = ValueNotifier(0);

  /// 可选倍速列表（来自 Pref.speedList）。
  List<double> get speedList => Pref.speedList;

  /// 弹幕数据控制器，由弹幕视图（WinWinDanmaku）创建并挂载。
  WinWinDanmakuController? danmaku;

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
  final ValueNotifier<List<ViewPoint>> viewPointsNotifier =
      ValueNotifier(const []);
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
  /// 缓冲假死计时（毫秒），用于超时检测与自愈。
  int _bufferingStallMs = 0;
  /// 用户意图播放标志（playWhenReady）：与底层瞬态解码器 playing 状态解耦。
  /// 用户点击暂停时为 false，起播/恢复时为 true。用于看门狗准确判定卡死。
  bool _userIntentPlaying = true;
  /// 上次轮询到的播放进度（毫秒），用于检测进度是否停滞。
  int _lastPolledPosMs = -1;
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

  // ── 心跳上报（Phase 4.2）──
  /// 心跳定时器：每 5 秒上报一次播放进度。
  Timer? _heartBeatTimer;
  /// 上次心跳上报时的播放状态，用于检测状态变化。
  /// null 表示尚未上报过任何心跳（首次状态变化报 play_type=0）。
  bool? _lastHeartBeatPlaying;
  /// 累计播放时长（秒），用于满足 "playing ≥5s" 触发条件。
  int _playingAccumSec = 0;
  /// 是否已上报过结束（play_type=-1），避免重复。
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

    // 显式设置 video decoders（与 fvp video_player_mdk.dart Windows 默认一致）。
    // mdk.Player() 默认 decoder 为 'auto'（通常=FFmpeg），但不显式设置时
    // D3D11 硬解 / dav1d AV1 软解不会被自动选中，导致 HEVC/AV1 decode error。
    // 顺序即优先级：D3D11 硬解 → FFmpeg 软解 → dav1d AV1 专用软解。
    player.videoDecoders = const ['D3D11', 'FFmpeg', 'dav1d'];

    // 网络流稳健性 / 格式探测（参照 fvp video_player_mdk.dart 默认项与 FFmpeg 规范）。
    player.setProperty('video.decoder', 'shader_resource=0');
    player.setProperty('avformat.strict', 'experimental');
    player.setProperty('avformat.safe', '0');
    player.setProperty('avformat.rtsp_transport', 'tcp');
    player.setProperty('avformat.extension_picky', '0');
    player.setProperty('avformat.allowed_segment_extensions', 'ALL');

    // 全量网络流断线自动重连与防死锁超时配置：
    // B站 CDN 在客户端由于缓冲满暂停读取时可能在 60s 左右主动切断连接。
    // reconnect_at_eof: 遇到服务端非预期 FIN/EOF 时自动以 Range 请求重连，杜绝误判为音画结束。
    // reconnect_streamed: 开启流式传输重连。
    // reconnect_on_network_error: 偶发网络波动或丢包时重试。
    // reconnect_on_http_error: 瞬态 4xx/5xx 错误时重试。
    // avio.timeout / avio.rw_timeout: FFmpeg 默认无超时无限阻塞，设置 10s 超时防死锁（微秒）。
    player.setProperty('avio.reconnect', '1');
    player.setProperty('avio.reconnect_at_eof', '1');
    player.setProperty('avio.reconnect_streamed', '1');
    player.setProperty('avio.reconnect_delay_max', '5');
    player.setProperty('avio.reconnect_on_network_error', '1');
    player.setProperty('avio.reconnect_on_http_error', '4xx,5xx');
    player.setProperty('avio.timeout', '10000000');
    player.setProperty('avio.rw_timeout', '10000000');

    // 解复用器包缓存与容错：加速 seek，避免重复请求 CDN，容忍轻微网络丢包。
    player.setProperty('demux.buffer.ranges', '50');
    player.setProperty('demux.buffer.protocols', 'http,https');
    player.setProperty('demux.max_errors', '50');

    // 缓冲窗口（VOD 点播模式）：
    // min: 2000ms（起播与再缓冲防抖门限，避免 1s 极小缓冲导致的反复启停死循环）；
    // max: 最大缓冲窗口（结合 Pref.bufferSec 确保充足网络水位，钳制在 30s~90s，
    // 避免 3 分钟以上过大缓冲导致网络长时间静默而触发 CDN 60s 闲置断线）。
    final maxBufMs = (Pref.bufferSec * 1000).clamp(30000.0, 90000.0).toInt();
    player.setBufferRange(min: 2000, max: maxBufMs);

    player.volume = volume.value / 100.0;
    return player;
  }

  /// 将本 controller 的事件监听挂载到共享 [_sharedPlayer]。
  /// 每个 controller 实例持有自己的订阅，dispose 时由 [detachListeners] 移除。
  /// 供页面 [RouteAware.didPopNext] 重新挂载（参照 PiliPlus addStatusLister）。
  void attachListeners() {
    final player = _sharedPlayer;
    if (player == null) return;
    _subscriptions
      ..add(player.onStateChanged.listen((event) {
        if (_disposed) return;
        playing.value = event.newValue == mdk.PlaybackState.playing;
      }))
      ..add(player.onEvent.listen((ev) {
        if (_disposed || _loading || _isRecovering) return;
        // NOTE: for 'reader.buffering' the error field is progress [0,100],
        // not an error code; real mdk failures carry negative codes.
        // -1 语义同 prepare 的 -1（already loading/open），不是硬错误：
        // 共享 player 切换 media 时 setMedia 已触发 open，onEvent "open" 返回 -1
        // 表示"已在加载"。仅对 < -1 的硬错误报错（与 prepare 判断一致）。
        if (ev.error < -1) {
          AppLogger.e('PlayerController', 'onEvent error: code=${ev.error} detail=${ev.detail}');
          // 参照 BiliPai PlayerErrorRecoveryPolicy：网络断开/错误时优先触发自愈重连或切线，
          // 而非直接向用户弹窗中断播放。
          if (ready.value && _userIntentPlaying && _stallRecoveryRetryCount < 3) {
            AppLogger.w('PlayerController', 'Triggering stream self-healing after onEvent error');
            unawaited(_recoverStalledStream(isNetworkError: true));
            return;
          }
          error.value = '播放错误 ${ev.error}: ${ev.detail}';
        }
      }))
      ..add(player.onMediaStatus.listen((event) {
        if (_disposed) return;
        final oldValue = event.oldValue;
        final newValue = event.newValue;
        // 缓冲中 / 缓冲完成（同时监听 buffering 与 stalled 位，映射同 fvp 的 bufferingStart / bufferingEnd）。
        final wasBufferingOrStalled =
            oldValue.test(mdk.MediaStatus.buffering | mdk.MediaStatus.stalled);
        final isBufferingOrStalled =
            newValue.test(mdk.MediaStatus.buffering | mdk.MediaStatus.stalled);
        if (!wasBufferingOrStalled && isBufferingOrStalled) {
          buffering.value = true;
        }
        if (!oldValue.test(mdk.MediaStatus.buffered) &&
            newValue.test(mdk.MediaStatus.buffered)) {
          buffering.value = false;
          _bufferingStallMs = 0;
          _stallRecoveryRetryCount = 0;
          AppLogger.i('PlayerController', 'onMediaStatus: buffered (duration=${player.mediaInfo.duration}ms)');
          // media 加载完成：获取正确的 duration 和 videoSize。
          // 避免切换 media 时拿到旧 media 的值（B 的 duration 比 A 长，
          // 导致时间轴超出 A 的长度）。
          final ms = player.mediaInfo.duration;
          if (ms > 0) duration.value = Duration(milliseconds: ms);
          unawaited(player.textureSize.then((size) {
            if (!_disposed && size != null) videoSize.value = size;
          }));
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
      }));
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
      final player = _player;
      if (_disposed || player == null || !ready.value) return;
      final posMs = player.position;
      final newPos = Duration(milliseconds: posMs);
      if (position.value != newPos) {
        position.value = newPos;
      }
      // 进度推进检测：若播放进度在前进，清零卡顿计时。
      final isPosAdvancing = posMs > _lastPolledPosMs;
      if (isPosAdvancing) {
        _lastPolledPosMs = posMs;
        _bufferingStallMs = 0;
      }

      // 卡死看门狗（Watchdog，参照 BiliPai resolvePlaybackStallRecoveryDecision）：
      // 1. 用户意图播放（_userIntentPlaying，非手动暂停）；
      // 2. 处于缓冲中（buffering.value）或底层报告 stalled，且进度未推进；
      // 3. 达到 4.5 秒门限（早于 CDN 60s 闲置与长缓冲超时，及时自愈无感续播）。
      if (_userIntentPlaying && !buffering.value && !isPosAdvancing && playing.value) {
        final status = player.mediaStatus;
        if (status.test(mdk.MediaStatus.stalled | mdk.MediaStatus.buffering) || player.buffered() <= 0) {
          buffering.value = true;
        }
      }

      if (_userIntentPlaying && buffering.value && !_isRecovering) {
        _bufferingStallMs += 100;
        if (_bufferingStallMs >= 4500) {
          _bufferingStallMs = 0;
          AppLogger.w(
            'PlayerController',
            'Buffering stall detected (4.5s) at ${posMs}ms, triggering stream recovery',
          );
          unawaited(_recoverStalledStream());
        }
      } else if (!_userIntentPlaying) {
        _bufferingStallMs = 0;
      }
      // SponsorBlock 自动跳过：检查当前位置是否在可跳过段落内。
      if (sponsorBlockEnabled) {
        final target = sponsorBlock?.computeSkipTarget(posMs / 1000.0);
        if (target != null) {
          unawaited(player.seek(position: (target * 1000).toInt()));
        }
      }
      // 播放结束检测：进度达到 duration 的 99% 视为播完，上报 -1。
      _maybeReportPlaybackEnd();
    });
  }

  /// 启动心跳定时器（每 5 秒上报一次进度）。
  /// 在 load 成功后调用，dispose / detachListeners 时停止。
  void _startHeartBeat() {
    _heartBeatTimer?.cancel();
    _playingAccumSec = 0;
    _lastHeartBeatPlaying = null;
    _reportedEnd = false;
    _heartBeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_disposed) return;
      // 未登录或用户关闭历史记录时不报。
      if (!Accounts.main.isLogin || Pref.historyPause) return;
      final aid = this.aid;
      if (aid == null || aid <= 0) return;
      final isPlaying = playing.value;
      // 播放中累计 ≥5s 才上报心跳。
      if (isPlaying) {
        _playingAccumSec += 5;
      }
      // 状态变化（playing↔paused）时上报：首次变化报 0（开始），
      // 其后 1=暂停 / 2=继续（参照 PiliPlus 心跳语义）。
      if (_lastHeartBeatPlaying != isPlaying) {
        final playType = _lastHeartBeatPlaying == null
            ? 0
            : (isPlaying ? 2 : 1);
        _lastHeartBeatPlaying = isPlaying;
        _sendHeartBeat(playType: playType);
        return;
      }
      // 持续播放中且累计 ≥5s：上报心跳进度。
      if (isPlaying && _playingAccumSec >= 5) {
        _sendHeartBeat(playType: 0);
      }
    });
  }

  /// 发送一次心跳（best-effort，失败静默）。
  void _sendHeartBeat({required int playType}) {
    final aid = this.aid;
    if (aid == null || aid <= 0) return;
    final progressSec = position.value.inSeconds;
    unawaited(
      VideoHttp.heartBeat(
        aid: aid,
        cid: cid,
        playType: playType,
        progressSec: progressSec,
      ).then((res) {
        if (!kDebugMode) return;
        if (res case Error(:final errMsg)) {
          debugPrint('HeartBeat: report failed: $errMsg');
        }
      }),
    );
  }

  /// 播放结束上报：进度达到 duration 99% 时上报 play_type=-1（仅一次）。
  void _maybeReportPlaybackEnd() {
    if (_reportedEnd) return;
    if (!Accounts.main.isLogin || Pref.historyPause) return;
    final aid = this.aid;
    if (aid == null || aid <= 0) return;
    final dur = duration.value;
    if (dur.inSeconds <= 0) return;
    final pos = position.value;
    // 进度达到 99% 视为播完。
    if (pos.inMilliseconds >= dur.inMilliseconds * 0.99) {
      _reportedEnd = true;
      unawaited(
        VideoHttp.heartBeat(
          aid: aid,
          cid: cid,
          playType: 3,
          progressSec: -1,
        ).then((_) async {
          // 同时上报历史进度（progress = 0 表示已看完）。
          await VideoHttp.reportHistory(aid: aid, cid: cid, progressSec: 0);
        }),
      );
    }
  }

  /// 上报当前进度（页面退出/被覆盖时调用，Phase 4.2 didPushNext）。
  Future<void> reportCurrentProgress() async {
    if (!Accounts.main.isLogin || Pref.historyPause) return;
    final aid = this.aid;
    if (aid == null || aid <= 0) return;
    final progressSec = position.value.inSeconds;
    if (progressSec <= 0) return;
    await VideoHttp.reportHistory(aid: aid, cid: cid, progressSec: progressSec);
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
        await done.future.timeout(const Duration(seconds: 15), onTimeout: () {});
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
      playing.value = false;

      // 1. PlayUrlCache：先查缓存，命中且未过期则跳过 HTTP。
      final cacheKey = (epId != null && epId! > 0) ? 'ep_$epId' : bvid;
      PlayUrlModel? playUrl =
          playUrlCache.get(cacheKey, cid, requestedQuality: qn) as PlayUrlModel?;
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
            result = await VideoHttp.videoUrl(bvid: bvid, cid: cid, qn: qn);
          }
        } else {
          result = await VideoHttp.videoUrl(bvid: bvid, cid: cid, qn: qn);
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
          dashVideoIds: playUrl.dash?.video
                  ?.map((v) => v.id ?? 0)
                  .toList(growable: false) ??
              const [],
        )) {
          playUrlCache.put(
            cacheKey,
            cid,
            playUrl,
            quality: qn,
          );
        }
      }

      // 2. StreamSelectionPolicy：编解码器感知选流（AV1 > HEVC > AVC），
      // 替换原 pickVideo/pickAudio。桌面端默认全档位解码能力。
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
        if (durls != null && durls.isNotEmpty && durls.first.playUrls.isNotEmpty) {
          _videoCdnCandidates = CdnPolicy.resolveAllUrls(durls.first.playUrls);
          isDurlFallback = _videoCdnCandidates.isNotEmpty;
        }
      }

      if (_videoCdnCandidates.isEmpty) {
        error.value = '未获取到可播放的视频流';
        return;
      }

      // 提取音频候选 URL（durl 模式已内嵌音频无需外部挂载）
      _audioCdnCandidates = (isDurlFallback || audio == null || audio.playUrls.isEmpty)
          ? const []
          : CdnPolicy.resolveAllUrls(audio.playUrls, isAudio: true);

      _currentCdnIndex = 0;
      final videoUrl = _videoCdnCandidates.first;
      final audioUrl = _audioCdnCandidates.isNotEmpty ? _audioCdnCandidates.first : null;
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
          final cookieStr = cookies.map((c) => '${c.name}=${c.value}').join('; ');
          headers += 'Cookie: $cookieStr\r\n';
        }
      }
      player.setProperty('avio.headers', headers);
      // Phase 4.7：音频归一化滤镜作为 player 属性在 prepare 前下发，
      // 避免在 media 已打开/播放中切换 avfilter 触发音频轨重初始化干扰状态。
      if (_audioNormalizeEnabled) {
        player.setProperty('audio.avfilter', 'loudnorm');
      }

      // 1. 设置主视频 media。
      AppLogger.w(
        'PlayerController',
        'setMedia video: cdn=${Pref.defaultCDNService.name} candidates=${_videoCdnCandidates.length} videoUrl=$videoUrl audioUrl=$audioUrl',
      );
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

      // 2. prepare 加载首帧。
      // prepare 不传 position：prepare 返回 -1（already loading）时
      // position 参数会被 native 忽略，导致进度没恢复。改用 prepare() 只
      // 加载首帧，进度恢复统一用 seek（ret >= 0 时立即 seek，ret == -1
      // 时延迟到 onMediaStatus.buffered 事件后 seek）。
      final ret = await player.prepare();
      AppLogger.w('PlayerController', 'prepare ret=$ret (0=ok, -1=already loading, <-1=error)');
      if (_disposed) return;
      // prepare 返回值语义（见 fvp player.dart 注释）：
      //   0: streams==0 无效媒体，否则成功
      //  -1: already loading or loaded（setMedia 已触发加载，无需重复 prepare）
      //  -4: 越界  -10: 内部错误
      // 共享 player 从 A 切换到 B 时，setMedia 已开始加载 B 的 media，prepare
      // 常返回 -1。这不是失败：真正的失败由 onEvent 错误事件（ev.error < 0）
      // 设置 error。仅对 < -1 的硬错误报错。
      if (ret < -1) {
        AppLogger.e('PlayerController', 'prepare failed: ret=$ret, aborting load');
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
      player.state =
          autoplay ? mdk.PlaybackState.playing : mdk.PlaybackState.paused;
      ready.value = true;
      AppLogger.w('PlayerController', 'ready=true, state=${player.state}, textureId=${player.textureId}');
      // Phase 4.2：播放就绪后启动心跳定时器（每 5 秒上报进度）。
      _startHeartBeat();

      // SponsorBlock 段落加载：失败不阻断播放，仅记录日志。
      if (sponsorBlockEnabled) {
        sponsorBlock ??= SponsorBlockUseCase();
        unawaited(
          sponsorBlock!.fetchSegments(bvid: bvid).then((res) {
            if (_disposed) return;
            final segments = res.dataOrNull;
            if (segments == null) return;
            if (kDebugMode && segments.isNotEmpty) {
              debugPrint('SponsorBlock: loaded ${segments.length} segments for $bvid');
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
      final currentIds = currentPlayUrl.dash?.video
              ?.map((v) => v.id ?? 0)
              .toList(growable: false) ??
          const <int>[];
      final shouldUpgrade = VideoLoadPolicy.shouldScheduleHdrAutoUpgrade(
        isInitialRequest: true,
        isAutoHighestQuality: Pref.autoHighestQuality,
        isVip: userInfo?.isVip ?? false,
        isMobileData: false,
        hasAccessToken: account.accessKey != null && account.accessKey!.isNotEmpty,
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
    _isRecovering = true;
    _stallRecoveryRetryCount++;
    try {
      final resumePosMs = player.position;
      final resumeDuration = Duration(milliseconds: resumePosMs > 0 ? resumePosMs : 0);

      AppLogger.w(
        'PlayerController',
        'Executing playback stall recovery (retry=$_stallRecoveryRetryCount, netErr=$isNetworkError) at ${resumeDuration.inSeconds}s',
      );

      // 1. 若有多条可用 CDN 镜像，轮换切换到下一条线路（参照 BiliPai PlaybackStallRecoveryPolicy）
      if (_videoCdnCandidates.length > 1) {
        _currentCdnIndex = (_currentCdnIndex + 1) % _videoCdnCandidates.length;
        _currentVideoUrl = _videoCdnCandidates[_currentCdnIndex];
        if (_audioCdnCandidates.isNotEmpty) {
          _currentAudioUrl = _audioCdnCandidates[_currentCdnIndex % _audioCdnCandidates.length];
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
      AppLogger.e('PlayerController', 'Stream stall recovery failed', error: e, stackTrace: s);
    } finally {
      _isRecovering = false;
    }
  }

  void playOrPause() {
    final player = _player;
    if (player == null || _disposed) return;
    if (player.state == mdk.PlaybackState.playing) {
      _userIntentPlaying = false;
      _bufferingStallMs = 0;
      player.state = mdk.PlaybackState.paused;
    } else {
      _userIntentPlaying = true;
      _bufferingStallMs = 0;
      player.state = mdk.PlaybackState.playing;
    }
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
  }

  /// 恢复播放（仅在暂停态生效），用于折叠自动暂停后展开时恢复。
  /// 与 [playOrPause] 不同，此方法不引入切换语义，避免误触其它状态。
  void play() {
    final player = _player;
    if (player == null || _disposed) return;
    _userIntentPlaying = true;
    _bufferingStallMs = 0;
    if (player.state == mdk.PlaybackState.paused) {
      player.state = mdk.PlaybackState.playing;
    }
  }

  void seek(Duration to) {
    final player = _player;
    if (player == null || _disposed) return;
    _bufferingStallMs = 0;
    _lastPolledPosMs = to.inMilliseconds;
    unawaited(player.seek(position: to.inMilliseconds));
    seekCount.value++;
  }

  /// 触发弹幕重建（didPopNext 返回本页时调用）。
  void reloadDanmaku() => danmakuReloadSignal.value++;

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
  String? currentChapterTitle([double? posSec]) => currentChapter(posSec)?.title;

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

  /// 是否启用音频归一化（loudnorm 滤镜）。
  bool _audioNormalizeEnabled = Pref.enableAudioNormalize;
  bool get audioNormalizeEnabled => _audioNormalizeEnabled;

  /// 开关音频归一化（Phase 4.7）。
  /// 使用 FFmpeg loudnorm 滤镜，播放时立即生效。持久化到 Pref。
  void setAudioNormalize(bool enabled) {
    _audioNormalizeEnabled = enabled;
    GStorage.setting.put(SettingBoxKey.enableAudioNormalize, enabled);
    final player = _player;
    if (player == null || _disposed) return;
    if (enabled) {
      player.setProperty('audio.avfilter', 'loudnorm');
    } else {
      player.setProperty('audio.avfilter', '');
    }
  }

  /// 设置音量（0-100）。
  void setVolume(double v) {
    final clamped = v.clamp(0.0, 100.0);
    volume.value = clamped;
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
    SyncTrace.log('PlayerCtrl', 'dispose enter, playerCount=$_playerCount');
    unawaited(reportCurrentProgress());
    detachListeners();
    _pollTimer?.cancel();
    _pollTimer = null;
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
    } else {
      SyncTrace.log('PlayerCtrl', 'refs remain=$_playerCount, set paused');
      _sharedPlayer?.state = mdk.PlaybackState.paused;
    }
    // 不 dispose 任何 ValueNotifier，让 GC 自动回收
    // 避免 UI 中的 ValueListenableBuilder 访问已 dispose 的 ValueNotifier
    // 导致崩溃
  }
}
