import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/core/storage/storage_key.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/models/video/play_info.dart';
import 'package:winwin/pages/danmaku/view.dart';
import 'package:winwin/pages/video/danmaku_settings_panel.dart';
import 'package:winwin/pages/video/desktop_pip.dart';
import 'package:winwin/pages/video/player_controller.dart';
import 'package:winwin/pages/video/player_focus.dart';
import 'package:winwin/pages/video/send_danmaku_panel.dart';
import 'package:winwin/pages/video/subtitle_settings_panel.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/utils/duration_utils.dart';

/// Duration 没有 clamp 方法，手动实现（用于 seek 位置限制）。
Duration _clampDuration(Duration value, Duration min, Duration max) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

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
    this.onEscape,
  });

  final WinWinPlayerController controller;
  final bool fullscreen;
  final VoidCallback? onToggleFullscreen;

  /// Esc 键回调（固定语义：返回上一级）。
  final VoidCallback? onEscape;

  @override
  State<PlayerPanel> createState() => _PlayerPanelState();
}

class _PlayerPanelState extends State<PlayerPanel> {
  Timer? _hideTimer;
  final ValueNotifier<bool> _controlsVisible = ValueNotifier(true);
  bool _draggingProgress = false;
  double _dragSeconds = 0;
  bool _volumePopupOpen = false;

