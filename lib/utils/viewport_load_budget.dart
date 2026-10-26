import 'dart:math' as math;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';

import 'package:winwin/core/shell/scaled_widgets_flutter_binding.dart';

/// 视口加载预算 —— 全库滚动分页页面的统一取数口径。
///
/// 约束（2026-10-27）：
/// - **冷启动首批**：最多取「当前视口可容纳条数 × 2」（当前视图 + 额外一倍）；
/// - **滚动补批**：每次最多取「当前视口可容纳条数 × 1」；
/// - **触发时机**：距底不足 1 屏时才补货（[shouldLoadMore]）；
/// - 页面原有的页大小更小时取更小值：本工具**只收紧、不放大**。
///
/// 服务端固定批量的接口（动态流、回复/艾特/点赞消息、App 推荐）无法调小每批
/// 条数，只能保证「单批在途 + 达到触发阈值才请求」，不额外并发多批。
abstract final class ViewportLoadBudget {
  /// 读不到窗口尺寸时的兜底逻辑高度（桌面默认窗口附近）。
  static const double fallbackWindowHeight = 720;

  /// 读不到窗口尺寸时的兜底逻辑宽度。
  static const double fallbackWindowWidth = 1280;

  /// 单屏行数上限：防止超长窗口把预算放大到不合理的数量。
  static const int maxRowsPerViewport = 20;

  /// 当前窗口逻辑高度（已按「界面缩放」换算，与 MediaQuery 同坐标系）。
  static double get windowLogicalHeight {
    final view = PlatformDispatcher.instance.implicitView;
    if (view == null) return fallbackWindowHeight;
    final scaled = ScaledWidgetsFlutterBinding.maybeInstance?.devicePixelRatioScaled;
    final dpr = (scaled != null && scaled > 0) ? scaled : view.devicePixelRatio;
    if (dpr <= 0) return fallbackWindowHeight;
    final height = view.physicalSize.height / dpr;
    return (height.isFinite && height > 0) ? height : fallbackWindowHeight;
  }

  /// 当前窗口逻辑宽度。
  static double get windowLogicalWidth {
    final view = PlatformDispatcher.instance.implicitView;
    if (view == null) return fallbackWindowWidth;
    final scaled = ScaledWidgetsFlutterBinding.maybeInstance?.devicePixelRatioScaled;
    final dpr = (scaled != null && scaled > 0) ? scaled : view.devicePixelRatio;
    if (dpr <= 0) return fallbackWindowWidth;
    final width = view.physicalSize.width / dpr;
    return (width.isFinite && width > 0) ? width : fallbackWindowWidth;
  }

  /// 解析当前滚动视口高度：已布局时用真实 [ScrollPosition.viewportDimension]，
  /// 否则回退到「窗口高度 − 页面固定占位高度」。
  static double viewportExtentOf(
    ScrollController? controller, {
    double reservedHeight = 0,
  }) {
    if (controller != null && controller.hasClients) {
      final position = controller.position;
      if (position.hasViewportDimension && position.viewportDimension > 0) {
        return position.viewportDimension;
      }
    }
    final fallback = windowLogicalHeight - reservedHeight;
    return fallback > 0 ? fallback : windowLogicalHeight;
  }

  /// 视口可容纳的最大行数。
  static int visibleRows({
    required double viewportExtent,
    required double rowExtent,
    int min = 1,
    int max = maxRowsPerViewport,
  }) {
    if (rowExtent <= 0) return min;
    final rows = (viewportExtent / rowExtent).floor();
    return rows.clamp(min, max);
  }

  /// 网格列数（与 SliverGridDelegateWithExtentAndRatio 的 ceil 口径一致）。
  static int gridColumns({
    required double viewportWidth,
    required double maxCrossAxisExtent,
  }) {
    if (maxCrossAxisExtent <= 0) return 1;
    return math.max(1, (viewportWidth / maxCrossAxisExtent).ceil());
  }

  /// 网格视口可容纳的最大条目数（行 × 列）。
  static int visibleGridItems({
    required double viewportExtent,
    required double viewportWidth,
    required double rowExtent,
    required double maxCrossAxisExtent,
  }) =>
      visibleRows(viewportExtent: viewportExtent, rowExtent: rowExtent) *
      gridColumns(
        viewportWidth: viewportWidth,
        maxCrossAxisExtent: maxCrossAxisExtent,
      );

  /// 请求条数上限：冷启动首批 2 屏、滚动补批 1 屏；只收紧、不放大。
  static int capRequestItems({
    required int fallback,
    required int visibleItems,
    required bool firstPage,
  }) {
    final safeFallback = fallback < 1 ? 1 : fallback;
    final safeVisible = visibleItems < 1 ? 1 : visibleItems;
    final budget = firstPage ? safeVisible * 2 : safeVisible;
    return budget < safeFallback ? budget : safeFallback;
  }

  /// 列表页单页条数上限的便捷入口：按行高估算一屏行数后再收敛。
  static int pageSizeFor({
    required int fallback,
    required double rowExtent,
    required bool firstPage,
    ScrollController? controller,
    double reservedHeight = 0,
  }) {
    final visible = visibleRows(
      viewportExtent: viewportExtentOf(
        controller,
        reservedHeight: reservedHeight,
      ),
      rowExtent: rowExtent,
    );
    return capRequestItems(
      fallback: fallback,
      visibleItems: visible,
      firstPage: firstPage,
    );
  }

  /// 距底不足 [bufferScreens] 屏时返回 true（默认 1 屏）。
  ///
  /// 只允许在当前视图之外再预取约一屏，避免滚动时把后面多屏内容提前拉回。
  static bool shouldLoadMore(
    ScrollPosition position, {
    double bufferScreens = 1.0,
  }) {
    if (!position.hasContentDimensions) return false;
    return position.maxScrollExtent - position.pixels <=
        position.viewportDimension * bufferScreens;
  }
}
