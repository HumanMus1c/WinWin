import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 下拉刷新（B7-c5 刷新体系批）：零 `material_ui` 依赖的**自绘紧凑指示环**。
//
// 为何自研（硬约束，非偏好）：
//   1. B7 目标 = lib 全量退役 `material_ui`；原 `AppRefreshIndicator` 只是
//      material `RefreshIndicator` 的薄封装，必须去依赖；
//   2. flutter_miuix 的 `MiuixPullToRefresh`（下推灰环 + 状态文案）已在
//      2026-10-03 被用户复测明确否掉（"原已有的下拉视觉更好"，见
//      docs/flutter_miuix修复轮2-刷新视觉回退与字重滑块复盘-2026-10-03.md），
//      不可用于替代；
//   3. 故在硬约束下自绘实现，几何与动画口径**逐条对齐** Flutter material
//      `RefreshIndicator` / `RefreshProgressIndicator`
//      （上游源：flutter/packages/flutter/lib/src/material/{refresh_indicator,progress_indicator}.dart，
//       BSD-3-Clause），确保与替换前观感/手感 1:1：
//         · 位移 `displacement`（settle 距离）+ `edgeOffset`（起始偏移）
//         · 41px 圆形底（elevation 2 阴影 + 12 内边距）+ 环宽 `strokeWidth`
//         · 拖动 → arc 增长 + 箭头（arrowhead）；松手吸附 150ms；
//         · 刷新中 → 不定态旋转；完成 → 200ms 收起
//
// 视觉参数口径（用户偏好定格）：紧凑扁平细环。`displacement` 为**直接**
// 逻辑位移（不再乘 0.8；默认 32 与原 `displacement * 0.8` 的等效值一致）。
// ═══════════════════════════════════════════════════════════════════════════

// ── 口径常量（逐条对齐 material）─────────────────────────────────────────
const double _kDragContainerExtentPercentage = 0.25;
const double _kDragSizeFactorLimit = 1.5;
const Duration _kIndicatorSnapDuration = Duration(milliseconds: 150);
const Duration _kIndicatorScaleDuration = Duration(milliseconds: 200);
const int _kIndeterminateCircularDuration = 1333 * 2222;
const double _kRingSize = 41.0;
const double _kRingMargin = 4.0;
const double _kRingPadding = 12.0;
const double _kStrokeHeadInterval = 0.33;

/// 无主题时的兜底前景色（= biliPink = Miuix 语义 primary）。
const Color _kFallbackPrimary = Color(0xFFFA7298);

/// 无主题时的兜底底色。
const Color _kFallbackSurface = Color(0xFFFFFFFF);

/// 下拉越阈值后回调（与 material `RefreshCallback` 同义）。
typedef RefreshCallback = Future<void> Function();

bool _defaultScrollNotificationPredicate(ScrollNotification n) => n.depth == 0;

/// 下拉刷新指示器（自绘紧凑环；零 `material_ui`）。
///
/// 用法与旧版一致：
/// ```dart
/// AppRefreshIndicator(
///   onRefresh: controller.onRefresh,
///   child: ListView(...),
/// )
/// ```
class AppRefreshIndicator extends StatefulWidget {
  const AppRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
    this.displacement = 32.0,
    this.edgeOffset = 0.0,
    this.color,
    this.strokeWidth = 2.2,
    this.notificationPredicate = _defaultScrollNotificationPredicate,
  });

  /// 越过阈值松手后回调。
  final RefreshCallback onRefresh;

  /// 被指示器覆盖的可滚动内容。
  final Widget child;

  /// 指示器停靠（settle）处距父级顶/底的逻辑距离（紧凑默认 32）。
  final double displacement;

  /// 指示器开始出现处距父级边缘的偏移（用于避让顶部浮动控件）。
  final double edgeOffset;

  /// 环前景色；null 取 Miuix 语义 `primary`（= biliPink）。
  final Color? color;

  /// 环宽（紧凑默认 2.2）。
  final double strokeWidth;

  /// 只处理 depth == 0 的滚动通知（对齐 material 默认）。
  final ScrollNotificationPredicate notificationPredicate;

  @override
  State<AppRefreshIndicator> createState() => _AppRefreshIndicatorState();
}

enum _RefreshStatus { drag, armed, snap, refresh, done, canceled }

