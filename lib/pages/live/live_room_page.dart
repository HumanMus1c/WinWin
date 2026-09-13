import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fvp/mdk.dart' as mdk;

import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/core/account/account_service.dart';
import 'package:winwin/core/account/login_guard.dart';
import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/core/window/desktop_fullscreen.dart';
import 'package:winwin/http/live.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/pages/member/member_space_page.dart';
import 'package:winwin/tcp/live.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/utils/bilibili_emotes.dart';
import 'package:winwin/utils/duration_utils.dart';
import 'package:winwin/utils/num_utils.dart';

/// 桌面原生直播间播放页面。
///
/// 特性：
/// - 基于 fvp / mdk 原生硬解播放 HTTP-FLV / HLS 直播流；
/// - 接入 [LiveDanmakuClient] 二进制 WebSocket 协议接收实时弹幕；
/// - 补齐普通视频除进度条外的全套播放控件（画质切换、音量静音、画面比例、推流线路切换、全屏/网页全屏、流刷新、弹幕开闭等）；
/// - 本次直播自开播以来的秒级实时动态递增时长展示；
/// - 实时互动面板支持发送弹幕（含登录守卫、CSRF 校验与乐观本地上屏）；
/// - 整页背景同步主播自定义背景（带高斯模糊与沉浸式半透明蒙版）。
class LiveRoomPage extends StatefulWidget {
  const LiveRoomPage({
    super.key,
    required this.roomId,
    this.title,
    this.uname,
    this.cover,
  });

  final int roomId;
  final String? title;
  final String? uname;
  final String? cover;

  @override
  State<LiveRoomPage> createState() => _LiveRoomPageState();
}

class _LiveRoomPageState extends State<LiveRoomPage> {
  mdk.Player? _player;
  int? _textureId;
  LiveDanmakuClient? _danmakuClient;
  StreamSubscription<LiveDanmakuMessage>? _danmakuSub;

  LiveRoomInfo? _roomInfo;
  LivePlayUrlData? _playUrlData;
  late int _realRoomId;
  int _liveStatus = 0; // 0=未开播/已下播, 1=直播中, 2=轮播中

  bool _loading = true;
  String? _errorMessage;
  bool _isLiving = false;
  bool _isPlaying = true;
  double _volume = 1.0;
  double _lastNonZeroVolume = 1.0;
  bool _showControls = true;
  Timer? _controlsTimer;
  Timer? _watchdogTimer;

  // 画质清晰度与推流线路
  int? _currentQn;
  List<LiveStreamLine> _streamLines = [];
  List<String> _streamCandidates = [];
  int _currentStreamIndex = 0;

  // 画面比例模式: 0: 16:9, 1: 4:3, 2: 原始比例 (自适应 contain), 3: 铺满拉伸 (fill)
  int _aspectRatioMode = 0;

  // 全屏与网页全屏
  bool _fullscreen = false;
  bool _inAppFullscreen = false;

  // 弹幕显示开关
  bool _danmakuVisible = true;

  // 本次直播累计时长
  int _liveStartTime = 0;
  String _liveDurationText = '';
  Timer? _liveDurationTimer;

  // 弹幕交互与发送
  final TextEditingController _danmakuInputCtrl = TextEditingController();
  final FocusNode _danmakuInputFocusNode = FocusNode();
  final FocusNode _keyboardFocusNode = FocusNode();
  bool _isSendingDanmaku = false;

