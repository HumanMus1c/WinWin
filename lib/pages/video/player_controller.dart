import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:fvp/mdk.dart' as mdk;

import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/core/cache/play_url_cache.dart';
import 'package:winwin/core/log/app_logger.dart';
import 'package:winwin/core/player/sponsorblock_usecase.dart';
import 'package:winwin/core/policy/stream_selection_policy.dart';
import 'package:winwin/core/policy/video_load_policy.dart';
import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/core/storage/storage_key.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/grpc/bilibili/community/service/dm/v1.pb.dart' hide SubtitleItem;
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/video.dart';
import 'package:winwin/models/user/user_info.dart';
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
  WinWinPlayerController({required this.bvid, required this.cid}) {
    _playerCount++;
    _sharedPlayer ??= _createPlayer();
    attachListeners(); // 内部启动轮询（_startPolling）
  }

  final String bvid;
  final int cid;

  /// 稿件 avid（由详情页 load 完成后设置，供心跳上报使用）。
  int? aid;

  // ── 全局单例 mdk 播放器（跨页面共享，参照 PiliPlus PlPlayerController）──
  static mdk.Player? _sharedPlayer;
  static int _playerCount = 0;

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
  /// 由 [setViewPoints] 设置，供面板在进度条上渲染章节标记。
  List<ViewPoint> _viewPoints = const [];
  List<ViewPoint> get viewPoints => _viewPoints;

  /// 是否启用 SponsorBlock 自动跳过（默认 true，用户可在设置中关闭）。
  bool sponsorBlockEnabled = Pref.enableSponsorBlock;

  /// 弹幕显示不透明度（0-1）：设置面板改动时写入，弹幕层监听实时刷新。
  final ValueNotifier<double> danmakuOpacity = ValueNotifier(
    Pref.danmakuOpacity,
  );

  // ── 清晰度状态 ──
  PlayUrlModel? _playUrl;
  int _currentQn = 80;

  /// HDR 自动升级是否已尝试过（避免循环升级）。
  bool _hdrUpgradeAttempted = false;
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

    // 网络流稳健性 / 格式探测（参照 fvp video_player_mdk.dart 的默认项）。
    player.setProperty('avio.reconnect', '1');
    player.setProperty('avio.reconnect_delay_max', '7');
    player.setProperty('avformat.extension_picky', '0');
    // 扩大缓冲上限，减少在线 DASH 卡顿（mdk 默认 max 仅 4 秒）。
    player.setBufferRange(min: 1000, max: 30000);

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
        if (_disposed || _loading) return;
        // NOTE: for 'reader.buffering' the error field is progress [0,100],
        // not an error code; real mdk failures carry negative codes.
        // -1 语义同 prepare 的 -1（already loading/open），不是硬错误：
        // 共享 player 切换 media 时 setMedia 已触发 open，onEvent "open" 返回 -1
        // 表示"已在加载"。仅对 < -1 的硬错误报错（与 prepare 判断一致）。
        if (ev.error < -1) {
          // 直接覆盖：让最新错误显示给用户。原 ??= 会忽略后续错误，
          // 网络恢复后又断开时用户看不到最新错误信息。
          AppLogger.e('PlayerController', 'onEvent error: code=${ev.error} detail=${ev.detail}');
          error.value = '播放错误 ${ev.error}: ${ev.detail}';
        }
      }))
      ..add(player.onMediaStatus.listen((event) {
        if (_disposed) return;
        final oldValue = event.oldValue;
        final newValue = event.newValue;
        // 缓冲中 / 缓冲完成（映射同 fvp 的 bufferingStart / bufferingEnd）。
        if (!oldValue.test(mdk.MediaStatus.buffering) &&
            newValue.test(mdk.MediaStatus.buffering)) {
          buffering.value = true;
        }
        if (!oldValue.test(mdk.MediaStatus.buffered) &&
            newValue.test(mdk.MediaStatus.buffered)) {
          buffering.value = false;
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
  }

  void _syncTextureId() {
    final player = _player;
    if (_disposed || player == null) return;
    textureId.value = player.textureId.value;
  }

  /// mdk 没有 position/duration 流，用 250ms 轮询更新 ValueNotifier。
  /// duration 不在此获取：切换 media 时 mediaInfo.duration 可能返回旧值
  /// （B 的 duration 比 A 长，导致时间轴超出 A 的长度）。duration 改为
  /// 在 onMediaStatus.buffered 事件中获取，确保是新 media 的值。
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final player = _player;
      if (_disposed || player == null || !ready.value) return;
      final posMs = player.position;
      position.value = Duration(milliseconds: posMs);
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
        ).then((_) {
          // 同时上报历史进度（progress = 0 表示已看完）。
          return VideoHttp.reportHistory(aid: aid, cid: cid, progressSec: 0);
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
      PlayUrlModel? playUrl =
          playUrlCache.get(bvid, cid, requestedQuality: qn) as PlayUrlModel?;
      if (playUrl == null) {
        final result = await VideoHttp.videoUrl(bvid: bvid, cid: cid, qn: qn);
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
            bvid,
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
      final videoUrl = video?.baseUrl;
      if (video == null || videoUrl == null || videoUrl.isEmpty) {
        error.value = '未获取到可播放的视频流';
        return;
      }

      _playUrl = playUrl;
      _currentQn = video.id ?? qn;
      // 通知面板重建画质按钮（_playUrl 为普通字段，不自动触发重建）。
      qualityVersion.value++;

      if (kDebugMode) {
        debugPrint(
          'PlayStream: bvid=$bvid qn=$_currentQn codec=${selection.videoCodec.name} '
          'audio=${selection.audioKind.name}',
        );
      }

      // 请求头经 'avio.headers' 属性下发，格式为 "Key: Value\r\n" 列表，
      // 对该 Player 打开的所有源（含外部音轨）生效。
      player.setProperty(
        'avio.headers',
        'Referer: $_referer\r\nUser-Agent: $_pcUserAgent\r\n',
      );
      // Phase 4.7：音频归一化滤镜作为 player 属性在 prepare 前下发，
      // 避免在 media 已打开/播放中切换 avfilter 触发音频轨重初始化干扰状态。
      if (_audioNormalizeEnabled) {
        player.setProperty('audio.avfilter', 'loudnorm');
      }

      // 1. 设置主视频 media。
      AppLogger.w('PlayerController', 'setMedia video: url=$videoUrl audioUrl=${audio?.baseUrl}');
      player.media = videoUrl;
      // DASH 分离音轨：以外部音轨方式挂载（prepare 之前）。
      // 参照 fvp setExternalAudio → setMedia(url, MediaType.audio) 用法：
      // native setMedia(url 变化) 会重置轨道，setMediaForType 挂载外部音轨
      // 后必须调用 setActiveTracks 显式激活，否则音频轨道不会被自动选中
      // （B站 DASH 主 media 为纯视频流，无内部音频轨，导致无声）。
      // 在 prepare 之前挂载，使 prepare 能一次性加载主视频 + 外部音轨。
      final audioUrl = audio?.baseUrl;
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

  void playOrPause() {
    final player = _player;
    if (player == null || _disposed) return;
    player.state = player.state == mdk.PlaybackState.playing
        ? mdk.PlaybackState.paused
        : mdk.PlaybackState.playing;
  }

  /// 暂停播放（不切换状态），用于页面被覆盖时保留单例资源。
  void pause() {
    final player = _player;
    if (player == null || _disposed) return;
    if (player.state == mdk.PlaybackState.playing) {
      player.state = mdk.PlaybackState.paused;
    }
  }

  /// 恢复播放（仅在暂停态生效），用于折叠自动暂停后展开时恢复。
  /// 与 [playOrPause] 不同，此方法不引入切换语义，避免误触其它状态。
  void play() {
    final player = _player;
    if (player == null || _disposed) return;
    if (player.state == mdk.PlaybackState.paused) {
      player.state = mdk.PlaybackState.playing;
    }
  }

  void seek(Duration to) {
    final player = _player;
    if (player == null || _disposed) return;
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
    _viewPoints = List.unmodifiable(points);
  }

  /// Phase 4.5：查找当前播放位置对应的章节标题（无则返回 null）。
  String? currentChapterTitle() {
    final posSec = position.value.inSeconds.toDouble();
    for (final vp in _viewPoints) {
      if (vp.contains(posSec)) return vp.title;
    }
    return null;
  }

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
    final codec = stream.codec?.codec?.toLowerCase();
    if (codec == null || codec.isEmpty) return null;
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
    detachListeners();
    _pollTimer?.cancel();
    _pollTimer = null;
    _heartBeatTimer?.cancel();
    _heartBeatTimer = null;
    sponsorBlock?.dispose();
    sponsorBlock = null;
    // 引用计数递减，归零时才真正释放全局单例 mdk.Player。
    _playerCount--;
    if (_playerCount <= 0) {
      _playerCount = 0;
      _sharedPlayer?.dispose();
      _sharedPlayer = null;
    }
    qualityVersion.dispose();
    danmakuReloadSignal.dispose();
    subtitle.dispose();
  }
}
