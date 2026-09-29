// Copyright 2026 WinWin Authors. All rights reserved.
// Ported & adapted from PiliPlus audio_video_progress_bar.dart (GPL-3.0).

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart'
    show
        MouseTrackerAnnotation,
        PointerEnterEventListener,
        PointerExitEventListener;

/// 进度条跳转回调（传递跳转目标毫秒数）。
typedef OnSeek = void Function(int milliseconds);

/// 拖动开始回调。
typedef ThumbDragStartCallback = void Function(ThumbDragDetails details);

/// 拖动进度更新回调。
typedef ThumbDragUpdateCallback = void Function(ThumbDragDetails details);

/// 拖动事件详情。
class ThumbDragDetails {
  const ThumbDragDetails({
    this.seconds = 0,
    this.milliseconds = 0,
    this.globalPosition = Offset.zero,
    this.localPosition = Offset.zero,
  });

  /// 当前 Thumb 对应的秒数。
  final int seconds;

  /// 当前 Thumb 对应的毫秒数。
  final int milliseconds;

  /// 全局拖动坐标。
  final Offset globalPosition;

  /// 局部拖动坐标。
  final Offset localPosition;

  @override
  String toString() =>
      '${objectRuntimeType(this, 'ThumbDragDetails')}('
      'time: ${seconds}s (${milliseconds}ms), '
      'global: $globalPosition, '
      'local: $localPosition)';
}

/// 优先赢得手势竞技场的水平拖动手势识别器。
/// 在 PointerDown 时即刻锁定 accepted，避免被外层滑动/导航组件截断。
class _EagerHorizontalDragGestureRecognizer
    extends HorizontalDragGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }

  @override
  String get debugDescription => '_EagerHorizontalDragGestureRecognizer';
}

/// 高性能视频/音频进度条组件。
///
/// 严格对标 PiliPlus 实现，基于 [LeafRenderObjectWidget] 与 Canvas Direct Painting。
/// 具备：
/// 1. 拖动状态物理隔离：用户拖动/按压期间，屏蔽外部进度推送跳变；
/// 2. 缓冲条（buffered）与播放条（progress）双轨渲染；
/// 3. 支持光晕发光 Thumb 与即时点击 Seek。
class ProgressBar extends LeafRenderObjectWidget {
  const ProgressBar({
    super.key,
    required this.progress,
    required this.total,
    this.buffered = 0,
    this.onSeek,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.barHeight = 3.5,
    required this.baseBarColor,
    required this.progressBarColor,
    required this.bufferedBarColor,
    this.thumbRadius = 6.0,
    required this.thumbColor,
    required this.thumbGlowColor,
    this.thumbGlowRadius = 18.0,
    this.thumbCanPaintOutsideBar = true,
  });

  /// 已播放时长（毫秒）。
  final int progress;

  /// 媒体总时长（毫秒）。
  final int total;

  /// 已缓冲时长（毫秒）。
  final int buffered;

  /// Seek 确认回调（手指抬起或点击完成时触发，传递目标毫秒）。
  final OnSeek? onSeek;

  /// 拖动开始。
  final ThumbDragStartCallback? onDragStart;

  /// 拖动持续更新。
  final ThumbDragUpdateCallback? onDragUpdate;

  /// 拖动结束。
  final VoidCallback? onDragEnd;

  /// 轨道高度。
  final double barHeight;

  /// 进度条底色（未播放且未缓冲）。
  final Color baseBarColor;

  /// 播放进度条颜色。
  final Color progressBarColor;

  /// 缓冲进度条颜色。
  final Color bufferedBarColor;

  /// 滑块圆点半径。
  final double thumbRadius;

  /// 滑块颜色。
  final Color thumbColor;

  /// 拖动时光晕颜色。
  final Color thumbGlowColor;

  /// 光晕半径。
  final double thumbGlowRadius;

