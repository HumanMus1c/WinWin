import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:winwin/common/widgets/image/network_img_layer.dart';
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
import 'package:winwin/ui/components/hover_container.dart';
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
    this.cover,
    this.fullscreen = false,
    this.onToggleFullscreen,
    this.onEscape,
  });

  final WinWinPlayerController controller;
  final String? cover;
  final bool fullscreen;
  final VoidCallback? onToggleFullscreen;

  /// Esc 键回调（固定语义：返回上一级）。
  final VoidCallback? onEscape;

  @override
  State<PlayerPanel> createState() => _PlayerPanelState();
}

class _PlayerPanelState extends State<PlayerPanel> {
  Timer? _hideTimer;
  Timer? _feedbackTimer;
  final ValueNotifier<bool> _controlsVisible = ValueNotifier(true);
  bool _draggingProgress = false;
  double _dragSeconds = 0;
  double? _hoverSliderSeconds;
  double? _hoverSliderFraction;
  bool _volumePopupOpen = false;
  bool _chapterPanelOpen = false;

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
    _feedbackTimer?.cancel();
    _dragFeedbackTimer?.cancel();
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
    // 取消之前的 timer，防止重复触发
    _feedbackTimer?.cancel();
    // 800ms 后自动清除反馈。
    _feedbackTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        _doubleTapFeedback.value = null;
      }
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
    // 检查 controller 是否已 dispose
    if (widget.controller.disposed) return;
    final c = widget.controller;
    // 锁定状态 / 播放中 / 未拖动进度 / 未打开音量弹层 / 未打开章节面板时才自动隐藏。
    if (!_locked &&
        c.playing.value &&
        !_draggingProgress &&
        !_volumePopupOpen &&
        !_chapterPanelOpen) {
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
      if (mounted) {
        _dragSeekFeedback.value = null;
      }
    });
  }

  // ── build ──

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    // 安全检查：controller 已销毁时不渲染，避免访问已释放的资源
    if (c.disposed) {
      return const ColoredBox(color: Colors.black);
    }
    return PlayerFocus(
      controller: c,
      enabled: !_locked,
      onToggleFullscreen: widget.onToggleFullscreen,
      onEscape: () {
        if (_chapterPanelOpen) {
          setState(() => _chapterPanelOpen = false);
          return;
        }
        widget.onEscape?.call();
      },
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final panelWidth =
                  (constraints.maxWidth / 3).clamp(240.0, 560.0);
              return Stack(
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
                  // BiliPai centerPlayButton：暂停时居中显示大播放按钮
                  //（点击由手势层 _onVideoTap 接管，此处仅视觉展示）。
                  _buildCenterPlayButton(),
                  // Phase 4.3：手势反馈叠加层。
                  _buildDoubleTapFeedback(),
                  _buildLongPressSpeedFeedback(),
                  _buildDragSeekFeedback(),
                  if (_volumePopupOpen) _buildVolumePopup(),
                  // Phase 4.5：章节悬浮面板（覆盖右侧 1/3 区域）。
                  _buildChapterPanel(panelWidth),
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
              );
            },
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
                  color: Colors.black.withValues(alpha: 0.6),
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
                  color: Colors.black.withValues(alpha: 0.7),
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
  /// 包裹 [RepaintBoundary] 隔离控制条/弹幕/手势等上层高频 UI 的重绘影响。
  Widget _buildVideoSurface(WinWinPlayerController c) {
    final coverUrl = widget.cover;
    return RepaintBoundary(
      child: ValueListenableBuilder<int?>(
        valueListenable: c.textureId,
        builder: (context, texId, _) {
          return ValueListenableBuilder<Size?>(
            valueListenable: c.videoSize,
            builder: (context, size, _) {
              final hasFrame = texId != null &&
                  texId >= 0 &&
                  size != null &&
                  size.width > 0 &&
                  size.height > 0;

              Widget videoWidget;
              if (hasFrame) {
                videoWidget = Center(
                  child: AspectRatio(
                    aspectRatio: size.width / size.height,
                    child: Texture(textureId: texId),
                  ),
                );
              } else if (texId != null && texId >= 0) {
                videoWidget = Texture(textureId: texId);
              } else {
                videoWidget = const SizedBox.expand();
              }

              if (!hasFrame && coverUrl != null && coverUrl.isNotEmpty) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    NetworkImgLayer(
                      src: coverUrl,
                      width: double.infinity,
                      height: double.infinity,
                      borderRadius: BorderRadius.zero,
                    ),
                    videoWidget,
                  ],
                );
              }
              return videoWidget;
            },
          );
        },
      ),
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

  /// BiliPai 风格中央大播放按钮：就绪且暂停时显示，
  /// 点击穿透到手势层（_onVideoTap → playOrPause）。
  Widget _buildCenterPlayButton() {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: Listenable.merge([c.playing, c.ready, c.completed]),
      builder: (context, _) {
        final isPlaying = c.playing.value;
        final isReady = c.ready.value;
        final isCompleted = c.completed.value;
        if (!isReady || isPlaying) return const SizedBox.shrink();
        return Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: Color(0x8C000000),
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(Style.md),
                  child: Icon(
                    isCompleted
                        ? Icons.replay_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 44,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 底部控制条（BiliPai 风格）：进度条置顶 + 下方左右分区控制行。
  Widget _buildControlBar() {
    final c = widget.controller;
    // BiliPai 底部控制条：透明→黑渐变遮罩（bottomScrim）。
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Color(0xD9000000)],
        ),
      ),
      padding: const EdgeInsets.only(
        left: Style.sm,
        right: Style.sm,
        top: Style.lg,
        bottom: Style.xs,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 第一行：进度条（全宽）
          _buildProgressSlider(),
          const SizedBox(height: Style.xs),
          // 第二行：控制按钮（左右分区）
          Row(
            children: [
              // 左侧：播放/暂停 + 时间 + 弹幕开关
              _buildPlayPauseButton(),
              const SizedBox(width: Style.sm),
              _buildTimeText(),
              const SizedBox(width: Style.md),
              _buildDanmakuChip(),
              const Spacer(),
              // 右侧：音频标签 + 画质 + 倍速 + 章节 + 字幕 + 功能按钮
              _buildAudioCodecLabel(),
              _buildQualityLabel(),
              _buildSpeedLabel(),
              _buildChapterButton(),
              _buildSubtitleChip(),
              const SizedBox(width: Style.sm),
              _iconButton(
                icon: Icons.comment_outlined,
                tooltip: '发弹幕',
                onPressed: () => showSendDanmakuPanel(context, controller: c),
              ),
              _iconButton(
                icon: Icons.tune,
                tooltip: '弹幕设置',
                onPressed: () => showDanmakuSettingsPanel(
                  context,
                  controller: c,
                  fullscreen: widget.fullscreen,
                ),
              ),
              _iconButton(
                icon: Icons.volume_up,
                tooltip: '音量',
                onPressed: _toggleVolumePopup,
              ),
              _iconButton(
                icon: Icons.lock_outline,
                tooltip: '锁定控制条',
                onPressed: _toggleLock,
              ),
              if (!widget.fullscreen)
                _iconButton(
                  icon: Icons.picture_in_picture_alt,
                  tooltip: '画中画',
                  onPressed: () => DesktopPipController.instance.togglePip(),
                ),
              HoverContainer(
                onTap: widget.onToggleFullscreen,
                borderRadius: 6.0,
                padding: const EdgeInsets.all(6),
                hoverColor: Colors.white.withValues(alpha: 0.12),
                child: Icon(
                  widget.fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 播放/暂停按钮。
  Widget _buildPlayPauseButton() {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: Listenable.merge([c.playing, c.completed]),
      builder: (context, _) {
        final isPlaying = c.playing.value;
        final isCompleted = c.completed.value;
        return HoverContainer(
          onTap: c.playOrPause,
          borderRadius: 6.0,
          padding: const EdgeInsets.all(6),
          hoverColor: Colors.white.withValues(alpha: 0.12),
          child: Tooltip(
            message: isCompleted ? '重新播放' : (isPlaying ? '暂停' : '播放'),
            child: Icon(
              isPlaying
                  ? Icons.pause
                  : (isCompleted ? Icons.replay : Icons.play_arrow),
              color: Colors.white,
              size: 24,
            ),
          ),
        );
      },
    );
  }

  /// 控制条图标按钮统一风格：20px 图标 + 紧凑密度 + hover 效果。
  Widget _iconButton({
    required IconData icon,
    required VoidCallback? onPressed,
    String? tooltip,
    Color color = Colors.white,
  }) {
    return HoverContainer(
      onTap: onPressed,
      borderRadius: 6.0,
      padding: const EdgeInsets.all(6),
      hoverColor: Colors.white.withValues(alpha: 0.12),
      child: Tooltip(
        message: tooltip ?? '',
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }

  Widget _buildTimeText() {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: Listenable.merge([
        c.position,
        c.duration,
        c.viewPointsNotifier,
      ]),
      builder: (context, _) {
        final pos = DurationUtils.formatDuration(c.position.value.inSeconds);
        final dur = DurationUtils.formatDuration(c.duration.value.inSeconds);
        final curChapter = c.currentChapter();
        // B 站风格：当前时间纯白，总时长降饱和。
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: pos,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  TextSpan(
                    text: ' / $dur',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (curChapter != null && curChapter.title.isNotEmpty) ...[
              const SizedBox(width: Style.xs),
              HoverContainer(
                onTap: () {
                  setState(() => _chapterPanelOpen = !_chapterPanelOpen);
                  _onPointerActivity();
                },
                borderRadius: 4.0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                color: _chapterPanelOpen
                    ? biliBlue.withValues(alpha: 0.25)
                    : Colors.white.withValues(alpha: 0.08),
                hoverColor: biliBlue.withValues(alpha: 0.3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: Text(
                        '· ${curChapter.title}',
                        style: TextStyle(
                          color: _chapterPanelOpen
                              ? biliBlue
                              : Colors.white.withValues(alpha: 0.88),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 14,
                      color: _chapterPanelOpen ? biliBlue : Colors.white54,
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildProgressSlider() {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: Listenable.merge([
        c.position,
        c.duration,
        c.viewPointsNotifier,
      ]),
      builder: (context, _) {
        final durSec = c.duration.value.inSeconds.toDouble();
        final maxSec = durSec > 0 ? durSec : 1.0;
        final posSec = _draggingProgress
            ? _dragSeconds
            : c.position.value.inSeconds.toDouble();
        final value = posSec.clamp(0.0, maxSec).toDouble();
        final chapters = c.viewPoints;
        final previewSec = _draggingProgress
            ? _dragSeconds
            : _hoverSliderSeconds;
        final previewChapter =
            previewSec != null ? c.currentChapter(previewSec) : null;
        final showTooltip = previewSec != null && durSec > 0;

        return LayoutBuilder(
          builder: (context, constraints) {
            final sliderWidth = constraints.maxWidth;
            final targetFraction = _draggingProgress
                ? (value / maxSec)
                : (_hoverSliderFraction ?? (value / maxSec));
            final tooltipLeft = (targetFraction * (sliderWidth - 24)).clamp(
              8.0,
              (sliderWidth - 180).clamp(8.0, double.infinity),
            );

            return Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // Hover/Drag 章节与时间浮动预览提示
                if (showTooltip)
                  Positioned(
                    bottom: 28,
                    left: tooltipLeft,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xF0181818),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                            width: 0.5,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black54,
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              DurationUtils.formatDuration(previewSec.toInt()),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (previewChapter != null &&
                                previewChapter.title.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 160),
                                child: Text(
                                  previewChapter.title,
                                  style: const TextStyle(
                                    color: Color(0xFF00AEEC),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                MouseRegion(
                  onHover: (e) {
                    final localX =
                        (e.localPosition.dx - 12).clamp(0.0, sliderWidth - 24);
                    final fraction = (sliderWidth > 24)
                        ? (localX / (sliderWidth - 24)).clamp(0.0, 1.0)
                        : 0.0;
                    setState(() {
                      _hoverSliderFraction = fraction;
                      _hoverSliderSeconds = fraction * maxSec;
                    });
                    _onPointerActivity();
                  },
                  onExit: (_) {
                    setState(() {
                      _hoverSliderSeconds = null;
                      _hoverSliderFraction = null;
                    });
                  },
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12),
                      activeTrackColor: biliBlue,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: biliBlue,
                      overlayColor: const Color(0x3300AEEC),
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
      },
    );
  }

  /// BiliPai 风格画质文字标签：点击弹出画质选择菜单。
  Widget _buildQualityLabel() {
    final c = widget.controller;
    return ValueListenableBuilder<int>(
      valueListenable: c.qualityVersion,
      builder: (context, _, _) {
        final labels = c.qualityLabels;
        final current = c.currentQualityIndex;
        if (labels.isEmpty) return const SizedBox.shrink();
        return PopupMenuButton<int>(
          tooltip: '画质',
          onSelected: c.switchQuality,
          color: const Color(0xE61A1A1A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Style.radiusSm),
            side: const BorderSide(color: Colors.white12),
          ),
          itemBuilder: (context) => [
            for (int i = 0; i < labels.length; i++)
              PopupMenuItem<int>(
                value: i,
                child: Text(
                  labels[i],
                  style: TextStyle(
                    color: i == current ? biliBlue : Colors.white70,
                    fontWeight:
                        i == current ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
          ],
          child: HoverContainer(
            borderRadius: 6.0,
            padding: const EdgeInsets.symmetric(horizontal: Style.sm, vertical: 4),
            hoverColor: Colors.white.withValues(alpha: 0.12),
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

  /// BiliPai 风格弹幕开关圆角 chip：
  /// 开启时 primary α0.22 背景 + 图标 + "开" 文字，关闭时白色半透明 + "关"。
  Widget _buildDanmakuChip() {
    final enabled = Pref.enableShowDanmaku;
    return HoverContainer(
      onTap: _toggleDanmaku,
      borderRadius: Style.radiusFull,
      padding: const EdgeInsets.symmetric(
        horizontal: Style.sm,
        vertical: Style.xs,
      ),
      hoverColor: Colors.white.withValues(alpha: 0.12),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Style.sm,
          vertical: Style.xs,
        ),
        decoration: BoxDecoration(
          color: enabled ? biliBlue.withValues(alpha: 0.22) : Colors.white12,
          borderRadius: BorderRadius.circular(Style.radiusFull),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              enabled ? Icons.chat_bubble : Icons.chat_bubble_outline,
              size: 14,
              color: enabled ? biliBlue : Colors.white70,
            ),
            const SizedBox(width: Style.xs),
            Text(
              enabled ? '开' : '关',
              style: TextStyle(
                color: enabled ? biliBlue : Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// BiliPai 风格字幕 chip：有字幕时高亮，点击打开字幕面板。
  Widget _buildSubtitleChip() {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: c.subtitle,
      builder: (context, _) {
        final isActive = c.subtitle.current != null;
        return HoverContainer(
          onTap: () => showSubtitleSettingsPanel(
            context,
            controller: c,
            fullscreen: widget.fullscreen,
          ),
          borderRadius: Style.radiusFull,
          padding: const EdgeInsets.symmetric(
            horizontal: Style.sm,
            vertical: Style.xs,
          ),
          hoverColor: Colors.white.withValues(alpha: 0.12),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Style.sm,
              vertical: Style.xs,
            ),
            decoration: BoxDecoration(
              color: isActive ? biliBlue.withValues(alpha: 0.22) : Colors.white12,
              borderRadius: BorderRadius.circular(Style.radiusFull),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isActive ? Icons.closed_caption : Icons.closed_caption_outlined,
                  size: 14,
                  color: isActive ? biliBlue : Colors.white70,
                ),
                const SizedBox(width: Style.xs),
                Text(
                  '字幕',
                  style: TextStyle(
                    color: isActive ? biliBlue : Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// BiliPai 风格音频编码标签：显示当前音轨编码（如 "AAC"），点击打开音轨菜单。
  Widget _buildAudioCodecLabel() {
    final c = widget.controller;
    return ValueListenableBuilder<bool>(
      valueListenable: c.ready,
      builder: (context, ready, _) {
        if (!ready) return const SizedBox.shrink();
        final codec = c.audioCodecLabel;
        if (codec == null) return const SizedBox.shrink();
        final tracks = c.audioTracks;
        // 单轨时仅显示标签，多轨时弹出菜单。
        if (tracks.length <= 1) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: Style.sm),
            child: Text(
              codec,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          );
        }
        return PopupMenuButton<String>(
          tooltip: '音轨',
          color: const Color(0xE61A1A1A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Style.radiusSm),
            side: const BorderSide(color: Colors.white12),
          ),
          onSelected: (value) {
            if (value == '__normalize') {
              c.setAudioNormalize(!c.audioNormalizeEnabled);
            } else {
              final idx = int.tryParse(value);
              if (idx != null) c.switchAudioTrack(idx);
            }
          },
          itemBuilder: (context) {
            final active = c.activeAudioTrackIndices;
            final activeIndex = active.isNotEmpty ? active.first : -1;
            return [
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
                        color: t.index == activeIndex ? biliBlue : null,
                      ),
                      const SizedBox(width: Style.xs),
                      Flexible(
                        child: Text(
                          t.title,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color:
                                t.index == activeIndex ? biliBlue : Colors.white70,
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
                      color: c.audioNormalizeEnabled ? biliBlue : null,
                    ),
                    const SizedBox(width: Style.xs),
                    const Text('音频归一化'),
                  ],
                ),
              ),
            ];
          },
          child: HoverContainer(
            borderRadius: 6.0,
            padding: const EdgeInsets.symmetric(horizontal: Style.sm, vertical: 4),
            hoverColor: Colors.white.withValues(alpha: 0.12),
            child: Text(
              codec,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
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
        // 安全检查：controller 已销毁时不渲染
        if (c.disposed) return const SizedBox.shrink();
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
                color: Colors.black.withValues(alpha: bgOpacity),
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



  /// 章节列表按钮（BiliPai 风格圆角 chip）：有章节时显示，点击打开/关闭章节面板。
  Widget _buildChapterButton() {
    final c = widget.controller;
    return ValueListenableBuilder<List<ViewPoint>>(
      valueListenable: c.viewPointsNotifier,
      builder: (context, chapters, _) {
        if (chapters.isEmpty) return const SizedBox.shrink();
        final isOpen = _chapterPanelOpen;
        return HoverContainer(
          onTap: () {
            setState(() => _chapterPanelOpen = !_chapterPanelOpen);
            _onPointerActivity();
          },
          borderRadius: Style.radiusFull,
          padding: const EdgeInsets.symmetric(
            horizontal: Style.sm,
            vertical: Style.xs,
          ),
          hoverColor: Colors.white.withValues(alpha: 0.12),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Style.sm,
              vertical: Style.xs,
            ),
            decoration: BoxDecoration(
              color: isOpen ? biliBlue.withValues(alpha: 0.22) : Colors.white12,
              borderRadius: BorderRadius.circular(Style.radiusFull),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isOpen ? Icons.bookmarks : Icons.bookmarks_outlined,
                  size: 14,
                  color: isOpen ? biliBlue : Colors.white70,
                ),
                const SizedBox(width: Style.xs),
                Text(
                  '章节 (${chapters.length})',
                  style: TextStyle(
                    color: isOpen ? biliBlue : Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 章节悬浮面板 — 覆盖视频画面右侧 1/3 区域的黑色半透明面板，每行展示「缩略图 + 时间节点范围 + 章节标题」。
  Widget _buildChapterPanel(double panelWidth) {
    final c = widget.controller;
    return ValueListenableBuilder<List<ViewPoint>>(
      valueListenable: c.viewPointsNotifier,
      builder: (context, chapters, _) {
        if (chapters.isEmpty) return const SizedBox.shrink();
        return AnimatedPositioned(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          right: _chapterPanelOpen ? 0 : -panelWidth - 10,
          top: 0,
          bottom: 0,
          width: panelWidth,
          child: IgnorePointer(
            ignoring: !_chapterPanelOpen,
            child: MouseRegion(
              onHover: (_) => _onPointerActivity(),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {}, // 吸收点击，防止穿透到视频触发暂停
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xE6141414), // 黑色半透明
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(Style.radiusMd),
                      bottomLeft: Radius.circular(Style.radiusMd),
                    ),
                    border: Border(
                      left: BorderSide(
                        color: Colors.white.withValues(alpha: 0.12),
                        width: 0.8,
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(-4, 0),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // 顶部标题栏
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Style.md,
                          vertical: Style.md,
                        ),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: Colors.white.withValues(alpha: 0.08),
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.bookmarks_outlined,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: Style.sm),
                            Text(
                              '章节 (${chapters.length})',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            HoverContainer(
                              onTap: () {
                                setState(() => _chapterPanelOpen = false);
                              },
                              borderRadius: 6.0,
                              padding: const EdgeInsets.all(4),
                              hoverColor: Colors.white.withValues(alpha: 0.12),
                              child: const Icon(
                                Icons.close,
                                color: Colors.white70,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 章节列表
                      Expanded(
                        child: ListenableBuilder(
                          listenable: c.position,
                          builder: (context, _) {
                            final currentSec =
                                c.position.value.inSeconds.toDouble();
                            return ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                vertical: Style.xs,
                                horizontal: Style.xs,
                              ),
                              itemCount: chapters.length,
                              itemBuilder: (context, index) {
                                final vp = chapters[index];
                                final isCurrent = vp.contains(currentSec);
                                final fromStr = DurationUtils.formatDuration(
                                  vp.from.toInt(),
                                );
                                final toStr = DurationUtils.formatDuration(
                                  vp.to.toInt(),
                                );
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 2,
                                  ),
                                  child: HoverContainer(
                                    onTap: () {
                                      c.seek(Duration(seconds: vp.from.round()));
                                    },
                                    borderRadius: Style.radiusSm,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: Style.sm,
                                      vertical: Style.sm,
                                    ),
                                    color: isCurrent
                                        ? biliBlue.withValues(alpha: 0.16)
                                        : Colors.transparent,
                                    hoverColor: isCurrent
                                        ? biliBlue.withValues(alpha: 0.24)
                                        : Colors.white.withValues(alpha: 0.08),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        // 播放状态指示或序号
                                        SizedBox(
                                          width: 22,
                                          child: isCurrent
                                              ? const Icon(
                                                  Icons.play_arrow_rounded,
                                                  color: biliBlue,
                                                  size: 18,
                                                )
                                              : Text(
                                                  '${index + 1}'.padLeft(2, '0'),
                                                  style: TextStyle(
                                                    color: Colors.white.withValues(
                                                      alpha: 0.35,
                                                    ),
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                        ),
                                        if (vp.imgUrl != null &&
                                            vp.imgUrl!.isNotEmpty) ...[
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            child: NetworkImgLayer(
                                              src: vp.imgUrl,
                                              width: 44,
                                              height: 25,
                                            ),
                                          ),
                                          const SizedBox(width: Style.xs),
                                        ],
                                        // 时间节点范围
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isCurrent
                                                ? biliBlue.withValues(
                                                    alpha: 0.22,
                                                  )
                                                : Colors.white.withValues(
                                                    alpha: 0.06,
                                                  ),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '$fromStr - $toStr',
                                            style: TextStyle(
                                              color: isCurrent
                                                  ? biliBlue
                                                  : Colors.white.withValues(
                                                      alpha: 0.8,
                                                    ),
                                              fontSize: 11,
                                              fontWeight: isCurrent
                                                  ? FontWeight.w600
                                                  : FontWeight.normal,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: Style.sm),
                                        // 章节标题
                                        Expanded(
                                          child: Text(
                                            vp.title.isEmpty
                                                ? '章节 ${index + 1}'
                                                : vp.title,
                                            style: TextStyle(
                                              color: isCurrent
                                                  ? Colors.white
                                                  : Colors.white.withValues(
                                                      alpha: 0.9,
                                                    ),
                                              fontSize: 13,
                                              fontWeight: isCurrent
                                                  ? FontWeight.w600
                                                  : FontWeight.normal,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// BiliPai 风格倍速文字标签：1.0x 时显示"倍速"，非 1.0x 时显示实际速度并高亮。
  Widget _buildSpeedLabel() {
    final c = widget.controller;
    return ValueListenableBuilder<double>(
      valueListenable: c.playbackSpeed,
      builder: (context, speed, _) {
        return PopupMenuButton<double>(
          tooltip: '倍速',
          onSelected: c.setPlaybackSpeed,
          color: const Color(0xE61A1A1A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Style.radiusSm),
            side: const BorderSide(color: Colors.white12),
          ),
          itemBuilder: (context) => [
            for (final v in c.speedList)
              CheckedPopupMenuItem<double>(
                value: v,
                checked: v == speed,
                child: Text(
                  '${v.toStringAsFixed(1)}x',
                  style: TextStyle(
                    color: v == speed ? biliBlue : Colors.white70,
                    fontWeight: v == speed ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
          ],
          child: HoverContainer(
            borderRadius: 6.0,
            padding: const EdgeInsets.symmetric(horizontal: Style.sm, vertical: 4),
            hoverColor: Colors.white.withValues(alpha: 0.12),
            child: Text(
              speed == 1.0 ? '倍速' : '${speed.toStringAsFixed(1)}x',
              style: TextStyle(
                color: speed == 1.0 ? Colors.white70 : biliBlue,
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
