import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/widgets.dart';

/// 滚轮平滑滚动参数（单一来源）。
///
/// 背景：SDK 的 [ScrollPosition.pointerScroll] 对滚轮是**立即** `forcePixels`
/// （`scroll_position_with_single_context.dart`），即「一个刻度 = 一次硬跳」。
/// Flutter 的 [ScrollBehavior] 只开放 `buildScrollbar / buildOverscrollIndicator /
/// getScrollPhysics`，没有滚轮钩子；而 `buildScrollbar` 的产物包在 `Scrollable`
/// 自身的 Listener **外层**，因此 [AppScrollBar] 也拦不到内容区滚轮。
/// 官方留出的唯一干净扩展点是 [ScrollController.createScrollPosition]，故在此
/// 用自定义 [ScrollPosition] 接管滚轮，零三方依赖。
abstract final class AppScrollTuning {
  /// 小于该位移的滚轮事件视为触控板 / 高精度输入：直接跟手，不做补间。
  ///
  /// 触控板事件高频且步长小，再叠补间会变成「拖着走」的延迟感；
  /// 鼠标滚轮单刻度通常是几十像素，才需要动画。
  static const double trackpadDeltaThreshold = 24;

  /// 补间时长系数（毫秒 / 像素）。
  ///
  /// 单刻度（约 50px）≈ 110ms，接近 Chrome / VS Code 的滚轮手感。
  static const double msPerPixel = 2.2;

  /// 单次补间的时长下限 / 上限。
  static const int minDurationMs = 90;
  static const int maxDurationMs = 260;
}

/// 页面级滚动控制器：把滚轮从「硬跳」换成「按距离补间」的平滑滚动。
///
/// 只影响 [ScrollPositionWithSingleContext.pointerScroll]（滚轮 / 触控板），
/// 拖拽、惯性、下拉刷新、键盘翻页全部沿用 SDK 原行为。
class AppScrollController extends ScrollController {
  AppScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
  });

  /// 滚轮已到边界仍继续向外滚时的回调（可选）。
  ///
  /// 用于 `NestedScrollView` 两段式协调：内层到顶继续上滚时，由宿主把
  /// 增量转给外层头部（展开），否则内层会静默吞掉该事件。
  /// 参数为原始滚轮增量（负值 = 继续向上）。
  void Function(double delta)? onScrollAtEdge;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return AppScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
      owner: this,
    );
  }
}

/// 带滚轮补间的滚动位置。
class AppScrollPosition extends ScrollPositionWithSingleContext {
  AppScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
    this.owner,
  });

  /// 创建本位置的控制器（读取边界回调用）。
  final AppScrollController? owner;

  /// 连续滚轮事件的目标位置：动画途中再滚时从**目标**继续加，
  /// 而不是从当前像素重新起算（后者会让连滚变成一格一格地追）。
  double? _wheelTarget;

  /// 动画世代号：只有最新一次补间完成时才允许清理 [_wheelTarget]。
  int _wheelGeneration = 0;

  @override
  void pointerScroll(double delta) {
    if (delta == 0.0) {
      // `PointerScrollInertiaCancelEvent`：取消触控板惯性。
      _wheelTarget = null;
      goBallistic(0.0);
      return;
    }

    if (delta.abs() < AppScrollTuning.trackpadDeltaThreshold) {
      _wheelTarget = null;
      super.pointerScroll(delta);
      return;
    }

    final base = _wheelTarget ?? pixels;
    final target = (base + delta).clamp(minScrollExtent, maxScrollExtent);
    _wheelTarget = target;

    // 到达边界后继续向外滚：交给宿主协调（如 NestedScrollView 展开外层头部）。
    final atMin = pixels <= minScrollExtent + 0.5;
    final atMax = pixels >= maxScrollExtent - 0.5;
    final outward =
        (delta < 0 && atMin && target <= minScrollExtent + 0.5) ||
            (delta > 0 && atMax && target >= maxScrollExtent - 0.5);
    if (outward && owner?.onScrollAtEdge != null) {
      owner!.onScrollAtEdge!(delta);
      return;
    }

    final distance = (target - pixels).abs();
    if (distance < 0.5) return;

    // 与基类 pointerScroll 同口径：pixels 增大 = 内容向上走 = reverse。
    updateUserScrollDirection(
      delta > 0 ? ScrollDirection.forward : ScrollDirection.reverse,
    );

    final ms = (distance * AppScrollTuning.msPerPixel)
        .clamp(
          AppScrollTuning.minDurationMs.toDouble(),
          AppScrollTuning.maxDurationMs.toDouble(),
        )
        .round();
    final generation = ++_wheelGeneration;
    animateTo(
      target,
      duration: Duration(milliseconds: ms),
      curve: Curves.easeOutCubic,
    ).whenComplete(() {
      if (generation == _wheelGeneration) _wheelTarget = null;
    });
  }

  @override
  void jumpTo(double value) {
    // 程序化跳转（回顶、定位、滚动条拖拽）视为用户意图切换，丢弃滚轮续追目标。
    _wheelTarget = null;
    super.jumpTo(value);
  }

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    final result = super.applyContentDimensions(minScrollExtent, maxScrollExtent);
    // 内容尺寸变化（加载更多 / footer 切换）时收敛在途目标，避免越界补间。
    final target = _wheelTarget;
    if (target != null) {
      _wheelTarget = target.clamp(minScrollExtent, maxScrollExtent);
    }
    return result;
  }
}
