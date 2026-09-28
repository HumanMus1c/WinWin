import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:winwin/core/input/app_escape_scope.dart';
import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/core/storage/storage_key.dart';
import 'package:winwin/pages/video/player_controller.dart';

/// Duration 没有 clamp 方法，手动实现（用于 seek 位置限制）。
Duration _clampDuration(Duration value, Duration min, Duration max) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

/// 播放器键盘快捷键包装器（Phase 4.3）。
///
/// 移植自 PiliPlus `pages/video/widgets/player_focus.dart`。
/// 用 [Focus] + [KeyboardListener] 监听键盘事件，映射到播放器操作。
/// 桌面端必备：空格暂停、←→ 快进快退、↑↓ 音量、F 全屏、M 静音、
/// D 弹幕开关、S 截图（Phase 4.6）、L 锁定控制条。
///
/// 用法：将 [PlayerFocus] 包裹在 [PlayerPanel] 外层，自动请求焦点。
class PlayerFocus extends StatefulWidget {
  const PlayerFocus({
    super.key,
    required this.controller,
    required this.child,
    this.onToggleFullscreen,
    this.onToggleInAppFullscreen,
    this.onEscape,
    this.onScreenshot,
    this.onToggleDanmaku,
    this.onLockToggle,
    this.onSpeedChange,
    this.enabled = true,
  });

  final WinWinPlayerController controller;
  final Widget child;
  final VoidCallback? onToggleFullscreen;
  final VoidCallback? onToggleInAppFullscreen;

  /// Esc 键回调（固定语义：返回上一级——全屏态退出全屏，否则退出页面）。
  final VoidCallback? onEscape;
  final VoidCallback? onScreenshot;
  final VoidCallback? onToggleDanmaku;
  final ValueChanged<bool>? onLockToggle;

  /// 长按快进倍速提示回调（对标 PiliPlus，驱动 UI 胶囊提示）
  final void Function(bool isLongPress, double speed)? onSpeedChange;

  /// 是否启用键盘快捷键（锁定控制条时可设为 false）。
  final bool enabled;

  @override
  State<PlayerFocus> createState() => _PlayerFocusState();
}

class _PlayerFocusState extends State<PlayerFocus> {
  final FocusNode _focusNode = FocusNode();
  double? _mutedVolume;

