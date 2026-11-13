import 'package:flutter/widgets.dart';

/// 滚动补货门闩：把「距底不足 N 屏」从**每帧条件**改成**跨阈值事件**。
///
/// 背景（2026-11-13 滚动体验轮）：各列表页原先在每次滚动通知里判断
/// `maxScrollExtent - pixels <= 阈值` 后直接请求。用户贴在底部时，
/// 每个滚动帧都会重新命中判断 —— 请求空手而归（服务端去重/失败）时
/// `isLoading` 立刻复位，于是每帧都重发，既是请求风暴，也让加载时机
/// 完全随机（内容忽快忽慢地蹦出来，观感即为「一顿一顿」）。
///
/// 规则：
/// - 从「距底 > [bufferScreens] 屏」跨入「≤ [bufferScreens] 屏」时放行一次；
/// - 放行后保持关闭，直到满足任一条件重新武装：
///   ① 距底超过「[bufferScreens] + [rearmScreens]」屏（用户回滚）；
///   ② 内容总长发生变化（有新批次落地，允许继续补下一批）；
/// - 同一位置连续命中时受 [minInterval] 冷却限制：服务端整批去重（返回 0 条、
///   内容长度不变）后，用户继续滚动仍可重试，但不会每帧重发。
class LoadMoreGate {
  LoadMoreGate({
    this.bufferScreens = 1.0,
    this.rearmScreens = 0.5,
    this.minInterval = const Duration(milliseconds: 450),
  });

  /// 距底多少屏时触发（默认 1 屏，与 [ViewportLoadBudget.shouldLoadMore] 同口径）。
  final double bufferScreens;

  /// 回滚多少屏后重新武装（迟滞带，避免在阈值附近来回抖动时反复请求）。
  final double rearmScreens;

  /// 同一位置的最小请求间隔（去重空批次后的重试节流）。
  final Duration minInterval;

  bool _armed = true;
  double? _lastMaxScrollExtent;
  DateTime? _lastTriggerAt;

  /// 刷新列表时手动复位（清空内容后重新按「未触达底部」处理）。
  void reset() {
    _armed = true;
    _lastMaxScrollExtent = null;
    _lastTriggerAt = null;
  }

  /// 是否应在本帧发起补货。
  bool shouldTrigger(ScrollPosition position) {
    if (!position.hasContentDimensions) return false;

    final maxScrollExtent = position.maxScrollExtent;
    final lastMax = _lastMaxScrollExtent;
    if (lastMax != null && (maxScrollExtent - lastMax).abs() > 0.5) {
      // 内容长度变了（新批次已落地 / 列表被重置）：重新给一次机会。
      _armed = true;
    }
    _lastMaxScrollExtent = maxScrollExtent;

    final triggerDistance = position.viewportDimension * bufferScreens;
    final rearmDistance =
        triggerDistance + position.viewportDimension * rearmScreens;
    final distance = maxScrollExtent - position.pixels;

    if (distance > rearmDistance) {
      _armed = true;
      return false;
    }
    // 严格小于：内容恰好「视口 + 1 屏」时缓冲已满足，不额外请求；
    // 首次进入时若只有一屏（distance == 0）则立即补齐 n+1。
    if (distance >= triggerDistance) return false;
    if (!_armed) return false;

    final now = DateTime.now();
    final last = _lastTriggerAt;
    if (last != null && now.difference(last) < minInterval) return false;

    _lastTriggerAt = now;
    _armed = false;
    return true;
  }
}