  /// 滑块是否可在轨道外延伸。
  final bool thumbCanPaintOutsideBar;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderProgressBar(
      progress: progress,
      total: total,
      buffered: buffered,
      onSeek: onSeek,
      onDragStart: onDragStart,
      onDragUpdate: onDragUpdate,
      onDragEnd: onDragEnd,
      barHeight: barHeight,
      baseBarColor: baseBarColor,
      progressBarColor: progressBarColor,
      bufferedBarColor: bufferedBarColor,
      thumbRadius: thumbRadius,
      thumbColor: thumbColor,
      thumbGlowColor: thumbGlowColor,
      thumbGlowRadius: thumbGlowRadius,
      thumbCanPaintOutsideBar: thumbCanPaintOutsideBar,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderProgressBar renderObject,
  ) {
    renderObject
      ..total = total
      ..progress = progress
      ..buffered = buffered
      ..onSeek = onSeek
      ..onDragStart = onDragStart
      ..onDragUpdate = onDragUpdate
      ..onDragEnd = onDragEnd
      ..barHeight = barHeight
      ..baseBarColor = baseBarColor
      ..progressBarColor = progressBarColor
      ..bufferedBarColor = bufferedBarColor
      ..thumbRadius = thumbRadius
      ..thumbColor = thumbColor
      ..thumbGlowColor = thumbGlowColor
      ..thumbGlowRadius = thumbGlowRadius
      ..thumbCanPaintOutsideBar = thumbCanPaintOutsideBar;
  }
}

class RenderProgressBar extends RenderBox implements MouseTrackerAnnotation {
  RenderProgressBar({
    required this._progress,
    required this._total,
    required this._buffered,
    this._onSeek,
    ThumbDragStartCallback? onDragStart,
    ThumbDragUpdateCallback? onDragUpdate,
    VoidCallback? onDragEnd,
    required this._barHeight,
    required this._baseBarColor,
    required this._progressBarColor,
    required this._bufferedBarColor,
    this._thumbRadius = 6.0,
    required this._thumbColor,
    required this._thumbGlowColor,
    this._thumbGlowRadius = 18.0,
    this._thumbCanPaintOutsideBar = true,
  })  : _onDragStartUserCallback = onDragStart,
        _onDragUpdateUserCallback = onDragUpdate,
        _onDragEndUserCallback = onDragEnd,
        _paintThumbGlow = _thumbGlowRadius > _thumbRadius,
        _hitTestSelf = onDragStart != null || _onSeek != null {
    if (_hitTestSelf) {
      _drag = _EagerHorizontalDragGestureRecognizer()
        ..onStart = _onDragStart
        ..onUpdate = _onDragUpdate
        ..onEnd = _onDragEnd
        ..onCancel = _finishDrag;
    }
    if (!_userIsDraggingThumb) {
      _thumbValue = _proportionOfTotal(_progress);
    }
  }

  @override
  void dispose() {
    _drag?.dispose();
    _drag = null;
    super.dispose();
  }

  _EagerHorizontalDragGestureRecognizer? _drag;
  double _thumbValue = 0.0;
  bool _userIsDraggingThumb = false;

  void _onDragStart(DragStartDetails details) {
    _userIsDraggingThumb = true;
    _updateThumbPosition(details.localPosition);
    final ms = _currentThumbDurationInMilliseconds();
    onDragStart?.call(
      ThumbDragDetails(
        seconds: ms ~/ 1000,
        milliseconds: ms,
        globalPosition: details.globalPosition,
        localPosition: details.localPosition,
      ),
    );
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _updateThumbPosition(details.localPosition);
    final ms = _currentThumbDurationInMilliseconds();
    onDragUpdate?.call(
      ThumbDragDetails(
        seconds: ms ~/ 1000,
        milliseconds: ms,
        globalPosition: details.globalPosition,
        localPosition: details.localPosition,
      ),
    );
  }

  void _onDragEnd(DragEndDetails details) {
    final ms = _currentThumbDurationInMilliseconds();
    onDragEnd?.call();
    onSeek?.call(ms);
    _finishDrag();
  }

  void _finishDrag() {
    _userIsDraggingThumb = false;
    markNeedsPaint();
  }

  int _currentThumbDurationInMilliseconds() {
    return (_thumbValue * total).round();
  }

  void _updateThumbPosition(Offset localPosition) {
    final dx = localPosition.dx;
    final barCapRadius = _barHeight / 2;
    final barStart = barCapRadius;
    final barEnd = size.width - barCapRadius;
    final barWidth = max(0.0, barEnd - barStart);
    if (barWidth <= 0) {
      _thumbValue = 0.0;
    } else {
      final position = (dx - barStart).clamp(0.0, barWidth);
      _thumbValue = position / barWidth;
    }
    _progress = _currentThumbDurationInMilliseconds();
    markNeedsPaint();
  }

