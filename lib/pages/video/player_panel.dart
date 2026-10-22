import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_miuix/miuix.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'package:winwin/theme/app_colors.dart';
import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/common/widgets/miuix_overlay_panel.dart';
import 'package:winwin/common/widgets/miuix_popup_menu.dart';
import 'package:winwin/common/widgets/progress_bar/audio_video_progress_bar.dart';
import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/core/input/escape_layer_registry.dart';
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
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/glass_contrast_widgets.dart';
import 'package:winwin/ui/components/hover_container.dart';
import 'package:winwin/utils/duration_utils.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/core/shell/app_dialogs.dart';
import 'package:winwin/common/widgets/app_dialog_shell.dart';
import 'package:winwin/ui/components/app_progress.dart';
import 'package:winwin/ui/components/app_tooltip.dart';
import 'package:winwin/ui/components/app_components.dart';
import 'package:winwin/ui/components/app_anchored_popup.dart';

/// Duration 没有 clamp 方法，手动实现（用于 seek 位置限制）。
Duration _clampDuration(Duration value, Duration min, Duration max) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

/// 音量条轨道粗细区间（实时随音量动态变化：0% 最细 → 100% 最粗）。
/// 上限沿用 `MiuixSliderDefaults.minHeight`(=28)，保证满音量观感与既有默认一致。
const double _kVolumeBarMinHeight = 14.0;
const double _kVolumeBarMaxHeight = 28.0;

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
    this.inAppFullscreen = false,
    this.onToggleFullscreen,
    this.onToggleInAppFullscreen,
    this.onEscape,
  });

  final WinWinPlayerController controller;
  final String? cover;
  final bool fullscreen;

  /// 是否处于网页全屏（铺满应用程序窗口，不修改系统原生窗口样式与最大化/还原属性）
  final bool inAppFullscreen;
  final VoidCallback? onToggleFullscreen;
  final VoidCallback? onToggleInAppFullscreen;

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
  /// 进度条悬浮预览状态（fraction, seconds）：独立局部驱动，杜绝滑动触发全局 setState 重绘风暴。
  final ValueNotifier<({double fraction, double seconds})?> _sliderHoverNotifier =
      ValueNotifier(null);
  bool _volumePopupOpen = false;
  bool _chapterPanelOpen = false;

  /// 二级设置弹层（音量 / 章节 / 弹幕设置 / 字幕设置 / 发弹幕 / 画质·音轨·
  /// 倍速菜单）的**打开计数**：>0 时控制条**不自动隐藏**（挂起隐藏计时），
  /// 归零（最后一个弹层关闭）后重置隐藏计时器，使控制条再停留一个完整周期。
  int _popupSuspend = 0;

  /// 音量按钮锚点：音量弹层据此定位到**触发按钮正上方**
  /// （B7-c6-4 反馈轮：此前弹层写死在左下角，与触发器脱钩）。
  final GlobalKey _volumeButtonKey = GlobalKey();

  /// 二级浮层的 Esc 登记注销回调（章节面板 / 音量弹层）。
  VoidCallback? _chapterEscUnregister;
  VoidCallback? _volumeEscUnregister;

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

  /// 「自动播放」关闭时的封面兜底（2026-10-22 对齐上游 PiliPlus `videoPlayer`）：
  /// 进入页面首次起播前，以视频封面整屏遮盖播放面（替代暂停首帧），
  /// 首次进入播放态后永久失效（见 [_onPlayingChanged]），
  /// 不影响起播后的正常视频流渲染。
  bool _coverFallbackActive = false;

  @override
  void initState() {
    super.initState();
    // 「自动播放」关闭（默认值）时启用封面兜底：与上游 PiliPlus 语义一致——
    // 未起播前展示封面而非暂停首帧（`if (!autoPlay) 封面覆盖 + 点击播放`）。
    _coverFallbackActive = !Pref.autoPlayEnable;
    widget.controller.playing.addListener(_onPlayingChanged);
    _showControlsTemporarily();
  }

  @override
  void dispose() {
    widget.controller.playing.removeListener(_onPlayingChanged);
    _hideTimer?.cancel();
    _feedbackTimer?.cancel();
    _dragFeedbackTimer?.cancel();
    _chapterEscUnregister?.call();
    _chapterEscUnregister = null;
    _volumeEscUnregister?.call();
    _volumeEscUnregister = null;
    _sliderHoverNotifier.dispose();
    _controlsVisible.dispose();
    _doubleTapFeedback.dispose();
    _longPressSpeedFeedback.dispose();
    _dragSeekFeedback.dispose();
    super.dispose();
  }

  /// 章节面板开关（唯一出口）：同步全局 Esc 登记表 + 控制条隐藏挂起。
  void _setChapterPanelOpen(bool open) {
    if (_chapterPanelOpen == open) return;
    setState(() => _chapterPanelOpen = open);
    if (open) {
      _beginPopupSuspend();
      _chapterEscUnregister = EscapeLayerRegistry.instance.register(() {
        if (!_chapterPanelOpen) return false;
        _setChapterPanelOpen(false);
        return true;
      });
    } else {
      _chapterEscUnregister?.call();
      _chapterEscUnregister = null;
      _endPopupSuspend();
    }
  }

  /// 音量弹层开关（唯一出口）：同步全局 Esc 登记表 + 控制条隐藏挂起。
  void _setVolumePopupOpen(bool open) {
    if (_volumePopupOpen == open) return;
    setState(() => _volumePopupOpen = open);
    if (open) {
      _beginPopupSuspend();
      _volumeEscUnregister = EscapeLayerRegistry.instance.register(() {
        if (!_volumePopupOpen) return false;
        _setVolumePopupOpen(false);
        return true;
      });
    } else {
      _volumeEscUnregister?.call();
      _volumeEscUnregister = null;
      _endPopupSuspend();
    }
  }

  /// 挂起控制条自动隐藏（弹层打开时调用）：计数 +1、取消隐藏计时并保持显示。
  void _beginPopupSuspend() {
    _popupSuspend++;
    _hideTimer?.cancel();
    _controlsVisible.value = true;
  }

  /// 恢复控制条自动隐藏（弹层关闭时调用）：计数归零后重置隐藏计时器
  /// （控制条当前可见才重置；已被隐藏时不再强行弹出）。
  void _endPopupSuspend() {
    if (_popupSuspend == 0) return;
    _popupSuspend--;
    if (_popupSuspend == 0 && _controlsVisible.value) {
      _resetHideTimer();
    }
  }

  /// 以"弹层挂起"包裹一个"打开即返回 Future、关闭才完成"的弹层调用。
  Future<void> _openSuspending(Future<void> Function() open) async {
    _beginPopupSuspend();
    try {
      await open();
    } finally {
      if (mounted) _endPopupSuspend();
    }
  }

  /// 控制条内 `MiuixPopupMenu`（画质 / 音轨 / 倍速）展开态变化 → 挂起/恢复
  /// 控制条自动隐藏（弹层锚定于控制条按钮，弹层开着时控制条必须保持外露）。
  void _onMenuOpenChanged(bool open) {
    if (open) {
      _beginPopupSuspend();
    } else {
      _endPopupSuspend();
    }
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
    showToast(context, '正在截图…', duration: const Duration(seconds: 1));
    final png = await c.screenshot();
    if (!mounted) return;
    if (png == null) {
      showToast(context, '截图失败', duration: const Duration(seconds: 1));
      return;
    }
    _showScreenshotPreview(png);
  }

  /// Phase 4.6：截图预览对话框 — 显示截图 + 保存按钮。
  void _showScreenshotPreview(Uint8List png) {
    showAppDialog<void>(
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
    // 锁定状态 / 播放中 / 未拖动进度 / 无任何设置弹层打开时才自动隐藏。
    if (!_locked &&
        c.playing.value &&
        !_draggingProgress &&
        _popupSuspend == 0) {
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
    // 其它设置弹层（弹幕/字幕设置、发弹幕、画质·音轨·倍速菜单）打开期间保持显示；
    // 音量弹层自身除外——鼠标移出播放器时仍需随控制条一并收起。
    if (_popupSuspend > 0 && !_volumePopupOpen) return;
    _controlsVisible.value = false;
    if (_volumePopupOpen) {
      _setVolumePopupOpen(false);
    }
  }

  // ── 交互 ──

  /// Esc 键与全屏浮层返回按钮的统一语义：
  /// 二级浮层（章节面板 / 音量弹层 / 弹幕样式…）优先关闭，本次不再级联；
  /// 否则交由页面处理（页面语义：优先退出显示器全屏 → 退出网页全屏 → 返回上一级）。
  void _handleEscape() {
    if (EscapeLayerRegistry.instance.closeTopmost()) return;
    widget.onEscape?.call();
  }

  void _onVideoTap() {
    widget.controller.playOrPause();
    _onPointerActivity();
  }

  /// 首次进入播放态 → 永久解除「自动播放关闭」的封面兜底。
  /// 只解除、不回盖：一旦起播，封面不再介入视频流（对齐上游 PiliPlus 语义）。
  void _onPlayingChanged() {
    if (!_coverFallbackActive) return;
    if (!widget.controller.playing.value) return;
    if (!mounted) return;
    setState(() => _coverFallbackActive = false);
  }

  void _toggleVolumePopup() {
    _setVolumePopupOpen(!_volumePopupOpen);
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
    return GStorage.video.get(
      VideoBoxKey.longPressSpeedDefault,
      defaultValue: 3.0,
    );
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
    final basePos = c.isSeeking ? c.seekPosition.value : c.position.value;
    final target = _clampDuration(
      basePos + Duration(seconds: delta),
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
    _hDragStart = widget.controller.isSeeking
        ? widget.controller.seekPosition.value
        : widget.controller.position.value;
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
      return const ColoredBox(color: AppColors.black);
    }
    return PlayerFocus(
      controller: c,
      enabled: !_locked,
      onSpeedChange: _onLongPressSpeedChange,
      onToggleFullscreen: widget.onToggleFullscreen,
      onToggleInAppFullscreen: widget.onToggleInAppFullscreen,
      onEscape: _handleEscape,
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
          color: AppColors.black,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final panelWidth = (constraints.maxWidth / 3).clamp(240.0, 560.0);
              return Stack(
                fit: StackFit.expand,
                children: [
                  _buildVideoSurface(c),
                  // 弹幕层（IgnorePointer，不拦截鼠标/点击；RepaintBoundary 隔离高频重绘）。
                  // 「自动播放关闭」的封面兜底期不渲染弹幕（避免静态封面叠动弹幕）；
                  // 首次起播后 [_coverFallbackActive] 置假，弹幕照常。
                  if (!_coverFallbackActive)
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: WinWinDanmaku(
                        key: ValueKey('danmaku_${c.cid}'),
                        controller: c,
                        fullscreen: widget.fullscreen || widget.inAppFullscreen,
                      ),
                    ),
                  ),
                  // Phase 4.4：字幕层（底部居中，IgnorePointer 不拦截手势；RepaintBoundary 隔离）。
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: IgnorePointer(child: _buildSubtitleLayer(c)),
                    ),
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
                  // Phase 4.3：锁定指示器（锁定时显示解锁按钮）。
                  if (_locked) _buildLockIndicator(),
                  if (!_locked)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: RepaintBoundary(
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
                    ),
                  // 全屏浮层返回键自 2026-10-21 起改由**壳层全局返回按钮**承担
                  // （页面经 BackButtonSpec 声明白色字形 + 退出全屏副作用），
                  // 本播放器不再自绘——消除「视频播放页未共享全局返回按钮」的最后一处。
                  // 常驻子树（不再 `if (_volumePopupOpen)` 条件挂载）：
                  // 展开/收起两段动画均由 `_volumePopupOpen` 驱动，
                  // 收起时由 `MiuixAnchoredPopup` 播完动画自行卸载为空。
                  _buildVolumePopup(),
                  // Phase 4.5：章节悬浮面板（覆盖在播放器控件之上的高层控件，外部视频区域点击 dismiss）。
                  _buildChapterPanel(panelWidth),
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
              child: GlassCapsule(
                blur: 16,
                padding: const EdgeInsets.symmetric(
                  horizontal: Style.lg,
                  vertical: Style.md,
                ),
                backgroundColor: AppColors.black.withValues(alpha: 0.55),
                borderRadius: Style.radiusSm,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ContrastIcon(
                      feedback.isForward
                          ? AppIcons.fastForward()
                          : AppIcons.fastRewind(),
                      color: AppColors.white,
                      size: 28,
                      shadows: ContrastStyle.boldGlyphShadows,
                    ),
                    const SizedBox(width: Style.xs),
                    ContrastText(
                      '${feedback.isForward ? '+' : '-'}${feedback.deltaSec}s',
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      shadows: ContrastStyle.boldGlyphShadows,
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
        return Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: GlassCapsule(
                blur: 16,
                padding: const EdgeInsets.symmetric(
                  horizontal: Style.lg,
                  vertical: Style.md,
                ),
                backgroundColor: AppColors.black.withValues(alpha: 0.55),
                borderRadius: Style.radiusSm,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ContrastIcon(
                      AppIcons.fastForward(),
                      color: biliPink,
                      size: 40,
                      shadows: ContrastStyle.boldGlyphShadows,
                    ),
                    const SizedBox(height: Style.xs),
                    const ContrastText(
                      '倍速播放中',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      shadows: ContrastStyle.glyphShadows,
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
              child: GlassCapsule(
                blur: 16,
                padding: const EdgeInsets.symmetric(
                  horizontal: Style.lg,
                  vertical: Style.md,
                ),
                backgroundColor: AppColors.black.withValues(alpha: 0.55),
                borderRadius: Style.radiusSm,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ContrastIcon(
                          isForward
                              ? AppIcons.fastForward()
                              : AppIcons.fastRewind(),
                          color: biliPink,
                          size: 20,
                          shadows: ContrastStyle.glyphShadows,
                        ),
                        const SizedBox(width: Style.xs),
                        ContrastText(
                          '${isForward ? '+' : ''}${feedback.deltaSec}s',
                          style: const TextStyle(
                            color: biliPink,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          shadows: ContrastStyle.boldGlyphShadows,
                        ),
                      ],
                    ),
                    const SizedBox(height: Style.xs),
                    ContrastText(
                      DurationUtils.formatDuration(feedback.target.inSeconds),
                      style: const TextStyle(color: AppColors.white, fontSize: 13),
                      shadows: ContrastStyle.glyphShadows,
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
      child: GlassCapsule(
        shape: BoxShape.circle,
        blur: 16,
        padding: const EdgeInsets.all(Style.xs),
        backgroundColor: AppColors.black.withValues(alpha: 0.45),
        child: MiuixIconButton(

          onPressed: _toggleLock,

          child: AppTooltip(message: '解锁控制条', child: ContrastIcon(
            AppIcons.lock(),
            color: AppColors.white,
            size: 32,
            shadows: ContrastStyle.boldGlyphShadows,
          )),
        ),
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
              return ValueListenableBuilder<bool>(
                valueListenable: c.startupGate,
                builder: (context, gateHeld, _) {
                  final hasFrame =
                      texId != null &&
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

                  // 封面作为「第一帧占位」常驻置顶（2026-09-29）：
                  // - 启动闸门 / 无首帧（加载、缓冲、弱网重试）期间不透明度 1 遮盖
                  //   （杜绝灰屏与 0 位闪帧）；无封面时黑底兜底；
                  // - 首帧就绪后 240ms 淡出完成过渡（替代硬切）。
                  // 2026-10-22「自动播放关闭」封面兜底：未起播前额外保持封面覆盖，
                  // 遮挡就绪后的暂停首帧（对齐上游 PiliPlus）；首次起播后该标志置假。
                  final coverVisible = gateHeld || !hasFrame || _coverFallbackActive;
                  final hasCover = coverUrl != null && coverUrl.isNotEmpty;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      videoWidget,
                      if (hasCover)
                        AnimatedOpacity(
                          opacity: coverVisible ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOut,
                          child: NetworkImgLayer(
                            src: coverUrl,
                            width: double.infinity,
                            height: double.infinity,
                            borderRadius: BorderRadius.zero,
                          ),
                        )
                      else if (coverVisible)
                        const ColoredBox(color: AppColors.black),
                    ],
                  );
                },
              );
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
                  child: AppProgressIndicator(color: biliPink),
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
          AppIcon(AppIcons.error(), color: AppColors.white70, size: 40),
          const SizedBox(height: Style.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.white70, fontSize: 14),
          ),
          const SizedBox(height: Style.md),
          MiuixTextButton('重试', onPressed: () =>
                widget.controller.load(start: widget.controller.position.value)),
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
              child: GlassCapsule(
                shape: BoxShape.circle,
                blur: 16,
                padding: const EdgeInsets.all(Style.md),
                backgroundColor: AppColors.black.withValues(alpha: 0.45),
                child: ContrastIcon(
                  isCompleted
                      ? AppIcons.replay()
                      : AppIcons.play(active: true),
                  color: AppColors.white,
                  size: 44,
                  shadows: ContrastStyle.boldGlyphShadows,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 底部控制条：纯渐进式压暗阴影延伸至进度条上方，无毛玻璃（0 GPU 滤镜开销），且无任何裁剪容器阻挡时间胶囊向上溢出。
  Widget _buildControlBar() {
    final c = widget.controller;
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            stops: [0.0, 0.55, 1.0],
            colors: [
              Color(0x73000000), // 底部轻柔渐进压暗 (~45% 黑)
              Color(0x28000000), // 中部微弱过渡暗色 (~16% 黑)
              AppColors.transparent, // 向上延伸至进度条上方平滑消隐至完全透明
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(
            top: 14.0, // 向上延伸至进度条上方，提供舒适的阴影渐变空间
            bottom: Style.xs,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 第一行：进度条（时间胶囊可向上自由悬浮溢出，无任何 ClipRect 截断）
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Style.sm),
                child: _buildProgressSlider(),
              ),
              // 第二行：控制按钮行（左右分区）
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Style.sm),
                child: Row(
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
                      icon: AppIcon(
                        AppIcons.sendDanmaku(),
                        shadows: ContrastStyle.glyphShadows,
                      ),
                      tooltip: '发弹幕',
                      onPressed: () => _openSuspending(
                        () => showSendDanmakuPanel(context, controller: c),
                      ),
                    ),
                    _iconButton(
                      icon: AppIcon(
                        AppIcons.danmakuTune(),
                        shadows: ContrastStyle.glyphShadows,
                      ),
                      tooltip: '弹幕设置',
                      onPressed: () => _openSuspending(
                        () => showDanmakuSettingsPanel(
                          context,
                          controller: c,
                          fullscreen:
                              widget.fullscreen || widget.inAppFullscreen,
                        ),
                      ),
                    ),
                    ValueListenableBuilder<double>(
                      valueListenable: c.volume,
                      builder: (context, vol, _) {
                        final Widget volIcon = AppIcon(
                          vol <= 0
                              ? AppIcons.volumeOff()
                              : (vol > 100
                                    ? AppIcons.volumeUp()
                                    : AppIcons.volumeDown()),
                          shadows: ContrastStyle.glyphShadows,
                        );
                        return KeyedSubtree(
                          key: _volumeButtonKey,
                          child: _iconButton(
                            icon: volIcon,
                            tooltip: '音量',
                            color: _volumePopupOpen ? biliBlue : null,
                            onPressed: _toggleVolumePopup,
                          ),
                        );
                      },
                    ),
                    // 「全屏显示锁定按钮」：全屏时按设置显隐（非全屏常显）。
                    if (!widget.fullscreen || Pref.showFsLockBtn)
                      _iconButton(
                        icon: AppIcon(
                          AppIcons.lockOutline(),
                          shadows: ContrastStyle.glyphShadows,
                        ),
                        tooltip: '锁定控制条',
                        onPressed: _toggleLock,
                      ),
                    // 「全屏显示截图按钮」：开启时在全屏显示截图按钮。
                    if (widget.fullscreen && Pref.showFsScreenshotBtn)
                      _iconButton(
                        icon: AppIcon(
                          AppIcons.screenshotButton(),
                          shadows: ContrastStyle.glyphShadows,
                        ),
                        tooltip: '截图',
                        onPressed: () => _takeScreenshot(),
                      ),
                    if (!widget.fullscreen)
                      _iconButton(
                        icon: AppIcon(
                          AppIcons.pip(),
                          shadows: ContrastStyle.glyphShadows,
                        ),
                        tooltip: '画中画',
                        onPressed: () => DesktopPipController.instance.togglePip(),
                      ),
                    if (!widget.fullscreen && widget.onToggleInAppFullscreen != null)
                      _iconButton(
                        icon: AppIcon(
                          AppIcons.inAppFullscreen(
                            active: widget.inAppFullscreen,
                          ),
                          shadows: ContrastStyle.glyphShadows,
                        ),
                        tooltip: widget.inAppFullscreen ? '退出网页全屏' : '网页全屏',
                        color: widget.inAppFullscreen ? biliBlue : null,
                        onPressed: widget.onToggleInAppFullscreen!,
                      ),
                    if (widget.onToggleFullscreen != null)
                      _iconButton(
                        icon: AppIcon(
                          AppIcons.fullscreen(active: widget.fullscreen),
                          shadows: ContrastStyle.glyphShadows,
                        ),
                        tooltip: widget.fullscreen ? '退出全屏' : '全屏',
                        color: widget.fullscreen ? biliBlue : null,
                        onPressed: widget.onToggleFullscreen!,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 播放/暂停按钮：统一为 20px 规格图标，具备温和柔白与 hover 提亮动效。
  Widget _buildPlayPauseButton() {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: Listenable.merge([c.playing, c.completed]),
      builder: (context, _) {
        final isPlaying = c.playing.value;
        final isCompleted = c.completed.value;
        final icon = AppIcon(
          isPlaying
              ? AppIcons.pause(active: true)
              : (isCompleted
                    ? AppIcons.replay()
                    : AppIcons.play(active: true)),
          shadows: ContrastStyle.glyphShadows,
        );
        return _iconButton(
          icon: icon,
          tooltip: isCompleted ? '重新播放' : (isPlaying ? '暂停' : '播放'),
          onPressed: c.playOrPause,
          size: 20.0,
        );
      },
    );
  }

  /// 控制条图标按钮统一风格：默认 18px 规范图标 + 30px 点击区域 + 温和白亮度 + hover 平滑提亮。
  Widget _iconButton({
    required Widget icon,
    required VoidCallback? onPressed,
    String? tooltip,
    Color? color,
    double size = 18.0,
  }) {
    return _PlayerBarIconButton(
      icon: icon,
      onPressed: onPressed,
      tooltip: tooltip,
      color: color,
      size: size,
    );
  }

  Widget _buildTimeText() {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: Listenable.merge([
        c.position,
        c.seekPosition,
        c.duration,
        c.viewPointsNotifier,
        _controlsVisible,
      ]),
      builder: (context, _) {
        if (!_controlsVisible.value) {
          return const SizedBox(width: 80, height: 16);
        }
        final pos = DurationUtils.formatDuration(c.currentProgress.inSeconds);
        final dur = DurationUtils.formatDuration(c.duration.value.inSeconds);
        final curChapter = c.currentChapter();
        // B 站风格：当前时间纯白，总时长降饱和，配合高对比度多向阴影。
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: pos,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 12,
                      shadows: ContrastStyle.glyphShadows,
                    ),
                  ),
                  TextSpan(
                    text: ' / $dur',
                    style: const TextStyle(
                      color: AppColors.white70,
                      fontSize: 12,
                      shadows: ContrastStyle.glyphShadows,
                    ),
                  ),
                ],
              ),
            ),
            if (curChapter != null && curChapter.title.isNotEmpty) ...[
              const SizedBox(width: Style.xs),
              GlassCapsule(
                borderRadius: 4.0,
                blur: 8.0,
                backgroundColor: _chapterPanelOpen
                    ? biliBlue.withValues(alpha: 0.25)
                    : AppColors.black.withValues(alpha: 0.35),
                padding: EdgeInsets.zero,
                child: HoverContainer(
                  onTap: () {
                    _setChapterPanelOpen(!_chapterPanelOpen);
                    _onPointerActivity();
                  },
                  borderRadius: 4.0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  color: AppColors.transparent,
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
                                : AppColors.white.withValues(alpha: 0.88),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            shadows: ContrastStyle.glyphShadows,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 2),
                      ContrastIcon(AppIcons.chevronForward(),
                        size: 14,
                        color: _chapterPanelOpen ? biliBlue : AppColors.white54,
                        shadows: ContrastStyle.glyphShadows,
                      ),
                    ],
                  ),
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
        c.buffered,
        c.seekPosition,
        c.viewPointsNotifier,
        _controlsVisible,
      ]),
      builder: (context, _) {
        if (!_controlsVisible.value && !_draggingProgress) {
          return const SizedBox(height: 18);
        }
        final durMs = c.duration.value.inMilliseconds;
        final posMs = c.currentProgress.inMilliseconds;
        final bufMs = c.buffered.value.inMilliseconds;
        final maxSec = durMs > 0 ? durMs / 1000.0 : 1.0;
        final chapters = c.viewPoints;

        return LayoutBuilder(
          builder: (context, constraints) {
            final sliderWidth = constraints.maxWidth;

            return Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // 1. 浮动时间节点与章节胶囊（Tooltip）— 局部 ValueListenableBuilder 独立渲染，带 RepaintBoundary
                ValueListenableBuilder<({double fraction, double seconds})?>(
                  valueListenable: _sliderHoverNotifier,
                  builder: (context, hover, _) {
                    final previewSec = _draggingProgress
                        ? _dragSeconds
                        : hover?.seconds;
                    final showTooltip = previewSec != null && durMs > 0;
                    if (!showTooltip) return const SizedBox.shrink();

                    final previewChapter = c.currentChapter(previewSec);
                    final targetFraction = _draggingProgress
                        ? (_dragSeconds / maxSec).clamp(0.0, 1.0)
                        : (hover?.fraction ??
                            (durMs > 0
                                ? (posMs / durMs).clamp(0.0, 1.0)
                                : 0.0));
                    final tooltipLeft =
                        (targetFraction * (sliderWidth - 24)).clamp(
                      8.0,
                      (sliderWidth - 180).clamp(8.0, double.infinity),
                    );

                    return Positioned(
                      bottom: 28,
                      left: tooltipLeft,
                      child: RepaintBoundary(
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
                                color: AppColors.white.withValues(alpha: 0.15),
                                width: 0.5,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: AppColors.black54,
                                  blurRadius: 6,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  DurationUtils.formatDuration(
                                    previewSec.toInt(),
                                  ),
                                  style: const TextStyle(
                                    color: AppColors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (previewChapter != null &&
                                    previewChapter.title.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 160,
                                    ),
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
                    );
                  },
                ),
                // 2. 进度条主体与手势检测 — 零全局 setState，局部驱动
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onHover: (e) {
                    final localX = (e.localPosition.dx - 12).clamp(
                      0.0,
                      sliderWidth - 24,
                    );
                    final fraction = (sliderWidth > 24)
                        ? (localX / (sliderWidth - 24)).clamp(0.0, 1.0)
                        : 0.0;
                    // 局部更新：彻底移除全局 setState，杜绝父级全量 Rebuild 与毛玻璃高频重绘
                    _sliderHoverNotifier.value = (
                      fraction: fraction,
                      seconds: fraction * maxSec,
                    );
                    _onPointerActivity();
                  },
                  onExit: (_) {
                    _sliderHoverNotifier.value = null;
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: RepaintBoundary(
                      child: ProgressBar(
                        progress: _draggingProgress
                            ? (_dragSeconds * 1000).round()
                            : posMs,
                        buffered: bufMs,
                        total: durMs,
                        barHeight: 3.5,
                        thumbRadius: 6.0,
                        thumbGlowRadius: 16.0,
                        baseBarColor: AppColors.white24,
                        bufferedBarColor: AppColors.white38,
                        progressBarColor: biliBlue,
                        thumbColor: biliBlue,
                        thumbGlowColor: const Color(0x3300AEEC),
                        onDragStart: (details) {
                          setState(() {
                            _draggingProgress = true;
                            _dragSeconds = details.seconds.toDouble();
                          });
                          _sliderHoverNotifier.value = (
                            fraction:
                                (details.seconds / maxSec).clamp(0.0, 1.0),
                            seconds: details.seconds.toDouble(),
                          );
                          c.onSeekStart(details.milliseconds);
                          _onPointerActivity();
                        },
                        onDragUpdate: (details) {
                          _dragSeconds = details.seconds.toDouble();
                          _sliderHoverNotifier.value = (
                            fraction:
                                (details.seconds / maxSec).clamp(0.0, 1.0),
                            seconds: details.seconds.toDouble(),
                          );
                          c.onSeekUpdate(details.milliseconds);
                          _onPointerActivity();
                        },
                        onDragEnd: () {
                          _onPointerActivity();
                        },
                        onSeek: (targetMs) {
                          setState(() {
                            _draggingProgress = false;
                            _dragSeconds = targetMs / 1000.0;
                          });
                          _sliderHoverNotifier.value = null;
                          c.seek(Duration(milliseconds: targetMs));
                          c.onSeekEnd();
                          _onPointerActivity();
                        },
                      ),
                    ),
                  ),
                ),
                // Phase 4.5：章节标记（view_points）— 在进度条上显示竖线标记。
                if (chapters.isNotEmpty && durMs > 0)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: CustomPaint(
                          painter: _ChapterMarkerPainter(
                            chapters: chapters,
                            durationSec: maxSec,
                            color: AppColors.white70,
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
        // 阶段5d-L1：M3 冻结分支已移除，弹层壳为唯一实现。
        return MiuixPopupMenu(
            entries: [
              MiuixDropdownEntry(
                items: [
                  for (int i = 0; i < labels.length; i++)
                    MiuixDropdownItem(
                      text: labels[i],
                      selected: i == current,
                      onClick: () => c.switchQuality(i),
                    ),
                ],
              ),
            ],
            title: '画质',
            itemTextStyle: const TextStyle(fontSize: 12),
            onOpenChanged: _onMenuOpenChanged,
            child: AppTooltip(
              message: '画质',
              child: HoverContainer(
                borderRadius: 6.0,
                padding: const EdgeInsets.symmetric(
                  horizontal: Style.sm,
                  vertical: 6,
                ),
                hoverColor: AppColors.white.withValues(alpha: 0.12),
                child: ContrastText(
                  (current >= 0 && current < labels.length)
                      ? labels[current]
                      : '画质',
                  style: TextStyle(
                    color: AppColors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                  ),
                  shadows: ContrastStyle.glyphShadows,
                ),
              ),
            ),
          );
      },
    );
  }

  /// BiliPai 风格弹幕开关圆角 chip：
  /// 统一 ~30px 高度规范，图标放大至 16.5px，温和白与高对比度毛玻璃胶囊底衬。
  Widget _buildDanmakuChip() {
    final enabled = Pref.enableShowDanmaku;
    return GlassCapsule(
      borderRadius: Style.radiusFull,
      blur: 8,
      padding: EdgeInsets.zero,
      backgroundColor: enabled
          ? biliBlue.withValues(alpha: 0.28)
          : AppColors.black.withValues(alpha: 0.35),
      borderColor: enabled
          ? biliBlue.withValues(alpha: 0.45)
          : AppColors.white.withValues(alpha: 0.15),
      child: HoverContainer(
        onTap: _toggleDanmaku,
        borderRadius: Style.radiusFull,
        padding: const EdgeInsets.symmetric(
          horizontal: 9,
          vertical: 5,
        ),
        hoverColor: AppColors.white.withValues(alpha: 0.12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ContrastIcon(
              AppIcons.danmaku(active: enabled),
              size: 16.5,
              color: enabled
                  ? const Color(0xFF00AEEC)
                  : AppColors.white.withValues(alpha: 0.85),
              shadows: ContrastStyle.glyphShadows,
            ),
            const SizedBox(width: Style.xs),
            ContrastText(
              enabled ? '开' : '关',
              style: TextStyle(
                color: enabled
                    ? const Color(0xFF00AEEC)
                    : AppColors.white.withValues(alpha: 0.85),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              shadows: ContrastStyle.glyphShadows,
            ),
          ],
        ),
      ),
    );
  }

  /// BiliPai 风格字幕 chip：统一 ~30px 高度规范与 16.5px 图标，有字幕时高亮，毛玻璃胶囊底衬。
  Widget _buildSubtitleChip() {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: c.subtitle,
      builder: (context, _) {
        final isActive = c.subtitle.current != null;
        return GlassCapsule(
          borderRadius: Style.radiusFull,
          blur: 8,
          padding: EdgeInsets.zero,
          backgroundColor: isActive
              ? biliBlue.withValues(alpha: 0.28)
              : AppColors.black.withValues(alpha: 0.35),
          borderColor: isActive
              ? biliBlue.withValues(alpha: 0.45)
              : AppColors.white.withValues(alpha: 0.15),
          child: HoverContainer(
            onTap: () => _openSuspending(
              () => showSubtitleSettingsPanel(
                context,
                controller: c,
                fullscreen: widget.fullscreen || widget.inAppFullscreen,
              ),
            ),
            borderRadius: Style.radiusFull,
            padding: const EdgeInsets.symmetric(
              horizontal: 9,
              vertical: 5,
            ),
            hoverColor: AppColors.white.withValues(alpha: 0.12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ContrastIcon(
                  AppIcons.subtitle(active: isActive),
                  size: 16.5,
                  color: isActive
                      ? const Color(0xFF00AEEC)
                      : AppColors.white.withValues(alpha: 0.85),
                  shadows: ContrastStyle.glyphShadows,
                ),
                const SizedBox(width: Style.xs),
                ContrastText(
                  '字幕',
                  style: TextStyle(
                    color: isActive
                        ? const Color(0xFF00AEEC)
                        : AppColors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  shadows: ContrastStyle.glyphShadows,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// BiliPai 风格音频编码标签：显示当前音轨编码（如 "AAC"），点击打开音轨与音频增强菜单。
  Widget _buildAudioCodecLabel() {
    final c = widget.controller;
    return ValueListenableBuilder<bool>(
      valueListenable: c.ready,
      builder: (context, ready, _) {
        if (!ready) return const SizedBox.shrink();
        final codec = c.audioCodecLabel;
        if (codec == null) return const SizedBox.shrink();
        final tracks = c.audioTracks;
        final active = c.activeAudioTrackIndices;
        final activeIndex = active.isNotEmpty ? active.first : -1;
        final currentNorm = Pref.audioNormalization;
        // 阶段5d-L1：M3 冻结分支已移除，弹层壳为唯一实现。
        return MiuixPopupMenu(
            entries: [
              if (tracks.length > 1)
                MiuixDropdownEntry(
                  items: [
                    for (final t in tracks)
                      MiuixDropdownItem(
                        text: t.title,
                        selected: t.index == activeIndex,
                        onClick: () => c.switchAudioTrack(t.index),
                      ),
                  ],
                ),
              MiuixDropdownEntry(
                items: [
                  MiuixDropdownItem(
                    text: '智能响度均衡 (loudnorm)',
                    selected: currentNorm == '2',
                    onClick: () {
                      c.setAudioNormalize('2');
                      setState(() {});
                    },
                  ),
                  MiuixDropdownItem(
                    text: '动态压缩 (dynaudnorm)',
                    selected: currentNorm == '1',
                    onClick: () {
                      c.setAudioNormalize('1');
                      setState(() {});
                    },
                  ),
                  MiuixDropdownItem(
                    text: '禁用',
                    selected: currentNorm == '0',
                    onClick: () {
                      c.setAudioNormalize('0');
                      setState(() {});
                    },
                  ),
                ],
              ),
            ],
            title: '音频设置',
            itemTextStyle: const TextStyle(fontSize: 12),
            onOpenChanged: _onMenuOpenChanged,
            child: AppTooltip(
              message: '音频设置',
              child: HoverContainer(
                borderRadius: 6.0,
                padding: const EdgeInsets.symmetric(
                  horizontal: Style.sm,
                  vertical: 6,
                ),
                hoverColor: AppColors.white.withValues(alpha: 0.12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ContrastText(
                      codec,
                      style: TextStyle(
                        color: AppColors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                      ),
                      shadows: ContrastStyle.glyphShadows,
                    ),
                    if (c.audioNormalizeEnabled) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: biliPink.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const ContrastText(
                          '均衡',
                          style: TextStyle(color: biliPink, fontSize: 10),
                          shadows: ContrastStyle.glyphShadows,
                        ),
                      ),
                    ],
                  ],
                ),
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
        final isLarge = widget.fullscreen || widget.inAppFullscreen;
        final scale = isLarge
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
              bottom: padB + (isLarge ? 60 : 48),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Style.sm,
                vertical: Style.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.black.withValues(alpha: bgOpacity),
                borderRadius: BorderRadius.circular(Style.radiusXs),
              ),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 16 * scale,
                  height: 1.4,
                  fontWeight: fontWeight,
                  shadows: strokeWidth > 0
                      ? [
                          Shadow(
                            offset: const Offset(0, 1),
                            blurRadius: strokeWidth,
                            color: AppColors.black,
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

  /// 章节列表按钮（BiliPai 风格圆角 chip）：统一 ~30px 高度规范与 16.5px 图标，有章节时显示，毛玻璃胶囊底衬。
  Widget _buildChapterButton() {
    final c = widget.controller;
    return ValueListenableBuilder<List<ViewPoint>>(
      valueListenable: c.viewPointsNotifier,
      builder: (context, chapters, _) {
        if (chapters.isEmpty) return const SizedBox.shrink();
        final isOpen = _chapterPanelOpen;
        return GlassCapsule(
          borderRadius: Style.radiusFull,
          blur: 8,
          padding: EdgeInsets.zero,
          backgroundColor: isOpen
              ? biliBlue.withValues(alpha: 0.28)
              : AppColors.black.withValues(alpha: 0.35),
          borderColor: isOpen
              ? biliBlue.withValues(alpha: 0.45)
              : AppColors.white.withValues(alpha: 0.15),
          child: HoverContainer(
            onTap: () {
              _setChapterPanelOpen(!_chapterPanelOpen);
              _onPointerActivity();
            },
            borderRadius: Style.radiusFull,
            padding: const EdgeInsets.symmetric(
              horizontal: 9,
              vertical: 5,
            ),
            hoverColor: AppColors.white.withValues(alpha: 0.12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ContrastIcon(
                  AppIcons.chapter(active: isOpen),
                  size: 16.5,
                  color: isOpen
                      ? const Color(0xFF00AEEC)
                      : AppColors.white.withValues(alpha: 0.85),
                  shadows: ContrastStyle.glyphShadows,
                ),
                const SizedBox(width: Style.xs),
                ContrastText(
                  '章节 (${chapters.length})',
                  style: TextStyle(
                    color: isOpen
                        ? const Color(0xFF00AEEC)
                        : AppColors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  shadows: ContrastStyle.glyphShadows,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 章节悬浮面板 — 覆盖在播放器控件之上的高层控件，覆盖右侧 1/3 区域，点击外部视频区域可 Dismiss 关闭。
  Widget _buildChapterPanel(double panelWidth) {
    final c = widget.controller;
    return ValueListenableBuilder<List<ViewPoint>>(
      valueListenable: c.viewPointsNotifier,
      builder: (context, chapters, _) {
        if (chapters.isEmpty) return const SizedBox.shrink();
        return Positioned.fill(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. 面板外区域 Dismiss 遮罩（点击面板以外的任意视频/底栏区域 dismiss 关闭章节面板）
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_chapterPanelOpen,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      _setChapterPanelOpen(false);
                      _onPointerActivity();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      color: _chapterPanelOpen
                          ? AppColors.black.withValues(alpha: 0.25)
                          : AppColors.transparent,
                    ),
                  ),
                ),
              ),
              // 2. 右侧滑出的章节悬浮面板本体（高层控件）
              AnimatedPositioned(
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
                      onTap: () {}, // 吸收点击，防止触发外部遮罩 dismiss
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(Style.radiusMd),
                          bottomLeft: Radius.circular(Style.radiusMd),
                        ),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xF2141414), // 黑色高质感毛玻璃半透明
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(Style.radiusMd),
                                bottomLeft: Radius.circular(Style.radiusMd),
                              ),
                              border: Border(
                                left: BorderSide(
                                  color: AppColors.white.withValues(alpha: 0.15),
                                  width: 0.8,
                                ),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.black.withValues(alpha: 0.5),
                                  blurRadius: 20,
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
                                        color: AppColors.white.withValues(
                                          alpha: 0.08,
                                        ),
                                        width: 0.5,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      AppIcon(
                                        AppIcons.chapter(),
                                        color: AppColors.white,
                                        size: appRowIconSize(context, 15),
                                      ),
                                      const SizedBox(width: Style.sm),
                                      Text(
                                        '章节 (${chapters.length})',
                                        style: const TextStyle(
                                          color: AppColors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const Spacer(),
                                      HoverContainer(
                                        onTap: () {
                                          _setChapterPanelOpen(false);
                                        },
                                        borderRadius: 6.0,
                                        padding: const EdgeInsets.all(4),
                                        hoverColor: AppColors.white.withValues(
                                          alpha: 0.12,
                                        ),
                                        child: AppIcon(
                                          AppIcons.clear(),
                                          color: AppColors.white70,
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
                                      final currentSec = c
                                          .position
                                          .value
                                          .inSeconds
                                          .toDouble();
                                      return ListView.builder(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: Style.xs,
                                          horizontal: Style.xs,
                                        ),
                                        itemCount: chapters.length,
                                        itemBuilder: (context, index) {
                                          final vp = chapters[index];
                                          final isCurrent = vp.contains(
                                            currentSec,
                                          );
                                          final fromStr =
                                              DurationUtils.formatDuration(
                                                vp.from.toInt(),
                                              );
                                          final toStr =
                                              DurationUtils.formatDuration(
                                                vp.to.toInt(),
                                              );
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 2,
                                            ),
                                            child: HoverContainer(
                                              onTap: () {
                                                c.seek(
                                                  Duration(
                                                    seconds: vp.from.round(),
                                                  ),
                                                );
                                              },
                                              borderRadius: Style.radiusSm,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: Style.sm,
                                                    vertical: Style.sm,
                                                  ),
                                              color: isCurrent
                                                  ? biliBlue.withValues(
                                                      alpha: 0.16,
                                                    )
                                                  : AppColors.transparent,
                                              hoverColor: isCurrent
                                                  ? biliBlue.withValues(
                                                      alpha: 0.24,
                                                    )
                                                  : AppColors.white.withValues(
                                                      alpha: 0.08,
                                                    ),
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.center,
                                                children: [
                                                  // 播放状态指示或序号
                                                  SizedBox(
                                                    width: 22,
                                                    child: isCurrent
                                                        ? AppIcon(
                                                            AppIcons.play(
                                                              active: true,
                                                            ),
                                                            color: biliBlue,
                                                            size: 18,
                                                          )
                                                        : Text(
                                                            '${index + 1}'
                                                                .padLeft(
                                                                  2,
                                                                  '0',
                                                                ),
                                                            style: TextStyle(
                                                              color: AppColors
                                                                  .white
                                                                  .withValues(
                                                                    alpha: 0.35,
                                                                  ),
                                                              fontSize: 12,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                            ),
                                                          ),
                                                  ),
                                                  if (vp.imgUrl != null &&
                                                      vp
                                                          .imgUrl!
                                                          .isNotEmpty) ...[
                                                    ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            4,
                                                          ),
                                                      child: NetworkImgLayer(
                                                        src: vp.imgUrl,
                                                        width: 44,
                                                        height: 25,
                                                      ),
                                                    ),
                                                    const SizedBox(
                                                      width: Style.xs,
                                                    ),
                                                  ],
                                                  // 时间节点范围
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 6,
                                                          vertical: 2,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: isCurrent
                                                          ? biliBlue.withValues(
                                                              alpha: 0.22,
                                                            )
                                                          : AppColors.white
                                                                .withValues(
                                                                  alpha: 0.06,
                                                                ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            4,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      '$fromStr - $toStr',
                                                      style: TextStyle(
                                                        color: isCurrent
                                                            ? biliBlue
                                                            : AppColors.white
                                                                  .withValues(
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
                                                  const SizedBox(
                                                    width: Style.sm,
                                                  ),
                                                  // 章节标题
                                                  Expanded(
                                                    child: Text(
                                                      vp.title.isEmpty
                                                          ? '章节 ${index + 1}'
                                                          : vp.title,
                                                      style: TextStyle(
                                                        color: isCurrent
                                                            ? AppColors.white
                                                            : AppColors.white
                                                                  .withValues(
                                                                    alpha: 0.9,
                                                                  ),
                                                        fontSize: 13,
                                                        fontWeight: isCurrent
                                                            ? FontWeight.w600
                                                            : FontWeight.normal,
                                                      ),
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
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
                  ),
                ),
              ),
            ],
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
        // 阶段5d-L1：M3 冻结分支已移除，弹层壳为唯一实现。
        return MiuixPopupMenu(
            entries: [
              MiuixDropdownEntry(
                items: [
                  for (final v in c.speedList)
                    MiuixDropdownItem(
                      text: '${v.toStringAsFixed(1)}x',
                      selected: v == speed,
                      onClick: () => c.setPlaybackSpeed(v),
                    ),
                ],
              ),
            ],
            title: '倍速',
            itemTextStyle: const TextStyle(fontSize: 12),
            onOpenChanged: _onMenuOpenChanged,
            child: AppTooltip(
              message: '倍速',
              child: HoverContainer(
                borderRadius: 6.0,
                padding: const EdgeInsets.symmetric(
                  horizontal: Style.sm,
                  vertical: 6,
                ),
                hoverColor: AppColors.white.withValues(alpha: 0.12),
                child: ContrastText(
                  speed == 1.0 ? '倍速' : '${speed.toStringAsFixed(1)}x',
                  style: TextStyle(
                    color: speed == 1.0
                        ? AppColors.white.withValues(alpha: 0.85)
                        : const Color(0xFF00AEEC),
                    fontSize: 12,
                    fontWeight:
                        speed == 1.0 ? FontWeight.normal : FontWeight.bold,
                  ),
                  shadows: ContrastStyle.glyphShadows,
                ),
              ),
            ),
          );
      },
    );
  }

  /// 取音量按钮在本面板坐标系中的矩形（音量弹层锚点）。
  Rect? _volumeAnchorRect() {
    final buttonContext = _volumeButtonKey.currentContext;
    if (buttonContext == null) return null;
    return anchorRectOf(buttonContext, ancestorContext: context);
  }

  /// 音量弹出 Slider。
  ///
  /// B7-c6-4 反馈轮：由**写死左下角**改为**锚定音量按钮正上方**。
  /// 本轮（2026-10-21）：外观改用**播放器统一抽象的弹层样式**
  /// （`MiuixOverlayPanel` 毛玻璃面板——与投币 / 表情 / 弹幕样式面板同源），
  /// 并经 `MiuixAnchoredPopup` 补齐**对角线展开 / 收起**两段动画；强调色取
  /// **主题色**（`tokens.colors.primary`），越过 100% 的增益态改用**深橙**
  /// `AppColors.orange700`（原亮黄 `amberAccent` 在浅色毛玻璃面板上过亮刺眼、
  /// 对比不足，实机反馈"看不清"）。音量读数（含 `(增益)` 后缀）并入**标题栏
  /// 右端**，内容区只留滑条。音量条轨道粗细随音量**实时动态变化**：越小越细、
  /// 越大越粗。
  Widget _buildVolumePopup() {
    final c = widget.controller;
    final anchor = _volumeAnchorRect();
    // 触发按钮尚未布局（极端首帧）时不渲染，避免弹层落到屏幕角落；
    // 收起动画期间锚点仍在，故关闭过程仍能正常渲染。
    if (anchor == null) return const SizedBox.shrink();
    final tokens = AppThemeHost.of(context);
    // 增益态的强调色：深橙 orange700。原亮黄 amberAccent(#FFD740) 压在浅色
    // 毛玻璃面板上过亮刺眼、明度又接近底衬导致对比不足（实机"看不清"）。
    const gainColor = AppColors.orange700;
    // 面板总宽 = 内容 232 + 内边距 16×2；外层定宽，避免 MiuixOverlayPanel
    // 标题行（MainAxisSize.max）在锚定浮层的 loose 约束下被拉成整页宽。
    return MiuixAnchoredPopup(
      visible: _volumePopupOpen,
      anchor: anchor,
      alignment: Alignment.bottomRight,
      child: SizedBox(
        width: 264,
        child: MiuixOverlayPanel(
          title: '音量',
          // 音量读数（`N%` / `N% (增益)`）并入**标题栏右端**：内容区只留滑条，
          // 排版更稳，也不再需要右侧定宽标签槽来防抖（增益后缀不再改变宽度）。
          trailing: ValueListenableBuilder<double>(
            valueListenable: c.volume,
            builder: (context, vol, _) {
              final rounded = vol.round();
              final gain = rounded > 100;
              return Text(
                gain ? '$rounded% (增益)' : '$rounded%',
                maxLines: 1,
                style: TextStyle(
                  color: gain ? gainColor : tokens.colors.onSurface,
                  fontWeight: gain ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                ),
              );
            },
          ),
          icon: ValueListenableBuilder<double>(
            valueListenable: c.volume,
            builder: (context, vol, _) {
              final gain = vol > 100;
              return AppIcon(
                vol <= 0
                    ? AppIcons.volumeOff()
                    : (gain ? AppIcons.volumeUp() : AppIcons.volumeDown()),
                size: 16,
                color: gain ? gainColor : tokens.colors.primary,
              );
            },
          ),
          child: SizedBox(
            width: 232,
            child: ValueListenableBuilder<double>(
              valueListenable: c.volume,
              builder: (context, vol, _) {
                final gain = vol > 100;
                final activeColor = gain ? gainColor : tokens.colors.primary;
                final base = MiuixSliderDefaults.sliderColors(context);
                // 动态粗细：0% → 14（最细）线性增长到 100% → 28（最粗）。
                final barHeight = lerpDouble(
                  _kVolumeBarMinHeight,
                  _kVolumeBarMaxHeight,
                  (vol / 100).clamp(0.0, 1.0),
                )!;
                return MiuixSlider(
                  value: vol.clamp(0.0, Pref.maxVolume).toDouble(),
                  min: 0,
                  max: Pref.maxVolume,
                  height: barHeight,
                  // 100% 处增加一个吸附关键点：拖动/点击时磁吸到 100%
                  //（常态音量基准，100% 以上为增益）。magnetThreshold
                  // 放宽到 3%（≈±6）更易吸附。
                  keyPoints: Pref.maxVolume > 100 ? const [100.0] : null,
                  showKeyPoints: Pref.maxVolume > 100,
                  magnetThreshold: 0.03,
                  colors: MiuixSliderColors(
                    foregroundColor: activeColor,
                    disabledForegroundColor: activeColor,
                    // 底轨沿用主题默认（随明暗/主题自适应），不再硬编码
                    // 半透明白（那是旧"黑色玻璃胶囊"底衬的遗留口径）。
                    backgroundColor: base.backgroundColor,
                    disabledBackgroundColor: base.disabledBackgroundColor,
                    thumbColor: activeColor,
                    disabledThumbColor: activeColor,
                    keyPointColor: activeColor,
                    keyPointForegroundColor: activeColor,
                  ),
                  onValueChanged: c.setVolume,
                );
              },
            ),
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
        showToast(context, '保存失败：$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialogShell(
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
                  Text('截图预览', style: AppThemeHost.of(context).text.titleMedium),
                  const Spacer(),
                  MiuixIconButton(

                    onPressed: () => Navigator.of(context).pop(),

                    child: AppIcon(AppIcons.clear()),
                  ),
                ],
              ),
              const MiuixHorizontalDivider(),
              const SizedBox(height: Style.sm),
              Flexible(child: Image.memory(widget.png, fit: BoxFit.contain)),
              const SizedBox(height: Style.sm),
              if (_savedPath != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: Style.xs),
                  child: Text(
                    '已保存：$_savedPath',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppThemeHost.of(context).colors.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  MiuixTextButton('关闭', onPressed: () => Navigator.of(context).pop()),
                  const SizedBox(width: Style.sm),
                  AppPrimaryButton(onPressed: _saving ? null : _save, child: Row(mainAxisSize: MainAxisSize.min, children: [_saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: AppProgressIndicator(strokeWidth: 2),
                          )
                        : AppIcon(AppIcons.download(), size: appRowIconSizeInherited(context)), const SizedBox(width: 6), Text(_savedPath != null ? '已保存' : '保存')])),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 控制条专用图标按钮：统一尺寸、温和白默认亮度、hover 平滑提亮与高对比度阴影。
class _PlayerBarIconButton extends StatefulWidget {
  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final double size;

  const _PlayerBarIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
    this.size = 18.0,
  });

  @override
  State<_PlayerBarIconButton> createState() => _PlayerBarIconButtonState();
}

class _PlayerBarIconButtonState extends State<_PlayerBarIconButton> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    // 默认温和白 (~82% alpha)，避免纯白在深色控制条上刺目；hover 时提亮至纯白 (100%)
    final effectiveColor = widget.color ??
        (_isHovering ? AppColors.white : AppColors.white.withValues(alpha: 0.82));

    final child = MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      cursor: widget.onPressed != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onPressed,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _isHovering
                ? AppColors.white.withValues(alpha: 0.12)
                : AppColors.transparent,
            borderRadius: BorderRadius.circular(6.0),
          ),
          // 动态尺寸/亮度经 IconTheme 注入（hover 提亮）；字形阴影由传入
          // 组件自带（调用点统一挂 ContrastStyle.glyphShadows）。
          child: IconTheme(
            data: IconThemeData(size: widget.size, color: effectiveColor),
            child: widget.icon,
          ),
        ),
      ),
    );

    if (widget.tooltip != null && widget.tooltip!.isNotEmpty) {
      return AppTooltip(
        message: widget.tooltip!,
        child: child,
      );
    }
    return child;
  }
}

