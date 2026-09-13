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

  bool _loading = true;
  String? _errorMessage;
  bool _isLiving = false;
  bool _isPlaying = true;
  double _volume = 1.0;
  bool _showControls = true;
  Timer? _controlsTimer;

  final List<LiveDanmakuMessage> _danmakuList = [];
  final ScrollController _chatScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _startHideControlsTimer();
    _initLive();
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
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

    // 1. 获取直播间详细信息
    final infoRes = await LiveHttp.roomInfo(roomId: widget.roomId);
    if (infoRes case Success(:final response)) {
      _roomInfo = response;
    }

    // 2. 获取直播推流地址
    final playRes = await LiveHttp.liveRoomPlayInfo(roomId: widget.roomId);
    if (!mounted) return;

    if (playRes case Success(:final response)) {
      final playUrl = response.bestPlayUrl;
      final isLive = response.isLiving && playUrl != null && playUrl.isNotEmpty;
      _isLiving = isLive;

      if (isLive) {
        await _setupPlayer(playUrl);
        _setupDanmaku();
      }
      setState(() => _loading = false);
    } else if (playRes case Error(:final errMsg)) {
      // 若无法拉取推流，检测 roomInfo 的状态兜底
      if (_roomInfo != null && !_roomInfo!.isLiving) {
        _isLiving = false;
        setState(() => _loading = false);
      } else {
        setState(() {
          _errorMessage = errMsg ?? '获取直播流失败';
          _loading = false;
        });
      }
    }
  }

  Future<void> _setupPlayer(String url) async {
    try {
      final player = mdk.Player();
      _player = player;

      player.setProperty(
        'avio.headers',
        'Referer: https://live.bilibili.com\r\n'
        'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36\r\n',
      );
      // 直播低延迟缓冲窗口
      player.setBufferRange(min: 800, max: 3000);
      player.volume = _volume;

      player.media = url;
      final texId = await player.updateTexture();
      _textureId = texId;

      player.prepare();
      player.state = mdk.PlaybackState.playing;
      _isPlaying = true;
    } catch (e) {
      _errorMessage = '播放器初始化失败：$e';
    }
  }

  void _setupDanmaku() {
    _danmakuSub?.cancel();
    _danmakuClient?.dispose();

    final client = LiveDanmakuClient(
      roomId: widget.roomId,
      uid: AccountService().userInfo?.mid ?? 0,
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

    client.connect();
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
    final displayTitle = _roomInfo?.title ?? widget.title ?? '直播间 ${widget.roomId}';
    final hostName = _roomInfo?.uname ?? widget.uname ?? 'UP 主';
    final hostAvatar = _roomInfo?.face;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16),
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
                ClipboardData(text: 'https://live.bilibili.com/${widget.roomId}'),
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
              if (_isLiving && _textureId != null)
                Texture(textureId: _textureId!)
              else
                _buildOfflineCover(),

              // 加载指示器
              if (_loading)
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
              if (_showControls && !_loading && _isLiving)
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

  /// 未开播/已下播占位封面
  Widget _buildOfflineCover() {
    final effectiveCover = _roomInfo?.cover ?? widget.cover;
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
          color: Colors.black.withValues(alpha: 0.7),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.sensors_off_outlined,
                  size: 48,
                  color: Colors.white60,
                ),
                const SizedBox(height: 12),
                Text(
                  _errorMessage ?? '主播当前暂未开播或已下播',
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
                    '房间号: ${widget.roomId}',
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
                  if (online != null && online > 0) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.local_fire_department,
                      size: 13,
                      color: Colors.orange.shade700,
                    ),
                    Text(
                      NumUtils.formatNum(online),
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
                    final rawInfo = item.raw['info'] as List?;
                    final uname = rawInfo != null &&
                            rawInfo.length > 2 &&
                            rawInfo[2] is List &&
                            (rawInfo[2] as List).length > 1
                        ? rawInfo[2][1]?.toString() ?? '用户'
                        : '观众';
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