  // ── Phase 4.3 手势反馈状态 ──
  /// 双击快进/快退波纹反馈：(isForward, deltaSec)，null 表示无反馈。
  final ValueNotifier<({bool isForward, int deltaSec})?> _doubleTapFeedback =
      ValueNotifier(null);
  /// 长按倍速反馈：非 null 时显示倍速指示器。
  final ValueNotifier<double?> _longPressSpeedFeedback = ValueNotifier(null);
  /// 水平拖动快进反馈：(deltaSec, targetPosition)，null 表示无反馈。
  final ValueNotifier<({int deltaSec, Duration target})?> _dragSeekFeedback =
      ValueNotifier(null);
  /// 控制条锁定（L 键 / 按钮切换），锁定后隐藏控制条且不响应手势。
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    _showControlsTemporarily();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controlsVisible.dispose();
    _doubleTapFeedback.dispose();
    _longPressSpeedFeedback.dispose();
    _dragSeekFeedback.dispose();
    super.dispose();
  }

  // ── Phase 4.3 手势反馈 ──

  /// 双击快进/快退反馈：短暂显示波纹 + 时间提示。
  void _onDoubleTapFeedback(bool isForward, int deltaSec) {
    _doubleTapFeedback.value = (isForward: isForward, deltaSec: deltaSec);
    // 800ms 后自动清除反馈。
    Timer(const Duration(milliseconds: 800), () {
      _doubleTapFeedback.value = null;
    });
  }

  /// 长按倍速反馈。
  void _onLongPressSpeedChange(bool isLongPress, double speed) {
    _longPressSpeedFeedback.value = isLongPress ? speed : null;
  }

  /// 水平拖动快进反馈。
  void _onDragSeeking(int deltaSec, Duration target) {
    _dragSeekFeedback.value = (deltaSec: deltaSec, target: target);
  }

  /// 切换控制条锁定。
  void _toggleLock() {
    setState(() {
      _locked = !_locked;
      if (_locked) {
        _hideControlsNow();
      } else {
        _showControlsTemporarily();
      }
    });
  }

  /// 切换弹幕开关（键盘 D 键 / 按钮共用）。
  void _toggleDanmaku() {
    final enabled = Pref.enableShowDanmaku;
    GStorage.setting.put(SettingBoxKey.enableShowDanmaku, !enabled);
    setState(() {});
  }

  /// Phase 4.6：截图 — 捕获当前帧并弹出预览对话框。
  Future<void> _takeScreenshot() async {
    final c = widget.controller;
    // 提示正在截图。
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('正在截图…'),
        duration: Duration(seconds: 1),
      ),
    );
    final png = await c.screenshot();
    if (!mounted || png == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('截图失败'), duration: Duration(seconds: 1)),
      );
      return;
    }
    if (!mounted) return;
    _showScreenshotPreview(png);
  }

  /// Phase 4.6：截图预览对话框 — 显示截图 + 保存按钮。
  void _showScreenshotPreview(Uint8List png) {
    showDialog<void>(
      context: context,
      builder: (context) => _ScreenshotPreviewDialog(png: png),
    );
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
    // 锁定状态 / 播放中 / 未拖动进度 / 未打开音量弹层时才自动隐藏。
    if (!_locked &&
        c.playing.value &&
        !_draggingProgress &&
        !_volumePopupOpen) {
      _controlsVisible.value = false;
    }
  }

  void _onPointerActivity() {
    if (_locked) return; // 锁定时不响应鼠标活动显示控制条。
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

  // ── Phase 4.3 手势状态 ──
  /// 水平拖动起始位置（用于计算 delta）。
  Duration? _hDragStart;
  double _hDragDelta = 0;
  Timer? _dragFeedbackTimer;
  /// 双击位置（用于波纹动画定位）。
  Offset? _doubleTapPos;
  /// 长按倍速前的原始速度。
  double? _longPressOriginalSpeed;

  double get _longPressSpeed {
    return GStorage.video
        .get(VideoBoxKey.longPressSpeedDefault, defaultValue: 3.0);
  }

  void _onDoubleTapDown(TapDownDetails details) {
    _doubleTapPos = details.localPosition;
  }

  void _onDoubleTap() {
    final c = widget.controller;
    final pos = _doubleTapPos;
    if (pos == null) return;
    // 用 RenderBox 判断左右半区。
    final renderBox = context.findRenderObject() as RenderBox?;
    final width = renderBox?.size.width ?? 1;
    final isRight = pos.dx > width / 2;
    final delta = isRight ? 10 : -10;
    final target = _clampDuration(
      c.position.value + Duration(seconds: delta),
      Duration.zero,
      c.duration.value,
    );
    c.seek(target);
    _onDoubleTapFeedback(isRight, delta.abs());
    _onPointerActivity();
  }

  void _onLongPressStart() {
    final c = widget.controller;
    _longPressOriginalSpeed = c.playbackSpeed.value;
    final target = _longPressSpeed;
    c.setPlaybackSpeed(target);
    _onLongPressSpeedChange(true, target);
  }

  void _onLongPressEnd() {
    final c = widget.controller;
    c.setPlaybackSpeed(_longPressOriginalSpeed ?? 1.0);
    _longPressOriginalSpeed = null;
    _onLongPressSpeedChange(false, 0);
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    _hDragStart = widget.controller.position.value;
    _hDragDelta = 0;
    _dragFeedbackTimer?.cancel();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (_hDragStart == null) return;
    _hDragDelta += details.delta.dx;
    final deltaSec = (_hDragDelta * 0.5).round(); // 0.5 灵敏度
    final target = _clampDuration(
      _hDragStart! + Duration(seconds: deltaSec),
      Duration.zero,
      widget.controller.duration.value,
    );
    _onDragSeeking(deltaSec, target);
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_hDragStart != null) {
      final deltaSec = (_hDragDelta * 0.5).round();
      final target = _clampDuration(
        _hDragStart! + Duration(seconds: deltaSec),
        Duration.zero,
        widget.controller.duration.value,
      );
      widget.controller.seek(target);
    }
    _hDragStart = null;
    _hDragDelta = 0;
    // 500ms 后清除拖动反馈。
    _dragFeedbackTimer?.cancel();
    _dragFeedbackTimer = Timer(const Duration(milliseconds: 500), () {
      _dragSeekFeedback.value = null;
    });
  }

  // ── build ──

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return PlayerFocus(
      controller: c,
      enabled: !_locked,
      onToggleFullscreen: widget.onToggleFullscreen,
      onEscape: widget.onEscape,
      onToggleDanmaku: _toggleDanmaku,
      onLockToggle: (locked) => setState(() {
        _locked = locked;
        if (_locked) {
          _hideControlsNow();
        } else {
          _showControlsTemporarily();
        }
      }),
      onScreenshot: () => _takeScreenshot(),
      child: MouseRegion(
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
              // Phase 4.4：字幕层（底部居中，IgnorePointer 不拦截手势）。
              Positioned.fill(
                child: IgnorePointer(child: _buildSubtitleLayer(c)),
              ),
              // Phase 4.3：手势层 — 单击(播放/暂停) + 双击(快进/快退) +
              // 长按(3x倍速) + 水平拖动(快进)。
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _onVideoTap,
                  onDoubleTapDown: _onDoubleTapDown,
                  onDoubleTap: _onDoubleTap,
                  onLongPressStart: (_) => _onLongPressStart(),
                  onLongPressEnd: (_) => _onLongPressEnd(),
                  onHorizontalDragStart: _onHorizontalDragStart,
                  onHorizontalDragUpdate: _onHorizontalDragUpdate,
                  onHorizontalDragEnd: _onHorizontalDragEnd,
                ),
              ),
              _buildCenterOverlay(),
              // Phase 4.3：手势反馈叠加层。
              _buildDoubleTapFeedback(),
              _buildLongPressSpeedFeedback(),
              _buildDragSeekFeedback(),
              if (_volumePopupOpen) _buildVolumePopup(),
              // Phase 4.3：锁定指示器（锁定时显示解锁按钮）。
              if (_locked) _buildLockIndicator(),
              if (!_locked)
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
      ),
    );
  }

  /// Phase 4.3：双击快进/快退波纹反馈。
  Widget _buildDoubleTapFeedback() {
    return ValueListenableBuilder<({bool isForward, int deltaSec})?>(
      valueListenable: _doubleTapFeedback,
      builder: (context, feedback, _) {
        if (feedback == null) return const SizedBox.shrink();
        final pos = _doubleTapPos;
        final align = pos != null
            ? Alignment(
                (pos.dx / (context.size?.width ?? 1)) * 2 - 1,
                (pos.dy / (context.size?.height ?? 1)) * 2 - 1,
              )
            : feedback.isForward
                ? Alignment.centerRight
                : Alignment.centerLeft;
        return Positioned.fill(
          child: IgnorePointer(
            child: Align(
              alignment: align,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Style.lg,
                  vertical: Style.md,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(Style.radiusSm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      feedback.isForward
                          ? Icons.fast_forward
                          : Icons.fast_rewind,
                      color: Colors.white,
                      size: 28,
                    ),
                    const SizedBox(width: Style.xs),
                    Text(
                      '${feedback.isForward ? '+' : '-'}${feedback.deltaSec}s',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Phase 4.3：长按倍速指示器。
  Widget _buildLongPressSpeedFeedback() {
    return ValueListenableBuilder<double?>(
      valueListenable: _longPressSpeedFeedback,
      builder: (context, speed, _) {
        if (speed == null) return const SizedBox.shrink();
        return const Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fast_forward, color: biliPink, size: 40),
                  SizedBox(height: Style.xs),
                  Text(
                    '倍速播放中',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Phase 4.3：水平拖动快进指示器。
  Widget _buildDragSeekFeedback() {
    return ValueListenableBuilder<({int deltaSec, Duration target})?>(
      valueListenable: _dragSeekFeedback,
      builder: (context, feedback, _) {
        if (feedback == null) return const SizedBox.shrink();
        final isForward = feedback.deltaSec >= 0;
        return Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Style.lg,
                  vertical: Style.md,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(Style.radiusSm),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isForward
                              ? Icons.fast_forward
                              : Icons.fast_rewind,
                          color: biliPink,
                          size: 20,
                        ),
                        const SizedBox(width: Style.xs),
                        Text(
                          '${isForward ? '+' : ''}${feedback.deltaSec}s',
                          style: const TextStyle(
                            color: biliPink,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Style.xs),
                    Text(
                      DurationUtils.formatDuration(feedback.target.inSeconds),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Phase 4.3：锁定指示器（锁定时仅显示一个解锁按钮）。
  Widget _buildLockIndicator() {
    return Center(
      child: IconButton(
        icon: const Icon(Icons.lock, color: Colors.white70, size: 32),
        onPressed: _toggleLock,
        tooltip: '解锁控制条',
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
            onPressed: () => widget.controller.load(
              start: widget.controller.position.value,
            ),
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
          _buildAudioTrackButton(),
          _buildQualityButton(),
          _buildDanmakuToggleButton(),
          _buildSubtitleButton(),
          _buildSpeedButton(),
          _buildChapterButton(),
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
            tooltip: '锁定控制条',
            icon: const Icon(Icons.lock_outline, color: Colors.white),
            onPressed: _toggleLock,
          ),
          // Phase 4.6：桌面伪 PiP（非全屏时可用）。
          if (!widget.fullscreen)
            IconButton(
              tooltip: '画中画',
              icon: const Icon(
                Icons.picture_in_picture_alt,
                color: Colors.white,
              ),
              onPressed: () => DesktopPipController.instance.togglePip(),
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
        final chapters = c.viewPoints;
        return Stack(
          alignment: Alignment.center,
          children: [
            SliderTheme(
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
            ),
            // Phase 4.5：章节标记（view_points）— 在进度条上显示竖线标记。
            if (chapters.isNotEmpty && durSec > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: CustomPaint(
                      painter: _ChapterMarkerPainter(
                        chapters: chapters,
                        durationSec: durSec,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ),
              ),
          ],
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
      onPressed: _toggleDanmaku,
    );
  }

  /// Phase 4.4：字幕按钮 — 打开字幕选择 + 样式设置面板。
  Widget _buildSubtitleButton() {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: c.subtitle,
      builder: (context, _) {
        final hasSubtitles = c.subtitle.available.isNotEmpty;
        final isActive = c.subtitle.current != null;
        return IconButton(
          tooltip: '字幕',
          icon: Icon(
            isActive ? Icons.closed_caption : Icons.closed_caption_outlined,
            color: isActive ? biliPink : Colors.white,
            size: 20,
          ),
          onPressed: hasSubtitles
              ? () => showSubtitleSettingsPanel(
                    context,
                    controller: c,
                    fullscreen: widget.fullscreen,
                  )
              : null,
        );
      },
    );
  }

  /// Phase 4.4：字幕渲染层 — 监听播放进度 + SubtitleController，
  /// 显示当前字幕行（可配置字号/字重/描边/背景/边距）。
  Widget _buildSubtitleLayer(WinWinPlayerController c) {
    return ListenableBuilder(
      listenable: Listenable.merge([c.subtitle, c.position]),
      builder: (context, _) {
        final cue = c.subtitle.currentCue(c.position.value);
        if (cue == null) return const SizedBox.shrink();
        final text = cue.text.trim();
        if (text.isEmpty) return const SizedBox.shrink();
        final scale = widget.fullscreen
            ? Pref.subtitleFontScaleFS
            : Pref.subtitleFontScale;
        final bgOpacity = Pref.subtitleBgOpacity;
        final strokeWidth = Pref.subtitleStrokeWidth;
        final fontWeight = _fontWeightFromIndex(Pref.subtitleFontWeight);
        final padH = Pref.subtitlePaddingH.toDouble();
        final padB = Pref.subtitlePaddingB.toDouble();
        return Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(
              left: padH,
              right: padH,
              bottom: padB + (widget.fullscreen ? 60 : 48),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Style.sm,
                vertical: Style.xs,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(bgOpacity),
                borderRadius: BorderRadius.circular(Style.radiusXs),
              ),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16 * scale,
                  height: 1.4,
                  fontWeight: fontWeight,
                  shadows: strokeWidth > 0
                      ? [
                          Shadow(
                            offset: const Offset(0, 1),
                            blurRadius: strokeWidth,
                            color: Colors.black,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 字重索引（0-8）→ FontWeight 映射。
  static FontWeight _fontWeightFromIndex(int idx) {
    const weights = [
      FontWeight.w100,
      FontWeight.w200,
      FontWeight.w300,
      FontWeight.w400,
      FontWeight.w500,
      FontWeight.w600,
      FontWeight.w700,
      FontWeight.w800,
      FontWeight.w900,
    ];
    if (idx < 0 || idx >= weights.length) return FontWeight.w500;
    return weights[idx];
  }

  /// Phase 4.7：音轨选择 + 音频归一化开关。
  /// 仅当存在多条音轨时显示按钮；单轨时隐藏。
  Widget _buildAudioTrackButton() {
    final c = widget.controller;
    final tracks = c.audioTracks;
    if (tracks.length <= 1) return const SizedBox.shrink();
    final active = c.activeAudioTrackIndices;
    final activeIndex = active.isNotEmpty ? active.first : -1;
    return PopupMenuButton<String>(
      tooltip: '音轨',
      icon: const Icon(Icons.graphic_eq, color: Colors.white, size: 20),
      onSelected: (value) {
        if (value == '__normalize') {
          c.setAudioNormalize(!c.audioNormalizeEnabled);
        } else {
          final idx = int.tryParse(value);
          if (idx != null) c.switchAudioTrack(idx);
        }
      },
      itemBuilder: (context) => [
        for (final t in tracks)
          PopupMenuItem<String>(
            value: t.index.toString(),
            child: Row(
              children: [
                Icon(
                  t.index == activeIndex
                      ? Icons.check
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: t.index == activeIndex ? biliPink : null,
                ),
                const SizedBox(width: Style.xs),
                Flexible(
                  child: Text(
                    t.title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color:
                          t.index == activeIndex ? biliPink : null,
                      fontWeight: t.index == activeIndex
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: '__normalize',
          child: Row(
            children: [
              Icon(
                c.audioNormalizeEnabled
                    ? Icons.check_box
                    : Icons.check_box_outline_blank,
                size: 18,
                color: c.audioNormalizeEnabled ? biliPink : null,
              ),
              const SizedBox(width: Style.xs),
              const Text('音频归一化'),
            ],
          ),
        ),
      ],
    );
  }

  /// Phase 4.5：章节列表按钮 — PopupMenu 显示章节，点击跳转。
  Widget _buildChapterButton() {
    final c = widget.controller;
    final chapters = c.viewPoints;
    if (chapters.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<double>(
      tooltip: '章节',
      icon: const Icon(Icons.bookmarks_outlined, color: Colors.white, size: 20),
      onSelected: (sec) => c.seek(Duration(seconds: sec.round())),
      itemBuilder: (context) => [
        for (final vp in chapters)
          PopupMenuItem<double>(
            value: vp.from,
            child: Text(
              '${DurationUtils.formatDuration(vp.from.toInt())}  ${vp.title}',
              style: TextStyle(
                fontSize: 13,
                color: vp.contains(c.position.value.inSeconds.toDouble())
                    ? biliPink
                    : null,
                fontWeight: vp.contains(
                  c.position.value.inSeconds.toDouble(),
                )
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ),
      ],
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

/// Phase 4.5：章节标记画笔 — 在进度条上绘制章节起始位置的竖线。
class _ChapterMarkerPainter extends CustomPainter {
  _ChapterMarkerPainter({
    required this.chapters,
    required this.durationSec,
    required this.color,
  });

  final List<ViewPoint> chapters;
  final double durationSec;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (durationSec <= 0 || size.width <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    // 竖线高度：进度条上下各延伸 3px。
    const markerHeight = 6.0;
    final centerY = size.height / 2;
    for (final vp in chapters) {
      if (vp.from <= 0 || vp.from >= durationSec) continue;
      final x = (vp.from / durationSec) * size.width;
      canvas.drawLine(
        Offset(x, centerY - markerHeight / 2),
        Offset(x, centerY + markerHeight / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ChapterMarkerPainter oldDelegate) {
    return oldDelegate.durationSec != durationSec ||
        oldDelegate.chapters.length != chapters.length;
  }
}

/// Phase 4.6：截图预览对话框 — 显示截图 + 保存到本地按钮。
class _ScreenshotPreviewDialog extends StatefulWidget {
  const _ScreenshotPreviewDialog({required this.png});

  final Uint8List png;

  @override
  State<_ScreenshotPreviewDialog> createState() =>
      _ScreenshotPreviewDialogState();
}

class _ScreenshotPreviewDialogState extends State<_ScreenshotPreviewDialog> {
  bool _saving = false;
  String? _savedPath;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final dir = await getDownloadsDirectory();
      final folder = dir ?? await getApplicationDocumentsDirectory();
      final now = DateTime.now();
      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}_'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}'
          '${now.second.toString().padLeft(2, '0')}';
      final file = File('${folder.path}/WinWin_screenshot_$stamp.png');
      await file.writeAsBytes(widget.png);
      if (mounted) {
        setState(() {
          _savedPath = file.path;
          _saving = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('保存失败：$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: Style.lg,
        vertical: Style.xl,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(Style.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    '截图预览',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(height: 1),
              const SizedBox(height: Style.sm),
              Flexible(
                child: Image.memory(
                  widget.png,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: Style.sm),
              if (_savedPath != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: Style.xs),
                  child: Text(
                    '已保存：$_savedPath',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭'),
                  ),
                  const SizedBox(width: Style.sm),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download, size: 18),
                    label: Text(_savedPath != null ? '已保存' : '保存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
