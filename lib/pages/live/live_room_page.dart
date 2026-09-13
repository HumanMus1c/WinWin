import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fvp/mdk.dart' as mdk;

import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/core/account/account_service.dart';
import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/http/live.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/pages/member/member_space_page.dart';
import 'package:winwin/tcp/live.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/utils/num_utils.dart';
import 'package:winwin/core/storage/storage_pref.dart';

/// 桌面原生直播间播放页面。
///
/// 特性：
/// - 基于 fvp / mdk 原生硬解播放 HTTP-FLV / HLS 直播流；
/// - 接入 [LiveDanmakuClient] 二进制 WebSocket 协议接收实时弹幕；
/// - 桌面宽屏自适应双栏（左侧播放器与主播信息，右侧实时弹幕面板）；
/// - 播放/暂停、音量滑动调节、流刷新、全屏与下播状态兜底。
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
  late int _realRoomId;
  int _liveStatus = 0; // 0=未开播/已下播, 1=直播中, 2=轮播中

  bool _loading = true;
  String? _errorMessage;
  bool _isLiving = false;
  bool _isPlaying = true;
  double _volume = 1.0;
  bool _showControls = true;
  Timer? _controlsTimer;
  Timer? _watchdogTimer;
  List<String> _streamCandidates = [];
  int _currentStreamIndex = 0;

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
    _danmakuSub?.cancel();
    _danmakuClient?.dispose();
    _chatScrollCtrl.dispose();
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

    // 等待核心房间信息返回（并发执行，消除瀑布流等待）
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
    }

    // 立即刷新界面：更新主播昵称、头像、真实房间号、在线人气与直播状态胶囊徽章！
    if (mounted) {
      setState(() {});
    }

    // 确保弹幕预取完成
    await dmFuture;
    if (!mounted) return;

    // 2. 根据权威开播状态解耦处理音视频播放与实时 WebSocket 弹幕
    if (_isLiving) {
      unawaited(_setupDanmaku(_realRoomId));

      final playRes = await LiveHttp.liveRoomPlayInfo(roomId: _realRoomId);
      if (!mounted) return;

      if (playRes case Success(:final response)) {
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
      // 未开播/已下播/轮播：立刻释放播放器并解除 loading 状态，展示下播封面与状态
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

      // 关键时序：先异步 await prepare() 探测解复用与视频属性
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

    // 1. 获取官方动态 Token 与候选彗星服务器集群
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

  void _setVolume(double val) {
    setState(() => _volume = val);
    _player?.volume = val;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final displayTitle = _roomInfo?.title ?? widget.title ?? '直播间 $_realRoomId';
    final hostName = _roomInfo?.uname ?? widget.uname ?? 'UP 主';
    final hostAvatar = _roomInfo?.face;

    return Scaffold(
      appBar: AppBar(
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
                ClipboardData(text: 'https://live.bilibili.com/$_realRoomId'),
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
      body: LayoutBuilder(
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
                        _buildHostInfo(hostName, hostAvatar, cs, theme),
                      ],
                    ),
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 0.5,
                  color: cs.outlineVariant.withValues(alpha: 0.3),
                ),
                // 右侧实时弹幕面板
                Expanded(
                  flex: 3,
                  child: _buildChatPanel(cs, theme),
                ),
              ],
            );
          } else {
            return Column(
              children: [
                _buildPlayerBox(),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Style.md,
                    vertical: Style.sm,
                  ),
                  child: _buildHostInfo(hostName, hostAvatar, cs, theme),
                ),
                const Divider(height: 1, thickness: 0.5),
                Expanded(child: _buildChatPanel(cs, theme)),
              ],
            );
          }
        },
      ),
    );
  }

  /// 视频播放器区域
  Widget _buildPlayerBox() {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(Style.radiusMd),
        ),
        clipBehavior: Clip.antiAlias,
        child: MouseRegion(
          onHover: (_) => _onHoverPlayer(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 视频画面
              if (_isLiving && _textureId != null && _errorMessage == null)
                Texture(textureId: _textureId!)
              else
                _buildOfflineCover(),

              // 加载指示器（仅在开播拉取视频流且无错误时展示，下播或报错直接展示对应提示与重试）
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

              // 控制覆层
              if (_showControls && !_loading && _isLiving && _errorMessage == null)
                _buildControlsOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  /// 播放器下部悬浮控制条
  Widget _buildControlsOverlay() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.75),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            // 播放/暂停
            IconButton(
              icon: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 24,
              ),
              tooltip: _isPlaying ? '暂停' : '播放',
              onPressed: _togglePlay,
            ),
            const SizedBox(width: 8),
            // 直播中红点
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
            const Spacer(),
            // 音量控制
            Icon(
              _volume > 0 ? Icons.volume_up : Icons.volume_off,
              color: Colors.white70,
              size: 20,
            ),
            SizedBox(
              width: 90,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 2,
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
            const SizedBox(width: 8),
            // 刷新流
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white70, size: 20),
              tooltip: '重新加载',
              onPressed: _initLive,
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
      badgeText = '直播中';
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
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
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

    return Row(
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
            width: 44,
            height: 44,
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
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    roomIdText,
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
                  ),
                  if (areaName != null && areaName.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: cs.secondaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        areaName,
                        style: TextStyle(
                          fontSize: 10,
                          color: cs.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                  if (heatText != null && heatText.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.local_fire_department,
                      size: 13,
                      color: Colors.orange.shade700,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      heatText,
                      style: TextStyle(
                        fontSize: 11,
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
    );
  }

  /// 实时弹幕聊天面板
  Widget _buildChatPanel(ColorScheme cs, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 头部
        Padding(
          padding: const EdgeInsets.all(Style.md),
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
              const SizedBox(width: 4),
              Text(
                _isLiving ? '连接就绪' : '未连接',
                style: TextStyle(fontSize: 11, color: cs.outline),
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 0.5),
        // 弹幕列表
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
                  padding: const EdgeInsets.all(Style.sm),
                  itemCount: _danmakuList.length,
                  itemBuilder: (context, index) {
                    final item = _danmakuList[index];
                    final uname = item.senderName;
                    final text = item.danmakuText ?? '';

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '$uname: ',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: cs.primary,
                              ),
                            ),
                            TextSpan(
                              text: text,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