  int get progress => _progress;
  int _progress;
  set progress(int value) {
    final clamp = _clampDuration(value);
    if (_progress == clamp) return;
    if (!_userIsDraggingThumb) {
      _progress = clamp;
      _thumbValue = _proportionOfTotal(clamp);
    }
    markNeedsPaint();
  }

  int get total => _total;
  int _total;
  set total(int value) {
    final clamp = value.isNegative ? 0 : value;
    if (_total == clamp) return;
    _total = clamp;
    if (!_userIsDraggingThumb) {
      _thumbValue = _proportionOfTotal(_progress);
    }
    markNeedsPaint();
  }

  int get buffered => _buffered;
  int _buffered;
  set buffered(int value) {
    final clamp = _clampDuration(value);
    if (_buffered == clamp) return;
    _buffered = clamp;
    markNeedsPaint();
  }

  int _clampDuration(int value) {
    if (value.isNegative) return 0;
    if (value > _total) return _total;
    return value;
  }

  OnSeek? get onSeek => _onSeek;
  OnSeek? _onSeek;
  set onSeek(OnSeek? value) {
    if (_onSeek == value) return;
    _onSeek = value;
  }

  ThumbDragStartCallback? get onDragStart => _onDragStartUserCallback;
  ThumbDragStartCallback? _onDragStartUserCallback;
  set onDragStart(ThumbDragStartCallback? value) {
    if (_onDragStartUserCallback == value) return;
    _onDragStartUserCallback = value;
  }

  ThumbDragUpdateCallback? get onDragUpdate => _onDragUpdateUserCallback;
  ThumbDragUpdateCallback? _onDragUpdateUserCallback;
  set onDragUpdate(ThumbDragUpdateCallback? value) {
    if (_onDragUpdateUserCallback == value) return;
    _onDragUpdateUserCallback = value;
  }

  VoidCallback? get onDragEnd => _onDragEndUserCallback;
  VoidCallback? _onDragEndUserCallback;
  set onDragEnd(VoidCallback? value) {
    if (_onDragEndUserCallback == value) return;
    _onDragEndUserCallback = value;
  }

  double get barHeight => _barHeight;
  double _barHeight;
  set barHeight(double value) {
    if (_barHeight == value) return;
    _barHeight = value;
    markNeedsPaint();
  }

  Color get baseBarColor => _baseBarColor;
  Color _baseBarColor;
  set baseBarColor(Color value) {
    if (_baseBarColor == value) return;
    _baseBarColor = value;
    markNeedsPaint();
  }

  Color get progressBarColor => _progressBarColor;
  Color _progressBarColor;
  set progressBarColor(Color value) {
    if (_progressBarColor == value) return;
    _progressBarColor = value;
    markNeedsPaint();
  }

  Color get bufferedBarColor => _bufferedBarColor;
  Color _bufferedBarColor;
  set bufferedBarColor(Color value) {
    if (_bufferedBarColor == value) return;
    _bufferedBarColor = value;
    markNeedsPaint();
  }

  Color get thumbColor => _thumbColor;
  Color _thumbColor;
  set thumbColor(Color value) {
    if (_thumbColor == value) return;
    _thumbColor = value;
    markNeedsPaint();
  }

  double get thumbRadius => _thumbRadius;
  double _thumbRadius;
  set thumbRadius(double value) {
    if (_thumbRadius == value) return;
    _thumbRadius = value;
    markNeedsLayout();
  }

  Color get thumbGlowColor => _thumbGlowColor;
  Color _thumbGlowColor;
  set thumbGlowColor(Color value) {
    if (_thumbGlowColor == value) return;
    _thumbGlowColor = value;
    if (_userIsDraggingThumb) markNeedsPaint();
  }

  bool _paintThumbGlow;
  double get thumbGlowRadius => _thumbGlowRadius;
  double _thumbGlowRadius;
  set thumbGlowRadius(double value) {
    if (_thumbGlowRadius == value) return;
    _thumbGlowRadius = value;
    _paintThumbGlow = value > _thumbRadius;
    markNeedsLayout();
  }

