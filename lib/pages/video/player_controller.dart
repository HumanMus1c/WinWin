import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:fvp/mdk.dart' as mdk;

import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/grpc/bilibili/community/service/dm/v1.pb.dart';
import 'package:winwin/http/video.dart';
import 'package:winwin/models/video/play_url.dart';
import 'package:winwin/pages/danmaku/controller.dart';
import 'package:winwin/plugin/canvas_danmaku/canvas_danmaku.dart';

/// WinWin 播放器控制器（fvp / mdk 内核）。
///
/// 负责：拉取 DASH 播放地址、外部音轨挂载、打开播放、
/// 进度/缓冲/错误状态广播、清晰度切换。
///
/// 对外暴露的 ValueNotifier 供 [PlayerPanel] 及详情页 UI 监听。
/// 渲染面：mdk 将解码帧注册为 Flutter Texture，面板监听
/// [textureId] 拿到 id 后用 `Texture(textureId:)` 绘制，
/// [videoSize] 用于保持视频帧宽高比（等效 BoxFit.contain）。
class WinWinPlayerController {
  WinWinPlayerController({required this.bvid, required this.cid}) {
    _player = _createPlayer();
  }

  final String bvid;
  final int cid;

  // ── 内部 mdk 播放器 ──
  mdk.Player? _player;

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

  /// seek 计数器：弹幕层监听后清空画面上的弹幕。
  final ValueNotifier<int> seekCount = ValueNotifier(0);

  /// 可选倍速列表（来自 Pref.speedList）。
  List<double> get speedList => Pref.speedList;

  /// 弹幕数据控制器，由弹幕视图（WinWinDanmaku）创建并挂载。
  WinWinDanmakuController? danmaku;

  /// 弹幕渲染引擎控制器，由 DanmakuScreen 的 createdController 回调赋值。
  DanmakuController<DanmakuElem>? danmakuEngine;

  /// 弹幕显示不透明度（0-1）：设置面板改动时写入，弹幕层监听实时刷新。
  final ValueNotifier<double> danmakuOpacity = ValueNotifier(
    Pref.danmakuOpacity,
  );

  // ── 清晰度状态 ──
  PlayUrlModel? _playUrl;
  int _currentQn = 80;

  // 请求头：Referer + PC User-Agent（经 mdk 'avio.headers' 属性下发）。
  static const String _referer = 'https://www.bilibili.com';
  static const String _pcUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _pollTimer;
  bool _disposed = false;

  /// 清晰度标签列表（PlayUrlModel.acceptDescription）。
  List<String> get qualityLabels => _playUrl?.acceptDescription ?? const [];

  /// 当前清晰度 qn 在 acceptQuality 中的下标。
  int get currentQualityIndex {
    final accept = _playUrl?.acceptQuality;
    if (accept == null || accept.isEmpty) return 0;
    final idx = accept.indexOf(_currentQn);
    return idx < 0 ? 0 : idx;
  }

  mdk.Player _createPlayer() {
    final player = mdk.Player();

    // 网络流稳健性 / 格式探测（参照 fvp video_player_mdk.dart 的默认项）。
    player.setProperty('avio.reconnect', '1');
    player.setProperty('avio.reconnect_delay_max', '7');
    player.setProperty('avformat.extension_picky', '0');
    // 扩大缓冲上限，减少在线 DASH 卡顿（mdk 默认 max 仅 4 秒）。
    player.setBufferRange(min: 1000, max: 30000);

    player.volume = volume.value / 100.0;

    _subscriptions
      ..add(player.onStateChanged.listen((event) {
        if (_disposed) return;
        playing.value = event.newValue == mdk.PlaybackState.playing;
      }))
      ..add(player.onEvent.listen((ev) {
        if (_disposed) return;
        // NOTE: for 'reader.buffering' the error field is progress [0,100],
        // not an error code; real mdk failures carry negative codes.
        if (ev.error < 0) {
          error.value ??= '播放错误 ${ev.error}: ${ev.detail}';
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
        }
        if (newValue.test(mdk.MediaStatus.invalid)) {
          error.value ??= '媒体加载失败';
        }
      }));

    // mdk 内部 updateTexture() 会更新 player.textureId，镜像到对外 notifier。
    player.textureId.addListener(_syncTextureId);

    _startPolling();
    return player;
  }

  void _syncTextureId() {
    final player = _player;
    if (_disposed || player == null) return;
    textureId.value = player.textureId.value;
  }

