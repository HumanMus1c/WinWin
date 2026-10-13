import 'package:flutter/widgets.dart';

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

  /// 当前 State 绑定的渲染引擎实例。
  DanmakuController<DanmakuElem>? _engine;

  /// 当前绑定的弹幕数据控制器缓存。
  WinWinDanmakuController? _dm;

  @override
  void initState() {
    super.initState();
    _bindController();
  }

  /// 绑定数据控制器与播放器信号监听。
  void _bindController() {
    final c = widget.controller;
    final dm = c.getOrCreateDanmaku();
    _dm = dm;

    c.danmakuReloadSignal.addListener(_onReload);
    c.position.addListener(_onPosition);
    c.playing.addListener(_onPlayingOrBuffering);
    c.buffering.addListener(_onPlayingOrBuffering);
    c.seekCount.addListener(_onSeek);
    dm.localEcho.addListener(_onLocalEcho);
    dm.danmakuLoadedSignal.addListener(_onDanmakuLoaded);

    // 初始同步一次运行状态（引擎就绪后会再次对齐）。
    _onPlayingOrBuffering();
  }

  /// 解除播放器信号与数据控制器的监听。
  void _unbindController() {
    final c = widget.controller;
    c.danmakuReloadSignal.removeListener(_onReload);
    c.position.removeListener(_onPosition);
    c.playing.removeListener(_onPlayingOrBuffering);
    c.buffering.removeListener(_onPlayingOrBuffering);
    c.seekCount.removeListener(_onSeek);
    _dm?.localEcho.removeListener(_onLocalEcho);
    _dm?.danmakuLoadedSignal.removeListener(_onDanmakuLoaded);
    _dm = null;
  }

  /// didPopNext 返回本页时重建弹幕：清空引擎画面与去重标记，重新对齐。
  void _onReload() {
    _unbindController();
    _engine?.clear();
    widget.controller.danmakuEngine?.clear();
    _lastProgressMs = -1;
    _lastLocal = null;
    _bindController();
  }

  @override
  void didUpdateWidget(WinWinDanmaku oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _unbindController();
      _lastProgressMs = -1;
      _lastLocal = null;
      _bindController();
    }
    if (oldWidget.fullscreen != widget.fullscreen) {
      final opt = DanmakuOptions.get(
        fullscreen: widget.fullscreen,
        speed: widget.controller.playbackSpeed.value,
      );
      _engine?.updateOption(opt);
      widget.controller.danmakuEngine?.updateOption(opt);
    }
  }

  @override
  void dispose() {
    _unbindController();
    // 仅当当前全局挂载的 engine 仍是本 State 创建的 engine 时才解挂，
    // 避免新 State 已经挂载了新 engine 后被旧 State 的 dispose 覆盖置空！
    if (identical(widget.controller.danmakuEngine, _engine)) {
      widget.controller.danmakuEngine = null;
    }
    _engine = null;
    // 严禁在此处调用 c.danmaku?.dispose() 或置空 c.danmaku！
    // 弹幕数据控制器的生命周期完全属于 WinWinPlayerController（cid 会话维度）。
    super.dispose();
  }

  // ── 监听 ──

  /// 进度推进：按时间区间跨步提取应上屏的弹幕逐条交给引擎（对标 PiliPlus videoPositionListen）。
  void _onPosition() {
    final c = widget.controller;
    final dm = _dm ?? c.danmaku;
    final engine = _engine ?? c.danmakuEngine;
    if (dm == null || engine == null || dm.danmakuClosed) return;
    final int rawMs = c.position.value.inMilliseconds;
    final int currentBucket = rawMs - (rawMs % 100);
    if (currentBucket == _lastProgressMs) return;

    final List<DanmakuContentItem<DanmakuElem>> items;
    if (_lastProgressMs < 0 || (currentBucket - _lastProgressMs).abs() > 1500) {
      _lastProgressMs = currentBucket;
      items = dm.getCurrentDanmaku(currentBucket);
    } else {
      items = dm.getDanmakuRange(_lastProgressMs + 100, currentBucket);
      _lastProgressMs = currentBucket;
    }

    if (items.isEmpty) return;

    // 突发高密弹幕削峰保护：单周期（100ms）限制最多投递 30 条弹幕，
    // 避免网络回包或瞬态时间跳跃时数十条弹幕扎堆同步布局排版引发 UI 线程掉帧。
    final toAdd = items.length > 30 ? items.sublist(items.length - 30) : items;
    for (final item in toAdd) {
      engine.addDanmaku(item);
    }
  }

  /// 自己发送的弹幕：本地回显立即上屏。
  void _onLocalEcho() {
    final dm = _dm ?? widget.controller.danmaku;
    final engine = _engine ?? widget.controller.danmakuEngine;
    final item = dm?.localEcho.value;
    if (item == null || identical(item, _lastLocal)) return;
    _lastLocal = item;
    engine?.addDanmaku(item);
  }

  /// 播放/暂停与缓冲状态联动引擎动画：缓冲中或暂停时冻结，正常播放时恢复。
  void _onPlayingOrBuffering() {
    final c = widget.controller;
    final engine = _engine ?? c.danmakuEngine;
    if (c.playing.value && !c.buffering.value) {
      engine?.resume();
    } else {
      engine?.pause();
    }
  }

  /// 弹幕段（6分钟）数据加载到达：重置上次分桶标记，立即按当前进度补投。
  void _onDanmakuLoaded() {
    _lastProgressMs = -1;
    _onPosition();
  }

  /// seek 后清空画面上的弹幕，并重置去重标记以便新进度立即补给。
  void _onSeek() {
    _lastProgressMs = -1;
    _lastLocal = null;
    _engine?.clear();
    widget.controller.danmakuEngine?.clear();
  }

  // ── build ──

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    // 安全检查：controller 已销毁时不渲染
    if (c.disposed) return const SizedBox.shrink();
    return RepaintBoundary(
      child: ClipRect(
        child: IgnorePointer(
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
                    createdController: (engine) {
                      _engine = engine;
                      c.danmakuEngine = engine;
                      _onPlayingOrBuffering();
                      _onPosition();
                    },
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
      ),
    ),
  );
}
}
