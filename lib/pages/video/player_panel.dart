import 'dart:async';

import 'package:flutter/material.dart';

import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/core/storage/storage_key.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/pages/danmaku/view.dart';
import 'package:winwin/pages/video/danmaku_settings_panel.dart';
import 'package:winwin/pages/video/player_controller.dart';
import 'package:winwin/pages/video/send_danmaku_panel.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/utils/duration_utils.dart';

/// BiliPai 风格的播放器面板。
///
/// 主体为 mdk 注册的 Flutter `Texture`（黑色背景、按视频帧宽高比居中，
/// 等效 `BoxFit.contain`，无内置控制条），
/// 叠加缓冲/错误指示与一条深色半透明控制条（悬停/移动显示，3 秒无操作自动隐藏）。
class PlayerPanel extends StatefulWidget {
  const PlayerPanel({
    super.key,
    required this.controller,
    this.fullscreen = false,
    this.onToggleFullscreen,
  });

  final WinWinPlayerController controller;
  final bool fullscreen;
  final VoidCallback? onToggleFullscreen;

  @override
  State<PlayerPanel> createState() => _PlayerPanelState();
}

class _PlayerPanelState extends State<PlayerPanel> {
  Timer? _hideTimer;
  final ValueNotifier<bool> _controlsVisible = ValueNotifier(true);
  bool _draggingProgress = false;
  double _dragSeconds = 0;
  bool _volumePopupOpen = false;

  @override
  void initState() {
    super.initState();
    _showControlsTemporarily();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controlsVisible.dispose();
    super.dispose();
  }

  // ── 控制条显隐 ──