class _AppRefreshIndicatorState extends State<AppRefreshIndicator>
    with TickerProviderStateMixin {
  late final AnimationController _positionController;
  late final AnimationController _scaleController;
  late final Animation<double> _positionFactor;
  late final Animation<double> _scaleFactor;
  late final Animation<double> _value;
  late Animation<Color?> _valueColor;

  _RefreshStatus? _status;
  Future<void> _pendingRefreshFuture = Future<void>.value();
  bool? _isIndicatorAtTop;
  double? _dragOffset;
  Color _effectiveValueColor = _kFallbackPrimary;

  static final Animatable<double> _threeQuarterTween =
      Tween<double>(begin: 0.0, end: 0.75);

  static final Animatable<double> _kDragSizeFactorLimitTween =
      Tween<double>(begin: 0.0, end: _kDragSizeFactorLimit);

  static final Animatable<double> _oneToZeroTween =
      Tween<double>(begin: 1.0, end: 0.0);

  @override
  void initState() {
    super.initState();
    _positionController = AnimationController(vsync: this);
    _positionFactor = _positionController.drive(_kDragSizeFactorLimitTween);

    // 拖动期间的进度的 = 环的 0.75 圈。
    _value = _positionController.drive(_threeQuarterTween);

    _scaleController = AnimationController(vsync: this);
    _scaleFactor = _scaleController.drive(_oneToZeroTween);
    _valueColor = const AlwaysStoppedAnimation<Color>(Color(0x00000000));
  }

  @override
  void didChangeDependencies() {
    _setupColorTween();
    super.didChangeDependencies();
  }

  @override
  void didUpdateWidget(AppRefreshIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color != widget.color) {
      _setupColorTween();
    }
  }

  @override
  void dispose() {
    _positionController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  Color _defaultColor(BuildContext context) =>
      MiuixTheme.maybeOf(context)?.colors.primary ?? _kFallbackPrimary;

  void _setupColorTween() {
    _effectiveValueColor = widget.color ?? _defaultColor(context);
    final Color color = _effectiveValueColor;
    if (color.a == 0.0) {
      _valueColor = AlwaysStoppedAnimation<Color>(color);
    } else {
      // 按 positionController 进度淡入；随 alpha 保持。
      _valueColor = _positionController.drive(
        ColorTween(
          begin: color.withValues(alpha: 0.0),
          end: color.withValues(alpha: color.a),
        ).chain(CurveTween(curve: const Interval(0.0, 1.0 / _kDragSizeFactorLimit))),
      );
    }
  }

  bool _shouldStart(ScrollNotification notification) {
    // 非用户拖拽（jumpTo / 惯性）带来的滚动不触发；仅当贴边起始。
    return ((notification is ScrollStartNotification &&
                notification.dragDetails != null) ||
            (notification is ScrollUpdateNotification &&
                notification.dragDetails != null)) &&
        ((notification.metrics.axisDirection == AxisDirection.up &&
                notification.metrics.extentAfter == 0.0) ||
            (notification.metrics.axisDirection == AxisDirection.down &&
                notification.metrics.extentBefore == 0.0)) &&
        _status == null &&
        _start(notification.metrics.axisDirection);
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (!widget.notificationPredicate(notification)) {
      return false;
    }
    if (_shouldStart(notification)) {
      setState(() {
        _status = _RefreshStatus.drag;
      });
      return false;
    }
    final bool? indicatorAtTopNow = switch (notification.metrics.axisDirection) {
      AxisDirection.down || AxisDirection.up => true,
      AxisDirection.left || AxisDirection.right => null,
    };
    if (indicatorAtTopNow != _isIndicatorAtTop) {
      if (_status == _RefreshStatus.drag ||
          _status == _RefreshStatus.armed) {
        _dismiss(_RefreshStatus.canceled);
      }
    } else if (notification is ScrollUpdateNotification) {
      if (_status == _RefreshStatus.drag ||
          _status == _RefreshStatus.armed) {
        if (notification.metrics.axisDirection == AxisDirection.down) {
          _dragOffset = _dragOffset! - notification.scrollDelta!;
        } else if (notification.metrics.axisDirection == AxisDirection.up) {
          _dragOffset = _dragOffset! + notification.scrollDelta!;
        }
        _checkDragOffset(notification.metrics.viewportDimension);
      }
      if (_status == _RefreshStatus.armed && notification.dragDetails == null) {
        _show();
      }
    } else if (notification is OverscrollNotification) {
      if (_status == _RefreshStatus.drag ||
          _status == _RefreshStatus.armed) {
        if (notification.metrics.axisDirection == AxisDirection.down) {
          _dragOffset = _dragOffset! - notification.overscroll;
        } else if (notification.metrics.axisDirection == AxisDirection.up) {
          _dragOffset = _dragOffset! + notification.overscroll;
        }
        _checkDragOffset(notification.metrics.viewportDimension);
      }
    } else if (notification is ScrollEndNotification) {
      switch (_status) {
        case _RefreshStatus.armed:
          if (_positionController.value < 1.0) {
            _dismiss(_RefreshStatus.canceled);
          } else {
            _show();
          }
        case _RefreshStatus.drag:
          _dismiss(_RefreshStatus.canceled);
        case _RefreshStatus.canceled:
        case _RefreshStatus.done:
        case _RefreshStatus.refresh:
        case _RefreshStatus.snap:
        case null:
          break;
      }
    }
    return false;
  }

  bool _handleIndicatorNotification(
      OverscrollIndicatorNotification notification) {
    if (notification.depth != 0 || !notification.leading) {
      return false;
    }
    if (_status == _RefreshStatus.drag) {
      notification.disallowIndicator();
      return true;
    }
    return false;
  }

  bool _start(AxisDirection direction) {
    switch (direction) {
      case AxisDirection.down:
      case AxisDirection.up:
        _isIndicatorAtTop = true;
      case AxisDirection.left:
      case AxisDirection.right:
        _isIndicatorAtTop = null;
        // 不支持横向滚动视图。
        return false;
    }
    _dragOffset = 0.0;
    _scaleController.value = 0.0;
    _positionController.value = 0.0;
    return true;
  }

  void _checkDragOffset(double containerExtent) {
    double newValue = _dragOffset! / (containerExtent * _kDragContainerExtentPercentage);
    if (_status == _RefreshStatus.armed) {
      newValue = math.max(newValue, 1.0 / _kDragSizeFactorLimit);
    }
    _positionController.value = newValue.clamp(0.0, 1.0);
    if (_status == _RefreshStatus.drag &&
        _valueColor.value!.a == _effectiveValueColor.a) {
      _status = _RefreshStatus.armed;
    }
  }

  // 收起指示器。
  Future<void> _dismiss(_RefreshStatus newMode) async {
    await Future<void>.value();
    setState(() {
      _status = newMode;
    });
    switch (_status!) {
      case _RefreshStatus.done:
        await _scaleController.animateTo(1.0, duration: _kIndicatorScaleDuration);
      case _RefreshStatus.canceled:
        await _positionController
            .animateTo(0.0, duration: _kIndicatorScaleDuration);
      case _RefreshStatus.armed:
      case _RefreshStatus.drag:
      case _RefreshStatus.refresh:
      case _RefreshStatus.snap:
        break;
    }
    if (mounted && _status == newMode) {
      _dragOffset = null;
      _isIndicatorAtTop = null;
      setState(() {
        _status = null;
      });
    }
  }

  void _show() {
    final completer = Completer<void>();
    _pendingRefreshFuture = completer.future;
    _status = _RefreshStatus.snap;
    _positionController
        .animateTo(1.0 / _kDragSizeFactorLimit, duration: _kIndicatorSnapDuration)
        .then<void>((void value) {
      if (mounted && _status == _RefreshStatus.snap) {
        setState(() {
          // 切到不定态（旋转）指示器。
          _status = _RefreshStatus.refresh;
        });

        final Future<void> refreshResult = widget.onRefresh();
        refreshResult.whenComplete(() {
          if (mounted && _status == _RefreshStatus.refresh) {
            completer.complete();
            _dismiss(_RefreshStatus.done);
          }
        });
      }
    });
  }

  /// 以编程方式显示指示器并执行刷新回调（与 material `show` 同义）。
  Future<void> show({bool atTop = true}) {
    if (_status != _RefreshStatus.refresh && _status != _RefreshStatus.snap) {
      if (_status == null) {
        _start(atTop ? AxisDirection.down : AxisDirection.up);
      }
      _show();
    }
    return _pendingRefreshFuture;
  }

  @override
  Widget build(BuildContext context) {
    final Widget child = NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: NotificationListener<OverscrollIndicatorNotification>(
        onNotification: _handleIndicatorNotification,
        child: widget.child,
      ),
    );

    final bool showIndeterminateIndicator = _status == _RefreshStatus.refresh ||
        _status == _RefreshStatus.done;

    return Stack(
      children: <Widget>[
        child,
        if (_status != null)
          Positioned(
            top: _isIndicatorAtTop! ? widget.edgeOffset : null,
            bottom: !_isIndicatorAtTop! ? widget.edgeOffset : null,
            left: 0.0,
            right: 0.0,
            child: SizeTransition(
              alignment:
                  AlignmentDirectional(-1.0, _isIndicatorAtTop! ? 1.0 : -1.0),
              sizeFactor: _positionFactor, // 这是把它带下来/上去的量。
              child: Padding(
                padding: _isIndicatorAtTop!
                    ? EdgeInsets.only(top: widget.displacement)
                    : EdgeInsets.only(bottom: widget.displacement),
                child: Align(
                  alignment: _isIndicatorAtTop!
                      ? Alignment.topCenter
                      : Alignment.bottomCenter,
                  child: ScaleTransition(
                    scale: _scaleFactor,
                    child: AnimatedBuilder(
                      animation: _positionController,
                      builder: (BuildContext context, Widget? _) {
                        return _AppRefreshRing(
                          value: showIndeterminateIndicator ? null : _value.value,
                          valueColor: _valueColor,
                          strokeWidth: widget.strokeWidth,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 指示环本体（对齐 material `RefreshProgressIndicator`）。
///
/// `value == null` → 不定态（旋转）；`value != null` → 由拖动进度驱动
/// arc 增长与箭头，并在内部把进度映射进不定态动画时间轴。
class _AppRefreshRing extends StatefulWidget {
  const _AppRefreshRing({
    required this.value,
    required this.valueColor,
    required this.strokeWidth,
  });

  final double? value;
  final Animation<Color?> valueColor;
  final double strokeWidth;

  @override
  State<_AppRefreshRing> createState() => _AppRefreshRingState();
}

class _AppRefreshRingState extends State<_AppRefreshRing>
    with SingleTickerProviderStateMixin {
  static const int _pathCount = _kIndeterminateCircularDuration ~/ 1333;
  static const int _rotationCount = _kIndeterminateCircularDuration ~/ 2222;

  static final Animatable<double> _strokeHeadTween =
      CurveTween(curve: const Interval(0.0, 0.5, curve: Curves.fastOutSlowIn))
          .chain(CurveTween(curve: const SawTooth(_pathCount)));
  static final Animatable<double> _strokeTailTween =
      CurveTween(curve: const Interval(0.5, 1.0, curve: Curves.fastOutSlowIn))
          .chain(CurveTween(curve: const SawTooth(_pathCount)));
  static final Animatable<double> _offsetTween =
      CurveTween(curve: const SawTooth(_pathCount));
  static final Animatable<double> _rotationTween =
      CurveTween(curve: const SawTooth(_rotationCount));

  late final Animatable<double> _convertTween =
      CurveTween(curve: const Interval(0.1, _kStrokeHeadInterval));

  late final Animatable<double> _additionalRotationTween =
      TweenSequence<double>(<TweenSequenceItem<double>>[
    TweenSequenceItem<double>(
      tween: Tween<double>(begin: -0.1, end: -0.2),
      weight: _kStrokeHeadInterval,
    ),
    TweenSequenceItem<double>(
      tween: Tween<double>(begin: -0.2, end: 1.35),
      weight: 1 - _kStrokeHeadInterval,
    ),
  ]);

  late final AnimationController _controller;
  double? _lastValue;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: _kIndeterminateCircularDuration),
      vsync: this,
    );
    _updateAnimatingStatus();
  }

  @override
  void didUpdateWidget(_AppRefreshRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateAnimatingStatus();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateAnimatingStatus() {
    if (widget.value == null && !_controller.isAnimating) {
      _controller.repeat();
    } else if (widget.value != null && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final double? value = widget.value;
    if (value != null) {
      _lastValue = value;
      // 把拖动进度映射到不定态动画时间轴：0..1 拖动 → arc 增长 + 箭头出现。
      _controller.value = _convertTween.transform(value) *
          (1333 / 2 / _kIndeterminateCircularDuration);
    }

    final Color rawColor = widget.valueColor.value ?? const Color(0xFF000000);
    final double opacity = rawColor.a;
    final Color paintedColor = rawColor.withValues(alpha: 1.0);
    final double arrowheadScale = value == null
        ? 0.0
        : const Interval(0.1, _kStrokeHeadInterval).transform(value);
    final double rotation = (value == null && _lastValue == null)
        ? 0.0
        : math.pi * _additionalRotationTween.transform(value ?? _lastValue!);

    final Color surface = MiuixTheme.maybeOf(context)?.colors.surface ??
        _kFallbackSurface;

    return Semantics(
      label: '刷新',
      value: value == null ? null : '${(value * 100).round()}%',
      child: Padding(
        padding: const EdgeInsets.all(_kRingMargin),
        child: SizedBox(
          width: _kRingSize,
          height: _kRingSize,
          child: PhysicalModel(
            shape: BoxShape.circle,
            color: surface,
            elevation: 2.0,
            shadowColor: const Color(0xFF000000),
            clipBehavior: Clip.none,
            child: Padding(
              padding: const EdgeInsets.all(_kRingPadding),
              child: Opacity(
                opacity: opacity,
                child: Transform.rotate(
                  angle: rotation,
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (BuildContext context, Widget? _) {
                      return CustomPaint(
                        painter: _AppRefreshRingPainter(
                          valueColor: paintedColor,
                          // 弧稍长一点，接近 Android 观感。
                          headValue: 1.05 *
                              _strokeHeadTween.transform(_controller.value),
                          tailValue: _strokeTailTween.transform(_controller.value),
                          offsetValue: _offsetTween.transform(_controller.value),
                          rotationValue:
                              _rotationTween.transform(_controller.value),
                          strokeWidth: widget.strokeWidth,
                          arrowheadScale: arrowheadScale,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 环 + 箭头绘制（对齐 material `_RefreshProgressIndicatorPainter`）。
class _AppRefreshRingPainter extends CustomPainter {
  _AppRefreshRingPainter({
    required this.valueColor,
    required this.headValue,
    required this.tailValue,
    required this.offsetValue,
    required this.rotationValue,
    required this.strokeWidth,
    required this.arrowheadScale,
  })  : arcStart = _startAngle +
            tailValue * 3 / 2 * math.pi +
            rotationValue * math.pi * 2.0 +
            offsetValue * 0.5 * math.pi,
        arcSweep = math.max(
            headValue * 3 / 2 * math.pi - tailValue * 3 / 2 * math.pi, _epsilon);

  final Color valueColor;
  final double headValue;
  final double tailValue;
  final double offsetValue;
  final double rotationValue;
  final double strokeWidth;
  final double arrowheadScale;
  final double arcStart;
  final double arcSweep;

  static const double _epsilon = .001;
  static const double _startAngle = -math.pi / 2.0;

  void _paintArrowhead(Canvas canvas, Size size) {
    // ux, uy：与箭头底边平行的单位向量。
    final double arcEnd = arcStart + arcSweep;
    final double ux = math.cos(arcEnd);
    final double uy = math.sin(arcEnd);

    final double radius = size.width / 2.0;
    final double arrowheadPointX =
        radius + ux * radius + -uy * strokeWidth * 2.0 * arrowheadScale;
    final double arrowheadPointY =
        radius + uy * radius + ux * strokeWidth * 2.0 * arrowheadScale;
    final double arrowheadRadius = strokeWidth * 2.0 * arrowheadScale;
    final double innerRadius = radius - arrowheadRadius;
    final double outerRadius = radius + arrowheadRadius;

    final path = Path()
      ..moveTo(radius + ux * innerRadius, radius + uy * innerRadius)
      ..lineTo(radius + ux * outerRadius, radius + uy * outerRadius)
      ..lineTo(arrowheadPointX, arrowheadPointY)
      ..close();

    final paint = Paint()
      ..color = valueColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = valueColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      // 不定态（value == null）且未指定 strokeCap → square（对齐 material）。
      ..strokeCap = StrokeCap.square;

    canvas.drawArc(Offset.zero & size, arcStart, arcSweep, false, paint);

    if (arrowheadScale > 0.0) {
      _paintArrowhead(canvas, size);
    }
  }

  @override
  bool shouldRepaint(_AppRefreshRingPainter oldPainter) {
    return oldPainter.valueColor != valueColor ||
        oldPainter.headValue != headValue ||
        oldPainter.tailValue != tailValue ||
        oldPainter.offsetValue != offsetValue ||
        oldPainter.rotationValue != rotationValue ||
        oldPainter.strokeWidth != strokeWidth ||
        oldPainter.arrowheadScale != arrowheadScale;
  }
}

/// Miuix 库下拉刷新（`MiuixPullToRefresh` 薄封装：中文文案）。
///
/// B7 反馈轮#2：评论区 / 消息中心等"刷新即清列表"的场景改用本组件 ——
/// 下拉反馈 = Miuix 库自身的指示器（圆环 + 状态文案，内容下推），
/// 不再与居中加载环同屏叠加（刷新期间调用方保留现有内容）。
class AppMiuixRefresh extends StatelessWidget {
  const AppMiuixRefresh({
    super.key,
    required this.isRefreshing,
    required this.onRefresh,
    required this.child,
  });

  /// 刷新状态（由调用方提升管理；`onRefresh` 内应尽快置 true）。
  final bool isRefreshing;

  /// 越过阈值松手后回调。
  final VoidCallback onRefresh;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MiuixPullToRefresh(
      isRefreshing: isRefreshing,
      onRefresh: onRefresh,
      refreshTexts: const ['下拉刷新', '释放刷新', '正在刷新…', '刷新完成'],
      child: child,
    );
  }
}