  // ── 方向键交互防抖与长按高倍速快进（对标 PiliPlus）──
  Timer? _rightArrowLongPressTimer;
  bool _isRightArrowLongPressing = false;
  double? _originalSpeedBeforeLongPress;
  bool _isLeftArrowPressed = false;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _rightArrowLongPressTimer?.cancel();
    _rightArrowLongPressTimer = null;
    _focusNode.dispose();
    super.dispose();
  }

  /// 快进/快退步长（秒）。
  static const int _seekStep = 10;
  /// 音量步长。
  static const double _volumeStep = 10;

  bool _handleKey(KeyEvent event) {
    if (!widget.enabled) return false;
    // 输入框（发弹幕 / 评论等）聚焦时不拦截快捷键；Esc 交由全局层“取消聚焦”。
    if (isTextInputFocused()) return false;
    final c = widget.controller;
    final key = event.logicalKey;

    // ── 左右方向键交互（对标 PiliPlus：长按 200ms 触发 3x 高倍速，KeyUp 触发单次 Seek，杜绝 KeyDown 狂轰滥炸）──
    if (key == LogicalKeyboardKey.arrowRight) {
      if (event is KeyDownEvent) {
        if (_isRightArrowLongPressing || _rightArrowLongPressTimer != null) {
          // Windows 键盘自动 repeat 派发的重复 KeyDown，全部吸收拦截
          return true;
        }
        _originalSpeedBeforeLongPress = c.playbackSpeed.value;
        _rightArrowLongPressTimer = Timer(const Duration(milliseconds: 200), () {
          if (!mounted || !widget.enabled) return;
          _isRightArrowLongPressing = true;
          final targetSpeed = GStorage.video.get(
            VideoBoxKey.longPressSpeedDefault,
            defaultValue: 3.0,
          );
          c.setPlaybackSpeed(targetSpeed);
          widget.onSpeedChange?.call(true, targetSpeed);
        });
        return true;
      } else if (event is KeyUpEvent) {
        if (_isRightArrowLongPressing) {
          // 长按状态松开：恢复原速
          final original = _originalSpeedBeforeLongPress ?? 1.0;
          c.setPlaybackSpeed(original);
          _originalSpeedBeforeLongPress = null;
          _isRightArrowLongPressing = false;
          widget.onSpeedChange?.call(false, original);
        } else if (_rightArrowLongPressTimer != null) {
          // 200ms 内松开：属于短按单击，触发单次快进 10s
          _rightArrowLongPressTimer?.cancel();
          _rightArrowLongPressTimer = null;
          _seekRelative(c, _seekStep);
        }
        return true;
      }
      return false;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      if (event is KeyDownEvent) {
        if (_isLeftArrowPressed) {
          // 吸收长按产生的重复 KeyDown
          return true;
        }
        _isLeftArrowPressed = true;
        return true;
      } else if (event is KeyUpEvent) {
        if (_isLeftArrowPressed) {
          _isLeftArrowPressed = false;
          _seekRelative(c, -_seekStep);
        }
        return true;
      }
      return false;
    }

    // 其余功能键仅在按下瞬间（KeyDownEvent）生效
    if (event is! KeyDownEvent) return false;

    // 空格 = 播放/暂停
    if (key == LogicalKeyboardKey.space) {
      c.playOrPause();
      return true;
    }
    // F = 全屏切换
    if (key == LogicalKeyboardKey.keyF) {
      widget.onToggleFullscreen?.call();
      return true;
    }
    // W = 网页全屏切换（对标 B 站 Web 端）
    if (key == LogicalKeyboardKey.keyW) {
      widget.onToggleInAppFullscreen?.call();
      return true;
    }
    // M = 静音切换
    if (key == LogicalKeyboardKey.keyM) {
      _toggleMute(c);
      return true;
    }
    // D = 弹幕开关
    if (key == LogicalKeyboardKey.keyD) {
      widget.onToggleDanmaku?.call();
      return true;
    }
    // S = 截图（Phase 4.6）
    if (key == LogicalKeyboardKey.keyS) {
      widget.onScreenshot?.call();
      return true;
    }
    // L = 锁定控制条
    if (key == LogicalKeyboardKey.keyL) {
      widget.onLockToggle?.call(!_focusNode.canRequestFocus);
      return true;
    }
    // Esc = 返回上一级（全屏态退出全屏，否则退出页面；不再切换全屏）
    if (key == LogicalKeyboardKey.escape) {
      widget.onEscape?.call();
      return true;
    }
    // ↑ = 音量 +10
    if (key == LogicalKeyboardKey.arrowUp) {
      c.setVolume(c.volume.value + _volumeStep);
      return true;
    }
    // ↓ = 音量 -10
    if (key == LogicalKeyboardKey.arrowDown) {
      c.setVolume(c.volume.value - _volumeStep);
      return true;
    }
    // 0-9 = 跳转到 0%-90%
    final digit = _digitFromKey(key);
    if (digit != null) {
      _seekToPercent(c, digit * 10);
      return true;
    }
    // < = 降速
    if (key == LogicalKeyboardKey.comma) {
      _adjustSpeed(c, -1);
      return true;
    }
    // > = 升速
    if (key == LogicalKeyboardKey.period) {
      _adjustSpeed(c, 1);
      return true;
    }
    return false;
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    return _handleKey(event)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  void _toggleMute(WinWinPlayerController c) {
    if (c.volume.value > 0) {
      _mutedVolume = c.volume.value;
      c.setVolume(0);
    } else {
      c.setVolume(_mutedVolume ?? 80);
      _mutedVolume = null;
    }
  }

  void _seekRelative(WinWinPlayerController c, int deltaSec) {
    final basePos = c.isSeeking ? c.seekPosition.value : c.position.value;
    final target = basePos + Duration(seconds: deltaSec);
    final clamped = _clampDuration(target, Duration.zero, c.duration.value);
    c.seek(clamped);
  }

  void _seekToPercent(WinWinPlayerController c, int percent) {
    final dur = c.duration.value;
    if (dur.inSeconds <= 0) return;
    final target = Duration(
      milliseconds: (dur.inMilliseconds * percent / 100).round(),
    );
    c.seek(target);
  }

  /// 在 speedList 中升降一档。
  void _adjustSpeed(WinWinPlayerController c, int direction) {
    final speeds = c.speedList;
    if (speeds.isEmpty) return;
    final current = c.playbackSpeed.value;
    if (direction > 0) {
      // 升速：找第一个大于当前的
      for (final s in speeds) {
        if (s > current) {
          c.setPlaybackSpeed(s);
          return;
        }
      }
    } else {
      // 降速：找第一个小于当前的（倒序遍历）
      for (final s in speeds.reversed) {
        if (s < current) {
          c.setPlaybackSpeed(s);
          return;
        }
      }
    }
  }

  int? _digitFromKey(LogicalKeyboardKey key) {
    // 主键盘数字键 0-9
    if (key.keyId >= LogicalKeyboardKey.digit0.keyId &&
        key.keyId <= LogicalKeyboardKey.digit9.keyId) {
      return key.keyId - LogicalKeyboardKey.digit0.keyId;
    }
    // 小键盘 0-9
    if (key.keyId >= LogicalKeyboardKey.numpad0.keyId &&
        key.keyId <= LogicalKeyboardKey.numpad9.keyId) {
      return key.keyId - LogicalKeyboardKey.numpad0.keyId;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKeyEvent,
      child: widget.child,
    );
  }
}

/// 双击快进/快退手势检测器（Phase 4.3）。
///
/// 左半区双击后退 [backwardStep] 秒，右半区双击前进 [forwardStep] 秒。
/// 双击时显示波纹动画 + 时间提示（由 [onFeedback] 回调驱动 UI）。
class DoubleTapSeekDetector extends StatefulWidget {
  const DoubleTapSeekDetector({
    super.key,
    required this.controller,
    required this.child,
    this.forwardStep = 10,
    this.backwardStep = 10,
    this.onFeedback,
  });