  void _showControlsTemporarily() {
    _controlsVisible.value = true;
    _resetHideTimer();
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), _maybeAutoHide);
  }

  void _maybeAutoHide() {
    if (!mounted) return;
    final c = widget.controller;
    // 仅当播放中、未拖动进度、未打开音量弹层时才自动隐藏。
    if (c.playing.value && !_draggingProgress && !_volumePopupOpen) {
      _controlsVisible.value = false;
    }
  }

  void _onPointerActivity() {
    _controlsVisible.value = true;
    _resetHideTimer();
  }

  void _hideControlsNow() {
    _hideTimer?.cancel();
    _controlsVisible.value = false;
    if (_volumePopupOpen) {
      setState(() => _volumePopupOpen = false);
    }
  }

  // ── 交互 ──

  void _onVideoTap() {
    widget.controller.playOrPause();
    _onPointerActivity();
  }

  void _toggleVolumePopup() {
    setState(() => _volumePopupOpen = !_volumePopupOpen);
    _onPointerActivity();
  }

  // ── build ──

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return MouseRegion(
      onHover: (_) => _onPointerActivity(),
      onEnter: (_) => _onPointerActivity(),
      onExit: (_) => _hideControlsNow(),
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildVideoSurface(c),
            // 弹幕层（IgnorePointer，不拦截鼠标/点击）。
            Positioned.fill(
              child: WinWinDanmaku(
                controller: c,
                fullscreen: widget.fullscreen,
              ),
            ),
            // 点击视频区域切换播放/暂停。
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _onVideoTap,
              ),
            ),
            _buildCenterOverlay(),
            if (_volumePopupOpen) _buildVolumePopup(),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ValueListenableBuilder<bool>(
                valueListenable: _controlsVisible,
                builder: (context, visible, _) {
                  return AnimatedOpacity(
                    opacity: visible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !visible,
                      child: _buildControlBar(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 视频渲染面：mdk 将解码帧注册为 Flutter Texture。
  ///
  /// 纹理未就绪时显示纯黑占位；就绪后按 [WinWinPlayerController.videoSize]
  /// 的宽高比居中显示（等效 `BoxFit.contain`）。
  Widget _buildVideoSurface(WinWinPlayerController c) {
    return ValueListenableBuilder<int?>(
      valueListenable: c.textureId,
      builder: (context, texId, _) {
        if (texId == null || texId < 0) return const SizedBox.expand();
        final texture = Texture(textureId: texId);
        return ValueListenableBuilder<Size?>(
          valueListenable: c.videoSize,
          builder: (context, size, _) {
            if (size == null || size.width <= 0 || size.height <= 0) {
              return texture;
            }
            return Center(
              child: AspectRatio(
                aspectRatio: size.width / size.height,
                child: texture,
              ),
            );
          },
        );
      },
    );
  }

  /// 中心缓冲/错误指示。
  Widget _buildCenterOverlay() {
    final c = widget.controller;
    return ValueListenableBuilder<String?>(
      valueListenable: c.error,
      builder: (context, err, _) {
        if (err != null && err.isNotEmpty) {
          return Center(child: _buildError(err));
        }
        return ValueListenableBuilder<bool>(
          valueListenable: c.buffering,
          builder: (context, isBuffering, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: c.ready,
              builder: (context, isReady, _) {
                final showSpinner = isBuffering || !isReady;
                if (!showSpinner) return const SizedBox.shrink();
                return const Center(
                  child: CircularProgressIndicator(color: biliPink),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildError(String message) {
    return Container(
      padding: const EdgeInsets.all(Style.lg),
      color: const Color(0x99000000),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.white70, size: 40),
          const SizedBox(height: Style.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: Style.md),
          TextButton(
            onPressed: widget.controller.load,
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  /// 底部控制条。
  Widget _buildControlBar() {
    final c = widget.controller;
    return Container(
      color: const Color(0x99000000),
      padding: const EdgeInsets.symmetric(
        horizontal: Style.md,
        vertical: Style.xs,
      ),
      child: Row(
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: c.playing,
            builder: (context, isPlaying, _) {
              return IconButton(
                icon: Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                ),
                onPressed: c.playOrPause,
              );
            },
          ),
          _buildTimeText(),
          const SizedBox(width: Style.sm),
          Expanded(child: _buildProgressSlider()),
          const SizedBox(width: Style.sm),
          IconButton(
            icon: const Icon(Icons.volume_up, color: Colors.white),
            onPressed: _toggleVolumePopup,
          ),
          _buildQualityButton(),
          _buildDanmakuToggleButton(),
          _buildSpeedButton(),
          IconButton(
            tooltip: '发弹幕',
            icon: const Icon(Icons.comment_outlined, color: Colors.white),
            onPressed: () => showSendDanmakuPanel(context, controller: c),
          ),
          IconButton(
            tooltip: '弹幕设置',
            icon: const Icon(Icons.tune, color: Colors.white),
            onPressed: () => showDanmakuSettingsPanel(
              context,
              controller: c,
              fullscreen: widget.fullscreen,
            ),
          ),
          IconButton(
            icon: Icon(
              widget.fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
              color: Colors.white,
            ),
            onPressed: widget.onToggleFullscreen,
          ),
        ],
      ),
    );
  }

  Widget _buildTimeText() {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: Listenable.merge([c.position, c.duration]),
      builder: (context, _) {
        final pos = DurationUtils.formatDuration(c.position.value.inSeconds);
        final dur = DurationUtils.formatDuration(c.duration.value.inSeconds);
        return Text(
          '$pos / $dur',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        );
      },
    );
  }

  Widget _buildProgressSlider() {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: Listenable.merge([c.position, c.duration]),
      builder: (context, _) {
        final durSec = c.duration.value.inSeconds.toDouble();
        final maxSec = durSec > 0 ? durSec : 1.0;
        final posSec = _draggingProgress
            ? _dragSeconds
            : c.position.value.inSeconds.toDouble();
        final value = posSec.clamp(0.0, maxSec).toDouble();
        return SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            activeTrackColor: biliPink,
            inactiveTrackColor: Colors.white24,
            thumbColor: biliPink,
            overlayColor: const Color(0x33FA7298),
          ),
          child: Slider(
            value: value,
            min: 0,
            max: maxSec,
            onChangeStart: (v) {
              setState(() {
                _draggingProgress = true;
                _dragSeconds = v;
              });
            },
            onChanged: (v) {
              setState(() => _dragSeconds = v);
            },
            onChangeEnd: (v) {
              setState(() => _draggingProgress = false);
              c.seek(Duration(seconds: v.round()));
            },
          ),
        );
      },
    );
  }

  Widget _buildQualityButton() {
    final c = widget.controller;
    return ValueListenableBuilder<int>(
      valueListenable: c.qualityVersion,
      builder: (context, _, _) {
        final labels = c.qualityLabels;
        final current = c.currentQualityIndex;
        if (labels.isEmpty) {
          return const SizedBox.shrink();
        }
        return PopupMenuButton<int>(
          tooltip: '画质',
          onSelected: c.switchQuality,
          itemBuilder: (context) => [
            for (int i = 0; i < labels.length; i++)
              PopupMenuItem<int>(
                value: i,
                child: Text(
                  labels[i],
                  style: TextStyle(
                    color: i == current ? biliPink : null,
                    fontWeight:
                        i == current ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Style.sm),
            child: Text(
              (current >= 0 && current < labels.length)
                  ? labels[current]
                  : '画质',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        );
      },
    );
  }

  /// 弹幕开关按钮：切换 Pref.enableShowDanmaku（弹幕层经
  /// AnimatedOpacity 渐显/渐隐）。
  Widget _buildDanmakuToggleButton() {
    final enabled = Pref.enableShowDanmaku;
    return IconButton(
      tooltip: enabled ? '关闭弹幕' : '开启弹幕',
      icon: Icon(
        enabled ? Icons.subtitles_outlined : Icons.subtitles_off,
        color: Colors.white,
      ),
      onPressed: () {
        GStorage.setting.put(SettingBoxKey.enableShowDanmaku, !enabled);
        setState(() {});
      },
    );
  }

  /// 倍速菜单：speedList 选项、当前值打勾，选中后 setPlaybackSpeed。
  Widget _buildSpeedButton() {
    final c = widget.controller;
    return ValueListenableBuilder<double>(
      valueListenable: c.playbackSpeed,
      builder: (context, speed, _) {
        return PopupMenuButton<double>(
          tooltip: '倍速',
          onSelected: c.setPlaybackSpeed,
          itemBuilder: (context) => [
            for (final v in c.speedList)
              CheckedPopupMenuItem<double>(
                value: v,
                checked: v == speed,
                child: Text('${v.toStringAsFixed(1)}x'),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Style.sm),
            child: Text(
              '${speed.toStringAsFixed(1)}x',
              style: TextStyle(
                color: speed == 1.0 ? Colors.white70 : biliPink,
                fontSize: 12,
                fontWeight: speed == 1.0 ? FontWeight.normal : FontWeight.bold,
              ),
            ),
          ),
        );
      },
    );
  }

  /// 音量弹出 Slider。
  Widget _buildVolumePopup() {
    final c = widget.controller;
    return Positioned(
      left: Style.lg,
      bottom: 60,
      child: Material(
        color: const Color(0xE61A1A1A),
        borderRadius: BorderRadius.circular(Style.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Style.md,
            vertical: Style.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.volume_up, color: Colors.white70, size: 18),
              const SizedBox(width: Style.sm),
              SizedBox(
                width: 140,
                child: ValueListenableBuilder<double>(
                  valueListenable: c.volume,
                  builder: (context, vol, _) {
                    return Slider(
                      value: vol.clamp(0.0, 100.0).toDouble(),
                      min: 0,
                      max: 100,
                      activeColor: biliPink,
                      inactiveColor: Colors.white24,
                      onChanged: c.setVolume,
                    );
                  },
                ),
              ),
              const SizedBox(width: Style.sm),
              ValueListenableBuilder<double>(
                valueListenable: c.volume,
                builder: (context, vol, _) {
                  return Text(
                    '${vol.round()}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
