import 'dart:async';

import 'package:flutter/material.dart';

import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/grpc/bilibili/community/service/dm/v1.pb.dart';
import 'package:winwin/pages/danmaku/controller.dart';
import 'package:winwin/pages/danmaku/danmaku_options.dart';
import 'package:winwin/pages/video/player_controller.dart';
import 'package:winwin/plugin/canvas_danmaku/canvas_danmaku.dart';

/// 弹幕 UI 层：叠在视频面之上、控制条之下。
///
/// 职责：
/// - 创建并挂载 [WinWinDanmakuController]（数据侧，cid 维度预载弹幕）；
/// - 将渲染引擎控制器（[DanmakuController]）挂到
///   [WinWinPlayerController.danmakuEngine]，供设置/发送面板使用；
/// - 监听播放器的 position / playing / seekCount / playbackSpeed 与
///   本地回显 localEcho，驱动引擎 addDanmaku / pause / resume / clear /
///   updateOption；
/// - 通过 [AnimatedOpacity] 实现弹幕开关与不透明度（Pref.enableShowDanmaku /
///   Pref.danmakuOpacity）。
class WinWinDanmaku extends StatefulWidget {
  const WinWinDanmaku({
    super.key,
    required this.controller,
    required this.fullscreen,
  });

  final WinWinPlayerController controller;
  final bool fullscreen;

  @override
  State<WinWinDanmaku> createState() => _WinWinDanmakuState();
}

class _WinWinDanmakuState extends State<WinWinDanmaku> {
  /// 记录上次拉取弹幕的时间戳（毫秒），用于跨步范围查询，防止轮询间隔漏投。
  int _lastProgressMs = -1;

  /// 最近一次已上屏的本地回显，防止重复 add。
  DanmakuContentItem<DanmakuElem>? _lastLocal;

  @override
  void initState() {
    super.initState();
    _initDanmaku();
    widget.controller.danmakuReloadSignal.addListener(_onReload);
  }

  /// 创建弹幕数据控制器并挂载监听。
  /// 提取为独立方法供 initState 和 _onReload（路由返回重建）复用。
  void _initDanmaku() {
    final c = widget.controller;
    final dm = WinWinDanmakuController(cid: c.cid);
    c.danmaku = dm;
    unawaited(dm.preload());

    c.position.addListener(_onPosition);
    c.playing.addListener(_onPlaying);
    c.seekCount.addListener(_onSeek);
    dm.localEcho.addListener(_onLocalEcho);

    // 初始同步一次运行状态（引擎默认 running）。
    _onPlaying();
  }

  /// didPopNext 返回本页时重建弹幕：dispose 旧 dm（清空缓存重新拉取）+
  /// clear 引擎 + 重置去重标记。等效于 PiliPlus 重建 PlDanmaku，但不需要
  /// 销毁 DanmakuScreen（避免引擎闪烁）。
  void _onReload() {
    final c = widget.controller;
    // 移除旧 dm 的监听并 dispose。
    c.position.removeListener(_onPosition);
    c.playing.removeListener(_onPlaying);
    c.seekCount.removeListener(_onSeek);
    c.danmaku?.localEcho.removeListener(_onLocalEcho);
    c.danmaku?.dispose();
    // 清空引擎画面上的残留弹幕，重置去重标记。
    c.danmakuEngine?.clear();
    _lastProgressMs = -1;
    _lastLocal = null;
    // 重建 dm 并重新挂载监听。
    _initDanmaku();
  }

  @override
  void didUpdateWidget(WinWinDanmaku oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fullscreen != widget.fullscreen) {
      widget.controller.danmakuEngine?.updateOption(
        DanmakuOptions.get(
          fullscreen: widget.fullscreen,
          speed: widget.controller.playbackSpeed.value,
        ),
      );
    }
  }

  @override
  void dispose() {
    final c = widget.controller;
    // 总是移除监听器，即使 controller 已销毁
    // 因为 ValueNotifier 仍然存在，只是不再变化
    c.danmakuReloadSignal.removeListener(_onReload);
    c.position.removeListener(_onPosition);
    c.playing.removeListener(_onPlaying);
    c.seekCount.removeListener(_onSeek);
    c.danmaku?.localEcho.removeListener(_onLocalEcho);
    c.danmaku?.dispose();
    c.danmaku = null;
    c.danmakuEngine = null;
    super.dispose();
  }

  // ── 监听 ──

  /// 进度推进：按时间区间跨步提取应上屏的弹幕逐条交给引擎。
  void _onPosition() {
    final c = widget.controller;
    final dm = c.danmaku;
    final engine = c.danmakuEngine;
    if (dm == null || engine == null || dm.danmakuClosed) return;
    final ms = c.position.value.inMilliseconds;
    if (_lastProgressMs < 0 || (ms - _lastProgressMs).abs() > 1500) {
      _lastProgressMs = ms - 100;
    }
    final items = dm.getDanmakuRange(_lastProgressMs + 100, ms);
    _lastProgressMs = ms;
    for (final item in items) {
      engine.addDanmaku(item);
    }
  }

  /// 自己发送的弹幕：本地回显立即上屏。
  void _onLocalEcho() {
    final item = widget.controller.danmaku?.localEcho.value;
    if (item == null || identical(item, _lastLocal)) return;
    _lastLocal = item;
    widget.controller.danmakuEngine?.addDanmaku(item);
  }

  /// 播放/暂停联动引擎动画。
  void _onPlaying() {
    final c = widget.controller;
    if (c.playing.value) {
      c.danmakuEngine?.resume();
    } else {
      c.danmakuEngine?.pause();
    }
  }

  /// seek 后清空画面上的弹幕，并重置去重标记以便新进度立即补给。
  void _onSeek() {
    _lastProgressMs = -1;
    _lastLocal = null;
    widget.controller.danmakuEngine?.clear();
  }

  // ── build ──

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    // 安全检查：controller 已销毁时不渲染
    if (c.disposed) return const SizedBox.shrink();
    return IgnorePointer(
      child: ValueListenableBuilder<double>(
        valueListenable: c.danmakuOpacity,
        builder: (context, opacity, _) {
          // 再次检查，防止在 builder 执行期间 controller 被销毁
          if (c.disposed) return const SizedBox.shrink();
          return AnimatedOpacity(
            opacity: Pref.enableShowDanmaku
                ? opacity.clamp(0.0, 1.0).toDouble()
                : 0.0,
            duration: const Duration(milliseconds: 200),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(
                  constraints.maxWidth.isFinite ? constraints.maxWidth : 0,
                  constraints.maxHeight.isFinite ? constraints.maxHeight : 0,
                );
                return DanmakuScreen<DanmakuElem>(
                  createdController: (engine) => c.danmakuEngine = engine,
                  option: DanmakuOptions.get(
                    fullscreen: widget.fullscreen,
                    speed: c.playbackSpeed.value,
                  ),
                  size: size,
                );
              },
            ),
          );
        },
      ),
    );
  }
}