  final WinWinPlayerController controller;
  final Widget child;
  final int forwardStep;
  final int backwardStep;

  /// 双击反馈回调：(isForward, deltaSeconds) → 显示波纹 + 提示。
  final void Function(bool isForward, int deltaSec)? onFeedback;

  @override
  State<DoubleTapSeekDetector> createState() => _DoubleTapSeekDetectorState();
}

class _DoubleTapSeekDetectorState extends State<DoubleTapSeekDetector> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onDoubleTapDown: (details) {
            final isRight = details.localPosition.dx > width / 2;
            _handleDoubleTap(isRight);
          },
          onDoubleTap: () {}, // 必须提供，否则 onDoubleTapDown 不触发
          child: widget.child,
        );
      },
    );
  }

  void _handleDoubleTap(bool isRight) {
    final c = widget.controller;
    final delta = isRight ? widget.forwardStep : -widget.backwardStep;
    final basePos = c.isSeeking ? c.seekPosition.value : c.position.value;
    final target = basePos + Duration(seconds: delta);
    final clamped = _clampDuration(target, Duration.zero, c.duration.value);
    c.seek(clamped);
    widget.onFeedback?.call(isRight, delta.abs());
  }
}

/// 长按倍速手势检测器（Phase 4.3）。
///
/// 长按时切换到 [longPressSpeed]（默认 3.0x），松开恢复原速。
/// 速度偏好持久化到 [VideoBoxKey.longPressSpeedDefault]。
class LongPressSpeedDetector extends StatefulWidget {
  const LongPressSpeedDetector({
    super.key,
    required this.controller,
    required this.child,
    this.onSpeedChange,
  });

  final WinWinPlayerController controller;
  final Widget child;

  /// 倍速变化回调：(isLongPress, currentSpeed) → UI 更新。
  final void Function(bool isLongPress, double speed)? onSpeedChange;

  @override
  State<LongPressSpeedDetector> createState() => _LongPressSpeedDetectorState();
}

class _LongPressSpeedDetectorState extends State<LongPressSpeedDetector> {
  double? _originalSpeed;

  double get _longPressSpeed {
    final box = GStorage.video;
    return box.get(VideoBoxKey.longPressSpeedDefault, defaultValue: 3.0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPressStart: (_) => _onLongPressStart(),
      onLongPressEnd: (_) => _onLongPressEnd(),
      child: widget.child,
    );
  }

  void _onLongPressStart() {
    final c = widget.controller;
    _originalSpeed = c.playbackSpeed.value;
    final target = _longPressSpeed;
    c.setPlaybackSpeed(target);
    widget.onSpeedChange?.call(true, target);
  }

  void _onLongPressEnd() {
    final c = widget.controller;
    final original = _originalSpeed ?? 1.0;
    c.setPlaybackSpeed(original);
    _originalSpeed = null;
    widget.onSpeedChange?.call(false, original);
  }
}

/// 水平拖动快进手势检测器（Phase 4.3）。
///
/// 水平拖动时根据拖动距离计算 ΔPosition，实时显示拖动进度提示。
/// 拖动结束 seek 到目标位置。
class HorizontalSeekDetector extends StatefulWidget {
  const HorizontalSeekDetector({
    super.key,
    required this.controller,
    required this.child,
    this.sensitivity = 1.0,
    this.onSeeking,
  });

  final WinWinPlayerController controller;
  final Widget child;

  /// 灵敏度系数：像素 → 秒的换算（1.0 = 1px 1s）。
  final double sensitivity;

  /// 拖动中回调：(deltaSec, targetPosition) → UI 更新。
  final void Function(int deltaSec, Duration target)? onSeeking;

  @override
  State<HorizontalSeekDetector> createState() => _HorizontalSeekDetectorState();
}

class _HorizontalSeekDetectorState extends State<HorizontalSeekDetector> {
  Duration? _dragStart;
  double _dragDelta = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (details) {
        _dragStart = widget.controller.isSeeking
            ? widget.controller.seekPosition.value
            : widget.controller.position.value;
        _dragDelta = 0;
      },
      onHorizontalDragUpdate: (details) {
        if (_dragStart == null) return;
        _dragDelta += details.delta.dx * widget.sensitivity;
        final deltaSec = _dragDelta.round();
        final target = _clampDuration(
          _dragStart! + Duration(seconds: deltaSec),
          Duration.zero,
          widget.controller.duration.value,
        );
        widget.onSeeking?.call(deltaSec, target);
      },
      onHorizontalDragEnd: (_) {
        if (_dragStart != null) {
          final deltaSec = _dragDelta.round();
          final target = _clampDuration(
            _dragStart! + Duration(seconds: deltaSec),
            Duration.zero,
            widget.controller.duration.value,
          );
          widget.controller.seek(target);
        }
        _dragStart = null;
        _dragDelta = 0;
      },
      child: widget.child,
    );
  }
}
