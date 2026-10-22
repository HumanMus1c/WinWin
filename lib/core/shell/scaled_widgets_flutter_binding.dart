import 'dart:async' show scheduleMicrotask;
import 'dart:collection' show Queue;
import 'dart:ui' show PointerDataPacket;

import 'package:flutter/gestures.dart' show PointerEventConverter;
import 'package:flutter/rendering.dart' show RenderView, ViewConfiguration;
import 'package:flutter/widgets.dart';

/// 支持「界面缩放」的自定义 Binding（**移植自上游 PiliPlus** 的
/// `lib/common/widgets/scale_app.dart`，其又 adapted from `scaled_app`）。
///
/// 与 WinWin 曾失效的「方案 A（`Transform.scale` 整树绘制缩放）」不同：本方案在
/// **渲染层**把 [RenderView] 的 `devicePixelRatio` 乘以 `_scaleFactor`，于是
/// 逻辑尺寸（`logicalConstraints = physicalConstraints / devicePixelRatioScaled`）
/// 随缩放变化 ⇒ **整棵树（含 `Overlay` / 弹层 / 自绘标题栏 / 窗口级参照）
/// 共享同一坐标空间**，天然一致。
///
/// 关键点（缺任一处即会坐标错配）：
/// 1. [createViewConfigurationFor]：改写 `devicePixelRatio` 与逻辑约束；
/// 2. [initInstances]：接管 `platformDispatcher.onPointerDataPacket`，指针数据用
///    **缩放后的 DPR** 转换（否则 `GestureBinding` 仍用未缩放的
///    `implicitView.devicePixelRatio` 计算命中测试 → 点击错位）；
/// 3. [scaleFactor] setter → [handleMetricsChanged] 触发布局重建（**热生效**）。
///
/// 与 `MediaQuery` 的协同（见 `core/shell/app_shell.dart`）：binding 改真实渲染
/// DPR，MediaQuery 需以同比例同步（`size / scale` 且 `dpr * scale`），二者一致
/// 后弹层锚定、命中测试才正确。
class ScaledWidgetsFlutterBinding extends WidgetsFlutterBinding {
  ScaledWidgetsFlutterBinding._(this._scaleFactor);

  /// 界面缩放比例（1.0 = 原始）。由「界面缩放」设置项驱动。
  double _scaleFactor;

  /// 更新缩放比例并**触发布局重建**（热生效）。
  set scaleFactor(double scaleFactor) {
    if (_scaleFactor == scaleFactor) return;
    _scaleFactor = scaleFactor;
    handleMetricsChanged();
  }

  /// 缩放后的真实渲染 `devicePixelRatio`（`原始 dpr × _scaleFactor`）。
  ///
  /// 指针转换（[_devicePixelRatioForView]）依赖此值，故它必须与
  /// [createViewConfigurationFor] 计算出的 `devicePixelRatio` 保持一致。
  double devicePixelRatioScaled = 0;

  static ScaledWidgetsFlutterBinding? _binding;

  /// 已初始化的实例；未初始化时为 null（供不持有 binding 的调用点安全取用）。
  static ScaledWidgetsFlutterBinding? get maybeInstance => _binding;

  static ScaledWidgetsFlutterBinding get instance => _binding!;

  /// 初始化自定义 Binding（替代 `WidgetsFlutterBinding.ensureInitialized()`）。
  ///
  /// **必须**在任何 Binding 使用与 `runApp` 之前调用。
  static WidgetsBinding ensureInitialized({double scaleFactor = 1.0}) =>
      _binding ??= ScaledWidgetsFlutterBinding._(scaleFactor);

  /// 覆写 [RendererBinding.createViewConfiguration]：把渲染 `devicePixelRatio`
  /// 乘以 [scaleFactor]，逻辑约束随之缩小。
  ///
  /// 参见 [RendererBinding.createViewConfiguration]。
  @override
  ViewConfiguration createViewConfigurationFor(RenderView renderView) {
    final view = renderView.flutterView;
    final devicePixelRatio = view.devicePixelRatio;
    devicePixelRatioScaled = devicePixelRatio * _scaleFactor;
    final BoxConstraints physicalConstraints =
        BoxConstraints.fromViewConstraints(view.physicalConstraints);
    return ViewConfiguration(
      physicalConstraints: physicalConstraints,
      logicalConstraints: physicalConstraints / devicePixelRatioScaled,
      devicePixelRatio: devicePixelRatioScaled,
    );
  }

  /// 接管指针数据包（Adapted from [GestureBinding.initInstances]）。
  ///
  /// 缩放后 `ui.window`/`FlutterView` 本身不变，而 [GestureBinding] 会使用
  /// 未缩放的 `implicitView.devicePixelRatio` 换算指针坐标 ⇒ 必须改为
  /// [_devicePixelRatioForView]（缩放后的 DPR），命中测试/手势坐标才与渲染一致。
  @override
  void initInstances() {
    super.initInstances();
    platformDispatcher.onPointerDataPacket = _handlePointerDataPacket;
  }

  @override
  void unlocked() {
    super.unlocked();
    _flushPointerEventQueue();
  }

  final Queue<PointerEvent> _pendingPointerEvents = Queue<PointerEvent>();

  void _handlePointerDataPacket(PointerDataPacket packet) {
    // 将指针数据换算为逻辑像素（如 touch slop 定义与设备无关）。
    try {
      _pendingPointerEvents.addAll(
        PointerEventConverter.expand(packet.data, _devicePixelRatioForView),
      );
      if (!locked) {
        _flushPointerEventQueue();
      }
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'gestures library',
          context: ErrorDescription('while handling a pointer data packet'),
        ),
      );
    }
  }

  double _devicePixelRatioForView(int viewId) => devicePixelRatioScaled;

  /// 尽快为该指针派发一个 [PointerCancelEvent]。
  @override
  void cancelPointer(int pointer) {
    if (_pendingPointerEvents.isEmpty && !locked) {
      scheduleMicrotask(_flushPointerEventQueue);
    }
    _pendingPointerEvents.addFirst(PointerCancelEvent(pointer: pointer));
  }

  void _flushPointerEventQueue() {
    assert(!locked);

    while (_pendingPointerEvents.isNotEmpty) {
      handlePointerEvent(_pendingPointerEvents.removeFirst());
    }
  }
}