  bool get thumbCanPaintOutsideBar => _thumbCanPaintOutsideBar;
  bool _thumbCanPaintOutsideBar;
  set thumbCanPaintOutsideBar(bool value) {
    if (_thumbCanPaintOutsideBar == value) return;
    _thumbCanPaintOutsideBar = value;
    markNeedsPaint();
  }

  static const _minDesiredWidth = 100.0;

  @override
  double computeMinIntrinsicWidth(double height) => _minDesiredWidth;

  @override
  double computeMaxIntrinsicWidth(double height) => _minDesiredWidth;

  @override
  double computeMinIntrinsicHeight(double width) => _height();

  @override
  double computeMaxIntrinsicHeight(double width) => _height();

  final bool _hitTestSelf;
  @override
  bool hitTestSelf(Offset position) => _hitTestSelf;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    assert(debugHandleEvent(event, entry));
    if (event is PointerDownEvent) {
      _drag?.addPointer(event);
    }
  }

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final desiredWidth = constraints.maxWidth;
    final desiredHeight = _height();
    return constraints.constrainDimensions(desiredWidth, desiredHeight);
  }

  double _height() {
    return max(2 * max(_thumbRadius, _thumbGlowRadius), _barHeight);
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas
      ..save()
      ..translate(offset.dx, offset.dy);

    _drawProgressBar(canvas, Offset.zero, size);

    canvas.restore();
  }

  void _drawProgressBar(Canvas canvas, Offset offset, Size localSize) {
    canvas
      ..save()
      ..translate(offset.dx, offset.dy);
    _drawBaseBar(canvas, localSize);
    _drawBufferedBar(canvas, localSize);
    _drawCurrentProgressBar(canvas, localSize);
    _drawThumb(canvas, localSize);
    canvas.restore();
  }

  void _drawBaseBar(Canvas canvas, Size localSize) {
    _drawBar(
      canvas: canvas,
      availableSize: localSize,
      widthProportion: 1.0,
      color: baseBarColor,
    );
  }

  void _drawBufferedBar(Canvas canvas, Size localSize) {
    if (total <= 0 || _buffered <= 0) return;
    _drawBar(
      canvas: canvas,
      availableSize: localSize,
      widthProportion: _proportionOfTotal(_buffered),
      color: bufferedBarColor,
    );
  }

  void _drawCurrentProgressBar(Canvas canvas, Size localSize) {
    if (total <= 0) return;
    _drawBar(
      canvas: canvas,
      availableSize: localSize,
      widthProportion: _thumbValue,
      color: progressBarColor,
    );
  }

  void _drawBar({
    required Canvas canvas,
    required Size availableSize,
    required double widthProportion,
    required Color color,
  }) {
    if (widthProportion <= 0) return;
    final barPaint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = _barHeight;
    final capRadius = _barHeight / 2;
    final adjustedWidth = availableSize.width - _barHeight;
    if (adjustedWidth <= 0) return;
    final dx = widthProportion * adjustedWidth + capRadius;
    final dy = availableSize.height / 2;
    final startPoint = Offset(capRadius, dy);
    final endPoint = Offset(dx, dy);
    canvas.drawLine(startPoint, endPoint, barPaint);
  }

  void _drawThumb(Canvas canvas, Size localSize) {
    final thumbPaint = Paint()..color = thumbColor;
    final barCapRadius = _barHeight / 2;
    final availableWidth = localSize.width - _barHeight;
    var thumbDx = _thumbValue * max(0.0, availableWidth) + barCapRadius;
    if (!_thumbCanPaintOutsideBar) {
      thumbDx = thumbDx.clamp(_thumbRadius, localSize.width - _thumbRadius);
    }
    final center = Offset(thumbDx, localSize.height / 2);
    if (_userIsDraggingThumb && _paintThumbGlow) {
      final thumbGlowPaint = Paint()..color = thumbGlowColor;
      canvas.drawCircle(center, thumbGlowRadius, thumbGlowPaint);
    }
    canvas.drawCircle(center, thumbRadius, thumbPaint);
  }

  double _proportionOfTotal(int duration) {
    if (total <= 0) return 0.0;
    return (duration / total).clamp(0.0, 1.0);
  }

  @override
  MouseCursor get cursor => SystemMouseCursors.click;

  @override
  PointerEnterEventListener? onEnter;

  @override
  PointerExitEventListener? onExit;

  @override
  bool get validForMouseTracker => true;
}