  /// mdk 没有 position/duration 流，用 250ms 轮询更新 ValueNotifier。
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final player = _player;
      if (_disposed || player == null || !ready.value) return;
      position.value = Duration(milliseconds: player.position);
      if (duration.value == Duration.zero) {
        final ms = player.mediaInfo.duration;
        if (ms > 0) duration.value = Duration(milliseconds: ms);
      }
    });
  }

  /// 拉取 DASH、pickVideo(maxQn)+pickAudio、挂载外部音轨打开，自动播放。
  /// 失败时写入 [error]，不抛异常。
  Future<void> load() async {
    // 幂等：网络栈未初始化时兜底（main 中未等待 bootstrap）。
    await ensureBootstrap();
    await _openWithQuality(qn: 80, maxQn: 80);
  }

  /// 切换到指定清晰度（acceptQuality[index]），记住进度重新 open。
  Future<void> switchQuality(int index) async {
    final accept = _playUrl?.acceptQuality;
    if (accept == null || index < 0 || index >= accept.length) return;
    final qn = accept[index];
    // 已是当前清晰度：不重复加载（重复 setMedia 同一 URL 会让 prepare 返回 -1）。
    if (qn == _currentQn) return;
    final remembered = position.value;
    await _openWithQuality(qn: qn, maxQn: qn, start: remembered);
  }

  Future<void> _openWithQuality({
    required int qn,
    required int maxQn,
    Duration? start,
  }) async {
    final player = _player;
    if (player == null || _disposed) return;
    try {
      error.value = null;
      ready.value = false;
      buffering.value = false;

      final result = await VideoHttp.videoUrl(bvid: bvid, cid: cid, qn: qn);
      if (_disposed) return;
      final PlayUrlModel? playUrl = result.dataOrNull;
      if (playUrl == null) {
        error.value = '获取播放地址失败';
        return;
      }

      final video = playUrl.pickVideo(maxQn: maxQn);
      final audio = playUrl.pickAudio();
      final videoUrl = video?.baseUrl;
      if (video == null || videoUrl == null || videoUrl.isEmpty) {
        error.value = '未获取到可播放的视频流';
        return;
      }

      _playUrl = playUrl;
      _currentQn = video.id ?? qn;

      // 请求头经 'avio.headers' 属性下发，格式为 "Key: Value\r\n" 列表，
      // 对该 Player 打开的所有源（含外部音轨）生效。
      player.setProperty(
        'avio.headers',
        'Referer: $_referer\r\nUser-Agent: $_pcUserAgent\r\n',
      );

      player.media = videoUrl;
      final audioUrl = audio?.baseUrl;
      if (audioUrl != null && audioUrl.isNotEmpty) {
        // DASH 分离音轨：以外部音轨方式挂载，prepare 后自动随视频播放。
        player.setMedia(audioUrl, mdk.MediaType.audio);
      }

      final ret = await player.prepare(
        position: (start ?? Duration.zero).inMilliseconds,
      );
      if (_disposed) return;
      if (ret < 0) {
        error.value = '播放失败（错误码 $ret）';
        return;
      }

      final ms = player.mediaInfo.duration;
      if (ms > 0) duration.value = Duration(milliseconds: ms);

      // 视频帧尺寸（纹理创建前已就绪），供面板保持宽高比。
      videoSize.value = await player.textureSize;
      if (_disposed) return;

      // 创建渲染 Texture 并更新 player.textureId（镜像到对外 notifier）。
      final tex = await player.updateTexture();
      if (_disposed) return;
      if (tex < 0) {
        error.value = '视频渲染面创建失败';
        return;
      }

      player.state = mdk.PlaybackState.playing;
      ready.value = true;
    } catch (e) {
      if (!_disposed) error.value = '播放失败：$e';
    }
  }

  void playOrPause() {
    final player = _player;
    if (player == null || _disposed) return;
    player.state = player.state == mdk.PlaybackState.playing
        ? mdk.PlaybackState.paused
        : mdk.PlaybackState.playing;
  }

  void seek(Duration to) {
    final player = _player;
    if (player == null || _disposed) return;
    unawaited(player.seek(position: to.inMilliseconds));
    seekCount.value++;
  }

  /// 设置音量（0-100）。
  void setVolume(double v) {
    final clamped = v.clamp(0.0, 100.0);
    volume.value = clamped;
    _player?.volume = clamped / 100.0;
  }

  /// 设置播放倍速：下发 mdk playbackRate 并更新 [playbackSpeed]。
  ///
  /// 弹幕时长的联动由弹幕视图监听 [playbackSpeed] 后调用
  /// `danmakuEngine.updateOption(DanmakuOptions.get(..., speed: v))` 完成。
  void setPlaybackSpeed(double v) {
    if (_disposed || v <= 0) return;
    playbackSpeed.value = v;
    _player?.playbackRate = v;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    final player = _player;
    _player = null;
    if (player != null) {
      player.textureId.removeListener(_syncTextureId);
      for (final sub in _subscriptions) {
        sub.cancel();
      }
      _subscriptions.clear();
      player.dispose();
    }
  }
}