  final List<LiveDanmakuMessage> _danmakuList = [];
  final ScrollController _chatScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _realRoomId = widget.roomId;
    _startHideControlsTimer();
    _initLive();
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _watchdogTimer?.cancel();
    _liveDurationTimer?.cancel();
    _danmakuSub?.cancel();
    _danmakuClient?.dispose();
    _chatScrollCtrl.dispose();
    _danmakuInputCtrl.dispose();
    _danmakuInputFocusNode.dispose();
    _keyboardFocusNode.dispose();
    if (_fullscreen) {
      DesktopFullscreen.exit();
    }
    final player = _player;
    _player = null;
    if (player != null) {
      player.state = mdk.PlaybackState.stopped;
      player.dispose();
    }
    super.dispose();
  }

  void _startHideControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _onHoverPlayer() {
    if (!_showControls) {
      setState(() => _showControls = true);
    }
    _startHideControlsTimer();
  }

  void _startLiveDurationTimer() {
    _liveDurationTimer?.cancel();
    if (!_isLiving || _liveStartTime <= 0) {
      _liveDurationText = '';
      return;
    }
    void updateDuration() {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final elapsed = nowSec - _liveStartTime;
      if (elapsed >= 0) {
        if (mounted) {
          setState(() {
            _liveDurationText = DurationUtils.formatDuration(elapsed);
          });
        }
      }
    }

    updateDuration();
    _liveDurationTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => updateDuration(),
    );
  }

  Future<void> _initLive() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    await ensureBootstrap();

    final targetRoomId = widget.roomId;

    // 1. 并发启动：短号转长号/开播状态、H5 详细信息、云端历史互动弹幕
    final initFuture = LiveHttp.roomInit(roomId: targetRoomId);
    final infoFuture = LiveHttp.roomInfo(roomId: targetRoomId);
    final dmFuture = _prefetchDanmaku(targetRoomId);

    final results = await Future.wait([initFuture, infoFuture]);
    final initRes = results[0] as LoadingState<LiveRoomInitData>;
    final infoRes = results[1] as LoadingState<LiveRoomInfo>;

    if (!mounted) return;

    if (initRes case Success(:final response)) {
      if (response.roomId > 0) {
        _realRoomId = response.roomId;
      }
      _liveStatus = response.liveStatus;
      _isLiving = response.isLiving;
      if (response.liveTime > 0) {
        _liveStartTime = response.liveTime;
      }
    }

    if (infoRes case Success(:final response)) {
      _roomInfo = response;
      if ((response.roomId ?? 0) > 0) {
        _realRoomId = response.roomId!;
      }
      if (response.liveStatus != null) {
        _liveStatus = response.liveStatus!;
        _isLiving = response.liveStatus == 1;
      }
      if (response.liveStartTime != null && response.liveStartTime! > 0) {
        _liveStartTime = response.liveStartTime!;
      }
    }

    // 启动或停止直播累计时长计时器
    _startLiveDurationTimer();

    // 立即刷新主播信息与背景
    if (mounted) {
      setState(() {});
    }

    // 等待弹幕预取完成
    await dmFuture;
    if (!mounted) return;

    // 2. 开播状态下获取推流与连接实时弹幕
    if (_isLiving) {
      unawaited(_setupDanmaku(_realRoomId));

      final playRes = await LiveHttp.liveRoomPlayInfo(
        roomId: _realRoomId,
        qn: _currentQn,
      );
      if (!mounted) return;

      if (playRes case Success(:final response)) {
        _playUrlData = response;
        _currentQn = response.currentQn ?? _currentQn;
        _streamLines = response.streamLines;
        final urls = response.allPlayUrls;
        if (urls.isNotEmpty) {
          await _setupPlayerWithCandidates(urls);
        } else {
          final singleUrl = response.bestPlayUrl;
          if (singleUrl != null && singleUrl.isNotEmpty) {
            await _setupPlayerWithCandidates([singleUrl]);
          } else {
            if (mounted) {
              setState(() {
                _errorMessage = '未获取到有效直播推流地址';
                _loading = false;
              });
            }
          }
        }
      } else if (playRes case Error(:final errMsg)) {
        if (mounted) {
          setState(() {
            _errorMessage = errMsg ?? '获取直播流失败';
            _loading = false;
          });
        }
      }
    } else {
      _watchdogTimer?.cancel();
      _liveDurationTimer?.cancel();
      _liveDurationText = '';
      final player = _player;
      _player = null;
      _textureId = null;
      if (player != null) {
        player.state = mdk.PlaybackState.stopped;
        player.dispose();
      }
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _prefetchDanmaku(int roomId) async {
    final prefetchRes = await LiveHttp.liveRoomDmPrefetch(roomId: roomId);
    if (!mounted) return;
    if (prefetchRes case Success(:final response)) {
      if (response.isNotEmpty) {
        setState(() {
          _danmakuList.clear();
          _danmakuList.addAll(response);
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_chatScrollCtrl.hasClients) {
            _chatScrollCtrl.jumpTo(_chatScrollCtrl.position.maxScrollExtent);
          }
        });
      }
    }
  }

  Future<void> _setupPlayerWithCandidates(List<String> candidates) async {
    _streamCandidates = candidates;
    _currentStreamIndex = 0;
    await _tryPlayCurrentCandidate();
  }

  Future<void> _tryPlayCurrentCandidate() async {
    if (_currentStreamIndex >= _streamCandidates.length) {
      if (mounted) {
        setState(() {
          _errorMessage = '所有直播推流均播放失败，请点击重试';
          _loading = false;
        });
      }
      return;
    }
    final url = _streamCandidates[_currentStreamIndex];
    await _startPlayer(url);
  }

  Future<void> _startPlayer(String url) async {
    _watchdogTimer?.cancel();

    // 启动 6 秒看门狗：避免加载菊花无限卡住
    _watchdogTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      if (_loading) {
        if (_currentStreamIndex + 1 < _streamCandidates.length) {
          _currentStreamIndex++;
          unawaited(_tryPlayCurrentCandidate());
        } else {
          setState(() => _loading = false);
        }
      }
    });

    try {
      final oldPlayer = _player;
      _player = null;
      if (oldPlayer != null) {
        oldPlayer.state = mdk.PlaybackState.stopped;
        oldPlayer.dispose();
      }

      final player = mdk.Player();
      _player = player;

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
        player.setProperty('video.decoder', 'shader_resource=1');
      } else {
        player.videoDecoders = const ['FFmpeg', 'dav1d'];
        player.setProperty('video.decoder', 'shader_resource=0');
      }

      player.setProperty('avformat.strict', 'experimental');
      player.setProperty('avformat.safe', '0');
      player.setProperty(
        'avio.headers',
        'Referer: https://live.bilibili.com\r\n'
        'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36\r\n',
      );
      player.setProperty('avio.reconnect', '1');
      player.setProperty('avio.reconnect_streamed', '1');
      player.setProperty('avio.reconnect_on_network_error', '1');
      player.setProperty('avio.reconnect_on_http_error', '4xx,5xx');
      player.setProperty('avio.timeout', '10000000');
      player.setProperty('demux.max_errors', '50');

      // 直播低延迟缓冲窗口
      player.setBufferRange(min: 800, max: 3000, drop: true);
      player.volume = _volume;

      // 监听播放器媒体状态：首帧/加载完成即可隐藏 loading 状态
      player.onMediaStatus.listen((event) {
        if (!mounted || _player != player) return;
        final status = event.newValue;
        if (status.test(mdk.MediaStatus.loaded) ||
            status.test(mdk.MediaStatus.buffering) ||
            status.test(mdk.MediaStatus.buffered)) {
          _watchdogTimer?.cancel();
          if (_loading) {
            setState(() => _loading = false);
          }
        }
      });

      // 监听播放器底层错误事件：遇到硬错误自动尝试候选备用流
      player.onEvent.listen((ev) {
        if (!mounted || _player != player) return;
        if (ev.error < -1) {
          _watchdogTimer?.cancel();
          if (_currentStreamIndex + 1 < _streamCandidates.length) {
            _currentStreamIndex++;
            unawaited(_tryPlayCurrentCandidate());
          } else {
            if (mounted) {
              setState(() {
                _errorMessage = '播放错误：${ev.detail} (${ev.error})';
                _loading = false;
              });
            }
          }
        }
      });

      player.media = url;

      // 先异步 await prepare() 探测解复用与视频属性
      final ret = await player.prepare();
      if (!mounted || _player != player) return;
      if (ret < 0 && ret != -1) {
        if (_currentStreamIndex + 1 < _streamCandidates.length) {
          _currentStreamIndex++;
          await _tryPlayCurrentCandidate();
          return;
        }
      }

      // 探测后异步创建并更新渲染纹理
      final texId = await player.updateTexture();
      if (!mounted || _player != player) return;
      if (texId < 0) {
        if (_currentStreamIndex + 1 < _streamCandidates.length) {
          _currentStreamIndex++;
          await _tryPlayCurrentCandidate();
          return;
        }
      }

      _textureId = texId;
      player.state = mdk.PlaybackState.playing;
      _isPlaying = true;
      if (mounted) {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (!mounted) return;
      if (_currentStreamIndex + 1 < _streamCandidates.length) {
        _currentStreamIndex++;
        await _tryPlayCurrentCandidate();
      } else {
        setState(() {
          _errorMessage = '播放器初始化失败：$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _setupDanmaku(int roomId) async {
    _danmakuSub?.cancel();
    _danmakuClient?.dispose();

    // 获取官方动态 Token 与候选彗星服务器集群
    String token = '';
    List<String> servers = [];
    final tokenRes = await LiveHttp.liveRoomGetDanmakuToken(roomId: roomId);
    if (!mounted) return;
    if (tokenRes case Success(:final response)) {
      token = response.token;
      servers = response.hostList.map((h) {
        final port = h.wssPort > 0 ? h.wssPort : 443;
        return 'wss://${h.host}:$port/sub';
      }).toList();
    }

    final client = LiveDanmakuClient(
      roomId: roomId,
      uid: AccountService().userInfo?.mid ?? 0,
      token: token,
      servers: servers,
    );
    _danmakuClient = client;

    _danmakuSub = client.messageStream.listen((msg) {
      if (!mounted) return;
      if (msg.isDanmaku) {
        setState(() {
          _danmakuList.add(msg);
          if (_danmakuList.length > 300) {
            _danmakuList.removeRange(0, 50);
          }
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_chatScrollCtrl.hasClients) {
            _chatScrollCtrl.animateTo(
              _chatScrollCtrl.position.maxScrollExtent,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });

    unawaited(client.connect());
  }

  void _togglePlay() {
    final player = _player;
    if (player == null) return;
    if (_isPlaying) {
      player.state = mdk.PlaybackState.paused;
      setState(() => _isPlaying = false);
    } else {
      player.state = mdk.PlaybackState.playing;
      setState(() => _isPlaying = true);
    }
  }

  void _toggleMute() {
    if (_volume > 0) {
      _lastNonZeroVolume = _volume;
      _setVolume(0);
    } else {
      _setVolume(_lastNonZeroVolume > 0 ? _lastNonZeroVolume : 1.0);
    }
  }

  void _setVolume(double val) {
    setState(() => _volume = val);
    _player?.volume = val;
  }

  Future<void> _changeQuality(int qn) async {
    if (_currentQn == qn) return;
    setState(() {
      _currentQn = qn;
      _loading = true;
      _errorMessage = null;
    });
    final res = await LiveHttp.liveRoomPlayInfo(roomId: _realRoomId, qn: qn);
    if (!mounted) return;
    if (res case Success(:final response)) {
      _playUrlData = response;
      _streamLines = response.streamLines;
      final urls = response.allPlayUrls;
      if (urls.isNotEmpty) {
        await _setupPlayerWithCandidates(urls);
      } else {
        final singleUrl = response.bestPlayUrl;
        if (singleUrl != null && singleUrl.isNotEmpty) {
          await _setupPlayerWithCandidates([singleUrl]);
        }
      }
    } else if (res case Error(:final errMsg)) {
      setState(() {
        _errorMessage = errMsg ?? '切换画质失败';
        _loading = false;
      });
    }
  }

  Future<void> _switchLine(int index) async {
    if (index < 0 || index >= _streamLines.length) return;
    setState(() {
      _currentStreamIndex = index;
      _loading = true;
      _errorMessage = null;
    });
    await _startPlayer(_streamLines[index].url);
  }

  Future<void> _toggleFullscreen() async {
    final next = !_fullscreen;
    setState(() => _fullscreen = next);
    if (next) {
      await DesktopFullscreen.enter();
    } else {
      await DesktopFullscreen.exit();
    }
  }

  void _toggleInAppFullscreen() {
    setState(() => _inAppFullscreen = !_inAppFullscreen);
  }

  void _handleEscape() {
    if (_fullscreen) {
      _toggleFullscreen();
    } else if (_inAppFullscreen) {
      _toggleInAppFullscreen();
    } else {
      Navigator.maybePop(context);
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // 当弹幕输入框正在编辑时，不拦截快捷键
    if (_danmakuInputFocusNode.hasFocus) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.space) {
      _togglePlay();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyD) {
      setState(() => _danmakuVisible = !_danmakuVisible);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyM) {
      _toggleMute();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyF) {
      _toggleFullscreen();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyW) {
      _toggleInAppFullscreen();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _handleEscape();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _sendDanmaku() async {
    final text = _danmakuInputCtrl.text.trim();
    if (text.isEmpty) return;
    if (!await LoginGuard.requireLogin(context)) return;
    if (!mounted) return;

    setState(() => _isSendingDanmaku = true);
    final res = await LiveHttp.sendLiveMsg(
      roomId: _realRoomId,
      msg: text,
    );
    if (!mounted) return;
    setState(() => _isSendingDanmaku = false);

    switch (res) {
      case Success():
        _danmakuInputCtrl.clear();
        final userInfo = AccountService().userInfo;
        final myUname = userInfo?.name ?? '我';
        final myAvatar = userInfo?.face;
        final myLevel = userInfo?.level;
        final optimisticMsg = LiveDanmakuMessage(
          cmd: 'DANMU_MSG',
          userName: myUname,
          customText: text,
          userAvatar: myAvatar,
          userLevel: myLevel,
          raw: const {},
        );
        setState(() {
          _danmakuList.add(optimisticMsg);
          if (_danmakuList.length > 300) {
            _danmakuList.removeRange(0, 50);
          }
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_chatScrollCtrl.hasClients) {
            _chatScrollCtrl.animateTo(
              _chatScrollCtrl.position.maxScrollExtent,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
            );
          }
        });
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('弹幕发送成功'),
            duration: Duration(seconds: 1),
          ),
        );
      case Error(:final errMsg):
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(errMsg ?? '发送弹幕失败'),
            duration: const Duration(seconds: 2),
          ),
        );
      case Loading():
        break;
    }
  }

  void _showQuickSendDialog() {
    if (!_isLiving) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('未开播，无法发送弹幕'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }
    if (!_fullscreen && !_inAppFullscreen) {
      _danmakuInputFocusNode.requestFocus();
      return;
    }

    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: const Color(0xE61E1E1E),
          title: const Text(
            '发送直播弹幕',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: '输入弹幕内容...',
              hintStyle: TextStyle(color: Colors.white54),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (text) async {
              Navigator.pop(dialogCtx);
              _danmakuInputCtrl.text = text;
              await _sendDanmaku();
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogCtx);
                _danmakuInputCtrl.text = ctrl.text;
                await _sendDanmaku();
              },
              child: const Text('发送'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final displayTitle = _roomInfo?.title ?? widget.title ?? '直播间 $_realRoomId';
    final hostName = _roomInfo?.uname ?? widget.uname ?? 'UP 主';
    final hostAvatar = _roomInfo?.face;
    final isFillWindow = _fullscreen || _inAppFullscreen;

    // 主播自定义背景图，若未设置则优雅回退至封面
    final customBgUrl =
        _roomInfo?.effectiveBackground ?? widget.cover;

    return Focus(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. 底层：主播自定义全屏背景 + 高性能降低分辨率 WebP 缩略图 + 轻量柔和模糊与半透明蒙版
          Positioned.fill(
            child: Container(
              color: isFillWindow ? Colors.black : theme.scaffoldBackgroundColor,
              child: (!isFillWindow && customBgUrl != null && customBgUrl.isNotEmpty)
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        NetworkImgLayer(
                          src: customBgUrl,
                          width: double.infinity,
                          height: double.infinity,
                          type: 'background',
                          borderRadius: BorderRadius.zero,
                          fit: BoxFit.cover,
                          fadeInDuration: const Duration(milliseconds: 300),
                        ),
                        // 柔和微模糊 (sigma: 6) 与半透明暗色渐变蒙版，保留背景图主体艺术感与轮廓，杜绝退化为纯色
                        BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  (theme.brightness == Brightness.dark
                                          ? Colors.black
                                          : cs.surface)
                                      .withValues(alpha: 0.40),
                                  (theme.brightness == Brightness.dark
                                          ? Colors.black
                                          : cs.surface)
                                      .withValues(alpha: 0.60),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : null,
            ),
          ),

          // 2. 主页面骨架
          Scaffold(
            backgroundColor: Colors.transparent,
            appBar: isFillWindow
                ? null
                : AppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    title: Row(
                      children: [
                        _buildStatusBadge(),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: '刷新直播流',
                        onPressed: _initLive,
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        tooltip: '复制直播间链接',
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(
                              text: 'https://live.bilibili.com/$_realRoomId',
                            ),
                          );
                          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                            const SnackBar(
                              content: Text('已复制直播间链接'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
            body: isFillWindow
                ? _buildFullscreenPlayer()
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 850;
                      if (isWide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 左侧播放区域与主播简介
                            Expanded(
                              flex: 7,
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(Style.md),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildPlayerBox(),
                                    const SizedBox(height: Style.md),
                                    _buildHostInfo(
                                      hostName,
                                      hostAvatar,
                                      cs,
                                      theme,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // 右侧实时互动面板（同等 Style.md 边距与全圆角容器）
                            Expanded(
                              flex: 3,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  0,
                                  Style.md,
                                  Style.md,
                                  Style.md,
                                ),
                                child: _buildChatPanel(cs, theme),
                              ),
                            ),
                          ],
                        );
                      } else {
                        return Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                Style.md,
                                Style.md,
                                Style.md,
                                0,
                              ),
                              child: _buildPlayerBox(),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                Style.md,
                                Style.md,
                                Style.md,
                                0,
                              ),
                              child: _buildHostInfo(
                                hostName,
                                hostAvatar,
                                cs,
                                theme,
                              ),
                            ),
                            const SizedBox(height: Style.md),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  Style.md,
                                  0,
                                  Style.md,
                                  Style.md,
                                ),
                                child: _buildChatPanel(cs, theme),
                              ),
                            ),
                          ],
                        );
                      }
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 视频播放器区域（普通窗口模式）
  Widget _buildPlayerBox() {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(Style.radiusMd),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: MouseRegion(
          onHover: (_) => _onHoverPlayer(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 视频画面
              _buildVideoSurface(),

              // 屏幕弹幕悬浮层
              if (_danmakuVisible && _isLiving) _buildDanmakuOverlay(),

              // 暂停状态大居中播放按钮
              if (_isLiving && !_isPlaying && !_loading && _errorMessage == null)
                _buildCenterPlayButton(),

              // 加载中菊花指示器
              if (_loading && _isLiving && _errorMessage == null)
                Container(
                  color: Colors.black54,
                  child: const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Colors.white,
                    ),
                  ),
                ),

              // 全功能控制条覆层
              if (_showControls && !_loading && _isLiving && _errorMessage == null)
                _buildControlsOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  /// 全屏/网页全屏模式播放器
  Widget _buildFullscreenPlayer() {
    return MouseRegion(
      onHover: (_) => _onHoverPlayer(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildVideoSurface(),
          if (_danmakuVisible && _isLiving) _buildDanmakuOverlay(),
          if (_isLiving && !_isPlaying && !_loading && _errorMessage == null)
            _buildCenterPlayButton(),
          if (_loading && _isLiving && _errorMessage == null)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Colors.white,
                ),
              ),
            ),
          if (_showControls && !_loading && _isLiving && _errorMessage == null) ...[
            _buildFullscreenTopBar(),
            _buildControlsOverlay(),
          ],
        ],
      ),
    );
  }

  /// 全屏模式顶部标题栏浮层
  Widget _buildFullscreenTopBar() {
    final displayTitle = _roomInfo?.title ?? widget.title ?? '直播间 $_realRoomId';
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.8),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              tooltip: '退出全屏 (Esc)',
              onPressed: _handleEscape,
            ),
            const SizedBox(width: 8),
            _buildStatusBadge(),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (_liveDurationText.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '已播 $_liveDurationText',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
              tooltip: '退出全屏',
              onPressed: _handleEscape,
            ),
          ],
        ),
      ),
    );
  }

  /// 视频画面渲染（支持不同画面比例模式）
  Widget _buildVideoSurface() {
    if (!_isLiving || _textureId == null || _errorMessage != null) {
      return _buildOfflineCover();
    }

    final textureWidget = Texture(textureId: _textureId!);

    switch (_aspectRatioMode) {
      case 1: // 4:3
        return Center(
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: textureWidget,
          ),
        );
      case 2: // 原始比例自适应 (contain)
        return Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 1920,
              height: 1080,
              child: textureWidget,
            ),
          ),
        );
      case 3: // 铺满拉伸 (fill)
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.fill,
            child: SizedBox(
              width: 1920,
              height: 1080,
              child: textureWidget,
            ),
          ),
        );
      case 0: // 16:9
      default:
        return Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: textureWidget,
          ),
        );
    }
  }

  /// 居中半透明大播放按钮
  Widget _buildCenterPlayButton() {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _togglePlay,
          borderRadius: BorderRadius.circular(36),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.play_arrow_rounded,
              color: Colors.white,
              size: 44,
            ),
          ),
        ),
      ),
    );
  }

  /// 屏幕悬浮滚动弹幕层
  Widget _buildDanmakuOverlay() {
    if (!_danmakuVisible || _danmakuList.isEmpty) {
      return const SizedBox.shrink();
    }
    final recent = _danmakuList.length > 5
        ? _danmakuList.sublist(_danmakuList.length - 5)
        : _danmakuList;

    return Positioned(
      left: 16,
      top: 16,
      right: 16,
      child: IgnorePointer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: recent.map((dm) {
            final spans = <InlineSpan>[
              TextSpan(
                text: '${dm.senderName}: ',
                style: const TextStyle(
                  color: Color(0xFF67E8F9),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(blurRadius: 2, color: Colors.black)],
                ),
              ),
              ..._buildDanmakuContentSpans(
                dm.danmakuText ?? '',
                dm.emots,
                const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  shadows: [Shadow(blurRadius: 2, color: Colors.black)],
                ),
              ),
            ];

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.5),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text.rich(
                  TextSpan(children: spans),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  /// 播放器下部悬浮全功能控制条（除进度条外全部完备）
  Widget _buildControlsOverlay() {
    final availableQn = _playUrlData?.availableQnList ?? [10000, 400, 250, 150];
    final currentQnText = LiveQuality.descFromCode(_currentQn);

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.85),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            // 1. 播放/暂停
            IconButton(
              icon: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 24,
              ),
              tooltip: _isPlaying ? '暂停 (Space)' : '播放 (Space)',
              onPressed: _togglePlay,
            ),
            const SizedBox(width: 6),

            // 2. 直播指示红点 + 本次直播实时时长
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.fiber_manual_record, size: 8, color: Colors.white),
                  SizedBox(width: 3),
                  Text(
                    'LIVE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            if (_liveDurationText.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                _liveDurationText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
            const SizedBox(width: 10),

            // 3. 弹幕开/关
            IconButton(
              icon: Icon(
                _danmakuVisible ? Icons.subtitles : Icons.subtitles_off,
                color: _danmakuVisible ? Colors.white : Colors.white54,
                size: 20,
              ),
              tooltip: _danmakuVisible ? '关闭弹幕 (D)' : '开启弹幕 (D)',
              onPressed: () {
                setState(() => _danmakuVisible = !_danmakuVisible);
              },
            ),

            // 4. 发弹幕快捷按钮
            IconButton(
              icon: const Icon(
                Icons.comment_outlined,
                color: Colors.white70,
                size: 20,
              ),
              tooltip: '发弹幕',
              onPressed: _showQuickSendDialog,
            ),

            const Spacer(),

            // 5. 画质/清晰度切换菜单
            PopupMenuButton<int>(
              tooltip: '画质清晰度',
              color: const Color(0xE61E1E1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Colors.white12),
              ),
              onSelected: _changeQuality,
              itemBuilder: (context) {
                return availableQn.map((qn) {
                  final isSelected = _currentQn == qn;
                  return PopupMenuItem<int>(
                    value: qn,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 16,
                          color: isSelected ? Colors.lightBlueAccent : Colors.white54,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          LiveQuality.descFromCode(qn),
                          style: TextStyle(
                            color: isSelected
                                ? Colors.lightBlueAccent
                                : Colors.white,
                            fontSize: 13,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      currentQnText,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    const Icon(
                      Icons.arrow_drop_down,
                      color: Colors.white70,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            // 6. 推流线路切换菜单
            if (_streamLines.isNotEmpty)
              PopupMenuButton<int>(
                tooltip: '推流线路/CDN',
                color: const Color(0xE61E1E1E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: Colors.white12),
                ),
                onSelected: _switchLine,
                itemBuilder: (context) {
                  return List.generate(_streamLines.length, (idx) {
                    final line = _streamLines[idx];
                    final isSelected = _currentStreamIndex == idx;
                    return PopupMenuItem<int>(
                      value: idx,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isSelected
                                ? Icons.check
                                : Icons.radio_button_unchecked,
                            size: 16,
                            color: isSelected ? Colors.lightBlueAccent : Colors.white54,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            line.title,
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.lightBlueAccent
                                  : Colors.white,
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    );
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '线路 ${_currentStreamIndex + 1}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      const Icon(
                        Icons.arrow_drop_down,
                        color: Colors.white70,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(width: 6),

            // 7. 画面比例模式切换
            PopupMenuButton<int>(
              tooltip: '画面比例',
              color: const Color(0xE61E1E1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Colors.white12),
              ),
              onSelected: (mode) => setState(() => _aspectRatioMode = mode),
              itemBuilder: (context) {
                const modes = ['16:9', '4:3', '原始比例', '铺满拉伸'];
                return List.generate(modes.length, (idx) {
                  final isSelected = _aspectRatioMode == idx;
                  return PopupMenuItem<int>(
                    value: idx,
                    child: Row(
                      children: [
                        Icon(
                          isSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 16,
                          color: isSelected ? Colors.lightBlueAccent : Colors.white54,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          modes[idx],
                          style: TextStyle(
                            color: isSelected
                                ? Colors.lightBlueAccent
                                : Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  );
                });
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.aspect_ratio, color: Colors.white70, size: 20),
              ),
            ),
            const SizedBox(width: 6),

            // 8. 音量控制（静音图标 + 滑块）
            IconButton(
              icon: Icon(
                _volume > 0 ? Icons.volume_up : Icons.volume_off,
                color: Colors.white70,
                size: 20,
              ),
              tooltip: _volume > 0 ? '静音 (M)' : '取消静音 (M)',
              onPressed: _toggleMute,
            ),
            SizedBox(
              width: 80,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 2.5,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: SliderComponentShape.noOverlay,
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white30,
                  thumbColor: Colors.white,
                ),
                child: Slider(
                  value: _volume,
                  min: 0.0,
                  max: 1.0,
                  onChanged: _setVolume,
                ),
              ),
            ),
            const SizedBox(width: 4),

            // 9. 刷新流
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white70, size: 20),
              tooltip: '重新加载流',
              onPressed: _initLive,
            ),

            // 10. 网页全屏（In-app 全屏）
            if (!_fullscreen)
              IconButton(
                icon: Icon(
                  _inAppFullscreen
                      ? Icons.crop_square
                      : Icons.crop_square_outlined,
                  color: Colors.white70,
                  size: 20,
                ),
                tooltip: _inAppFullscreen ? '退出网页全屏 (W)' : '网页全屏 (W)',
                onPressed: _toggleInAppFullscreen,
              ),

            // 11. 窗口原生全屏
            IconButton(
              icon: Icon(
                _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                color: Colors.white70,
                size: 22,
              ),
              tooltip: _fullscreen ? '退出全屏 (F / Esc)' : '全屏 (F)',
              onPressed: _toggleFullscreen,
            ),
          ],
        ),
      ),
    );
  }

  /// 直播状态胶囊徽章（直播中 / 轮播中 / 未开播）
  Widget _buildStatusBadge() {
    final Color badgeColor;
    final String badgeText;
    final IconData icon;

    if (_isLiving) {
      badgeColor = const Color(0xFF10B981);
      badgeText = _liveDurationText.isNotEmpty
          ? '直播中 · 已播 $_liveDurationText'
          : '直播中';
      icon = Icons.fiber_manual_record;
    } else if (_liveStatus == 2) {
      badgeColor = Colors.orangeAccent;
      badgeText = '轮播中';
      icon = Icons.replay_rounded;
    } else {
      badgeColor = Colors.white54;
      badgeText = '未开播';
      icon = Icons.radio_button_unchecked;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: badgeColor.withValues(alpha: 0.4),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 8, color: badgeColor),
          const SizedBox(width: 4),
          Text(
            badgeText,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: badgeColor,
            ),
          ),
        ],
      ),
    );
  }

  /// 未开播/已下播占位封面
  Widget _buildOfflineCover() {
    final effectiveCover = _roomInfo?.cover ?? widget.cover;
    final isRound = _liveStatus == 2 || _roomInfo?.liveStatus == 2;
    final offlineText = isRound ? '主播当前正在轮播中' : '主播当前暂未开播或已下播';
    return Stack(
      fit: StackFit.expand,
      children: [
        if (effectiveCover != null && effectiveCover.isNotEmpty)
          NetworkImgLayer(
            src: effectiveCover,
            width: double.infinity,
            height: double.infinity,
            borderRadius: BorderRadius.zero,
          ),
        Container(
          color: Colors.black.withValues(alpha: 0.75),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isRound ? Icons.repeat : Icons.sensors_off_outlined,
                  size: 48,
                  color: isRound ? Colors.orangeAccent : Colors.white60,
                ),
                const SizedBox(height: 12),
                Text(
                  _errorMessage ?? offlineText,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: _initLive,
                  child: const Text('重试刷新'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 主播信息与房间数据卡片
  Widget _buildHostInfo(
    String hostName,
    String? hostAvatar,
    ColorScheme cs,
    ThemeData theme,
  ) {
    final areaName = _roomInfo?.areaName;
    final online = _roomInfo?.online;
    final heatText = _roomInfo?.watchedShowText ??
        (online != null && online > 0 ? NumUtils.formatNum(online) : null);
    final shortId = _roomInfo?.shortId;
    final roomIdText =
        (shortId != null && shortId > 0 && shortId != _realRoomId)
            ? '房间号: $shortId ($_realRoomId)'
            : '房间号: $_realRoomId';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.50),
        borderRadius: BorderRadius.circular(Style.radiusMd),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.2),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              final uid = _roomInfo?.uid;
              if (uid != null && uid > 0) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => MemberSpacePage(mid: uid)),
                );
              }
            },
            child: NetworkImgLayer(
              src: hostAvatar,
              width: 48,
              height: 48,
              type: 'avatar',
            ),
          ),
          const SizedBox(width: Style.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hostName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      roomIdText,
                      style:
                          theme.textTheme.bodySmall?.copyWith(color: cs.outline),
                    ),
                    if (areaName != null && areaName.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: cs.secondaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          areaName,
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                    if (heatText != null && heatText.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.local_fire_department,
                        size: 14,
                        color: Colors.orange.shade700,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        heatText,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 实时互动面板（含云端与实时弹幕列表 + 底部发送弹幕输入交互条）
  Widget _buildChatPanel(ColorScheme cs, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.50),
        borderRadius: BorderRadius.circular(Style.radiusMd),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.2),
          width: 0.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部：标题与状态指示
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.chat_bubble_outline, size: 18),
                const SizedBox(width: 6),
                Text(
                  '实时互动',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isLiving ? Colors.greenAccent : Colors.grey,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  _isLiving ? '连接就绪' : '未连接',
                  style: TextStyle(fontSize: 11, color: cs.outline),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 0.5,
            color: cs.outlineVariant.withValues(alpha: 0.3),
          ),

          // 弹幕列表（富文本支持头像、粉丝牌、UL等级铭牌与官方Emoji图文混排）
          Expanded(
            child: _danmakuList.isEmpty
                ? Center(
                    child: Text(
                      _isLiving ? '弹幕加载中，等待新发言...' : '直播未开启，暂无弹幕',
                      style: TextStyle(color: cs.outline, fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    controller: _chatScrollCtrl,
                    padding: const EdgeInsets.symmetric(
                      horizontal: Style.sm,
                      vertical: 6,
                    ),
                    itemCount: _danmakuList.length,
                    itemBuilder: (context, index) {
                      final item = _danmakuList[index];
                      return _buildDanmakuItem(item, cs, theme);
                    },
                  ),
          ),

          // 底部互动发送条（输入框与发送按钮高度严格对齐）
          _buildChatInputBar(cs, theme),
        ],
      ),
    );
  }

  /// 单条弹幕渲染（含头像、粉丝牌、UL等级、用户名及官方表情图文混排）
  Widget _buildDanmakuItem(
    LiveDanmakuMessage item,
    ColorScheme cs,
    ThemeData theme,
  ) {
    final avatar = item.userAvatar;
    final medalName = item.medalName;
    final userLevel = item.userLevel;
    final uname = item.senderName;
    final text = item.danmakuText ?? '';

    final inlineSpans = <InlineSpan>[];

    // 1. 粉丝勋章牌（根据官方配色渲染彩色胶囊徽章）
    if (medalName != null && medalName.isNotEmpty) {
      final medalColorInt = item.medalColor ?? 0;
      final Color medalColor = (medalColorInt > 0)
          ? Color(medalColorInt | 0xFF000000)
          : const Color(0xFF5896DE);
      inlineSpans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            margin: const EdgeInsets.only(right: 5),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: medalColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: medalColor.withValues(alpha: 0.7),
                width: 0.8,
              ),
            ),
            child: Text(
              '$medalName ${item.medalLevel ?? 1}',
              style: TextStyle(
                fontSize: 9.5,
                color: medalColor,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
            ),
          ),
        ),
      );
    }

    // 2. UL 用户等级铭牌
    if (userLevel != null && userLevel > 0) {
      inlineSpans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            margin: const EdgeInsets.only(right: 5),
            padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 1),
            decoration: BoxDecoration(
              color: cs.secondaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.5),
                width: 0.6,
              ),
            ),
            child: Text(
              'UL $userLevel',
              style: TextStyle(
                fontSize: 9.5,
                color: cs.onSecondaryContainer,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
            ),
          ),
        ),
      );
    }

    // 3. 用户名
    inlineSpans.add(
      TextSpan(
        text: '$uname: ',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: cs.primary,
        ),
      ),
    );

    // 4. 正文文本与官方表情解析图文混排
    inlineSpans.addAll(
      _buildDanmakuContentSpans(text, item.emots, theme.textTheme.bodySmall),
    );

    // 5. 大表情 / 贴纸
    if (item.emoteUrl != null && item.emoteUrl!.isNotEmpty) {
      inlineSpans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(left: 4, top: 2, bottom: 2),
            child: Image.network(
              item.emoteUrl!,
              height: 44,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 用户头像（22x22 圆形）
          if (avatar != null && avatar.isNotEmpty)
            ClipOval(
              child: NetworkImgLayer(
                src: avatar,
                width: 22,
                height: 22,
                type: 'avatar',
              ),
            )
          else
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
              ),
              child: Icon(Icons.person, size: 14, color: cs.outline),
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(children: inlineSpans),
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// 将弹幕文本中的 `[xxx]` 官方表情解析为真实图片 Span 进行图文混排渲染
  List<InlineSpan> _buildDanmakuContentSpans(
    String text,
    Map<String, dynamic>? customEmotes,
    TextStyle? defaultStyle,
  ) {
    if (text.isEmpty) return const [];
    final spans = <InlineSpan>[];
    int lastEnd = 0;

    for (final match in BilibiliEmotes.emotePattern.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(
          TextSpan(
            text: text.substring(lastEnd, match.start),
            style: defaultStyle,
          ),
        );
      }
      final emoteCode = match.group(0)!;
      String? emoteUrl;
      if (customEmotes != null && customEmotes.containsKey(emoteCode)) {
        final val = customEmotes[emoteCode];
        if (val is Map && val['url'] != null) {
          emoteUrl = val['url']?.toString();
        } else if (val is String) {
          emoteUrl = val;
        }
      }
      emoteUrl ??= BilibiliEmotes.defaultEmotes[emoteCode];

      if (emoteUrl != null && emoteUrl.isNotEmpty) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Image.network(
                emoteUrl,
                width: 20,
                height: 20,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    Text(emoteCode, style: defaultStyle),
              ),
            ),
          ),
        );
      } else {
        spans.add(TextSpan(text: emoteCode, style: defaultStyle));
      }
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(lastEnd),
          style: defaultStyle,
        ),
      );
    }

    return spans;
  }

  /// 底部互动发送条（表情选择器、输入框与发送按钮统一为严格等高的 40px 胶囊设计）
  Widget _buildChatInputBar(ColorScheme cs, ThemeData theme) {
    const double barItemHeight = 40.0;
    const double barItemRadius = 20.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        border: Border(
          top: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. 哔哩哔哩官方表情快捷选择器（严格 40x40 圆形图标，消除外层边距偏差）
          _buildEmotePickerButton(cs, barItemHeight),
          const SizedBox(width: 8),

          // 2. 弹幕输入框（外层 Container 严格限定为 40px 胶囊容器，保证与发送按钮完全等高且绝不缩瘪）
          Expanded(
            child: Container(
              height: barItemHeight,
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(barItemRadius),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _danmakuInputCtrl,
                      focusNode: _danmakuInputFocusNode,
                      enabled: !_isSendingDanmaku,
                      textInputAction: TextInputAction.send,
                      textAlignVertical: TextAlignVertical.center,
                      onSubmitted: (_) => _sendDanmaku(),
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: _isLiving ? '发个弹幕和主播互动吧~' : '未开播，无法发送弹幕',
                        hintStyle: TextStyle(color: cs.outline, fontSize: 13),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  if (_danmakuInputCtrl.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 24,
                        minHeight: 24,
                      ),
                      onPressed: () {
                        _danmakuInputCtrl.clear();
                        setState(() {});
                      },
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 3. 发送按钮（严格 40px 高度，与输入框和表情按钮完全等高且拥有同款 20px 圆角）
          SizedBox(
            height: barItemHeight,
            child: FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(68, barItemHeight),
                maximumSize: const Size(double.infinity, barItemHeight),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(barItemRadius),
                ),
              ),
              onPressed: (_isLiving &&
                      _danmakuInputCtrl.text.trim().isNotEmpty &&
                      !_isSendingDanmaku)
                  ? _sendDanmaku
                  : null,
              child: _isSendingDanmaku
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('发送', style: TextStyle(fontSize: 13)),
                        SizedBox(width: 4),
                        Icon(Icons.send_rounded, size: 14),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// 官方表情弹层选择器按钮（严格限定 size 宽高）
  Widget _buildEmotePickerButton(ColorScheme cs, [double size = 40.0]) {
    return PopupMenuButton<String>(
      tooltip: '选择官方表情',
      padding: EdgeInsets.zero,
      color: const Color(0xF01E1E1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.white12),
      ),
      offset: const Offset(0, -220),
      onSelected: (code) {
        final currentText = _danmakuInputCtrl.text;
        final selection = _danmakuInputCtrl.selection;
        final newText = (selection.start >= 0 && selection.end >= 0)
            ? currentText.replaceRange(selection.start, selection.end, code)
            : '$currentText$code';
        _danmakuInputCtrl.text = newText;
        _danmakuInputCtrl.selection = TextSelection.collapsed(
          offset: selection.start >= 0
              ? selection.start + code.length
              : newText.length,
        );
        setState(() {});
        _danmakuInputFocusNode.requestFocus();
      },
      itemBuilder: (context) {
        return [
          PopupMenuItem<String>(
            enabled: false,
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              width: 260,
              height: 200,
              child: GridView.builder(
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                ),
                itemCount: BilibiliEmotes.popularEmotes.length,
                itemBuilder: (context, i) {
                  final code = BilibiliEmotes.popularEmotes[i];
                  final url = BilibiliEmotes.defaultEmotes[code];
                  return InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      Navigator.pop(context, code);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: url != null
                          ? Image.network(
                              url,
                              width: 28,
                              height: 28,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => Center(
                                child: Text(
                                  code,
                                  style: const TextStyle(fontSize: 10),
                                ),
                              ),
                            )
                          : Center(
                              child: Text(
                                code,
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                    ),
                  );
                },
              ),
            ),
          ),
        ];
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: cs.surface.withValues(alpha: 0.75),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.sentiment_satisfied_alt_outlined,
          color: cs.outline,
          size: 20,
        ),
      ),
    );
  }
}
