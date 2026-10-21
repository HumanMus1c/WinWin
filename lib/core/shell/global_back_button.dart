import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart' show MiuixIconButton;

import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/theme/app_colors.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/ui/components/app_tooltip.dart';

/// 全局返回按钮控制器的**应用级单例**。
///
/// 由 `main.dart` 在 `navigatorObservers` 中注册，并传给 `AppShell`（壳层据此渲染
/// 单实例按钮）；各页面/组件直接用本单例登记规格（[BackButtonOwner]）。
final GlobalBackButtonController appBackButtonController =
    GlobalBackButtonController();

/// 单个页面（路由）向「全局返回按钮」声明的展示规格。
///
/// 背景：项目自 2026-10-21 起把返回按钮**上提为壳层单实例**（见
/// [GlobalBackButton]）——它挂在 Navigator **之上**，因此：
/// - 不再属于任何页面路由子树，**不跟随页面转场动画**进出；
/// - 只在栈深 ≥ 2（可返回）且返回根页面时显隐；
/// - **位置固定**（默认位，见 [GlobalBackButton.defaultLeft] / [defaultTop]）。
///
/// 页面若需要覆盖默认观感/行为（覆盖在媒体上的反色、无底色、退出全屏、
/// 返回前置副作用等），通过 [BackButtonOwner] 声明一份本规格即可；
/// **不需要任何定制**的标准页无需声明，壳层按 [BackButtonSpec] 默认值渲染。
class BackButtonSpec {
  const BackButtonSpec({
    this.visible = true,
    this.icon,
    this.color,
    this.background,
    this.shadows,
    this.iconSize = 22,
    this.ringShadow,
    this.tooltip,
    this.onPressed,
    this.onBeforePop,
  });

  /// 是否显示（false = 本页不显示全局返回按钮，如播放器全屏时另有片内控件）。
  final bool visible;

  /// 图标字形；null = 自动（[PageRoute.fullscreenDialog] 路由渲染「关闭」，否则「返回」）。
  final IconData? icon;

  /// 图标颜色；null = 取当前 Token 的 `onSurfaceVariant`。
  final Color? color;

  /// 按钮底色；null = 取当前 Token 的 `surfaceContainerHighest`（0.92）。
  /// 传 [AppColors.transparent] 可得到无底色（仅字形，用于覆盖在媒体上）。
  final Color? background;

  /// 字形对比度阴影（覆盖在视频/封面等媒体上时使用）。
  final List<Shadow>? shadows;

  /// 图标字形尺寸（外框恒定为 42，保证固定位不漂移）。
  final double iconSize;

  /// 是否绘制外圈柔和阴影（可辨识底衬）。null = 自动（无自定义底色时为 true）。
  final bool? ringShadow;

  /// 悬浮提示；null = 自动（「返回」/「关闭」）。
  final String? tooltip;

  /// 完全自定义点击行为；提供后不再自动 `maybePop`。
  final VoidCallback? onPressed;

  /// 返回前副作用（在统一 `maybePop` 之前执行，如暂停播放器）。
  final VoidCallback? onBeforePop;

  /// 默认规格（标准页返回按钮：Token 底色 + 环形阴影 + 自动字形）。
  static const BackButtonSpec standard = BackButtonSpec();

  /// 隐藏规格。
  static const BackButtonSpec hidden = BackButtonSpec(visible: false);

  @override
  bool operator ==(Object other) =>
      other is BackButtonSpec &&
      other.visible == visible &&
      other.icon == icon &&
      other.color == color &&
      other.background == background &&
      _sameShadows(other.shadows, shadows) &&
      other.iconSize == iconSize &&
      other.ringShadow == ringShadow &&
      other.tooltip == tooltip &&
      other.onPressed == onPressed &&
      other.onBeforePop == onBeforePop;

  @override
  int get hashCode => Object.hash(
        visible,
        icon,
        color,
        background,
        shadows?.length,
        iconSize,
        ringShadow,
        tooltip,
        onPressed,
        onBeforePop,
      );

  static bool _sameShadows(List<Shadow>? a, List<Shadow>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// 全局返回按钮控制器：**路由栈观察者** + **每路由规格注册表**（单一来源）。
///
/// 作为 [NavigatorObserver] 注册进根 Navigator 的 `navigatorObservers`
/// （见 `main.dart`），维护当前路由栈；同时收纳各页面声明的 [BackButtonSpec]。
/// 壳层单实例按钮 [GlobalBackButton] 监听本对象，据此决定显隐与观感。
class GlobalBackButtonController extends NavigatorObserver with ChangeNotifier {
  GlobalBackButtonController();

  final List<Route<dynamic>> _routes = <Route<dynamic>>[];
  final Map<Route<dynamic>, BackButtonSpec> _specs =
      <Route<dynamic>, BackButtonSpec>{};

  bool _notifyScheduled = false;

  /// 当前路由栈顶（无路由时为 null）。
  Route<dynamic>? get topRoute => _routes.isEmpty ? null : _routes.last;

  /// 是否可返回（栈深 ≥ 2）。
  bool get canPop => _routes.length > 1;

  /// 栈顶是否为路由级弹层（对话框 / 底部弹层 / 菜单 / 下拉）。
  ///
  /// 弹层在最上层时，返回按钮**让位隐藏**——否则它会浮在弹层遮罩之上，
  /// 既视觉突兀又不可点（真实语义已在弹层自身）。
  bool get hasPopupOnTop => _routes.isNotEmpty && _routes.last is PopupRoute;

  /// 当前栈顶路由生效的规格（无声明时取 [BackButtonSpec.standard]）。
  BackButtonSpec get spec {
    final Route<dynamic>? route = topRoute;
    if (route == null) return BackButtonSpec.standard;
    return _specs[route] ?? BackButtonSpec.standard;
  }

  /// 壳层返回按钮是否应可见。
  bool get visible => canPop && !hasPopupOnTop && spec.visible;

  /// 当前路由是否为全屏对话框式页面路由（自动渲染「关闭」字样）。
  bool get isFullscreenDialogRoute {
    final Route<dynamic>? route = topRoute;
    return route is PageRoute<dynamic> && route.fullscreenDialog;
  }

  /// 登记/更新某路由的返回按钮规格。
  void setSpec(Route<dynamic> route, BackButtonSpec spec) {
    if (_specs[route] == spec) return;
    _specs[route] = spec;
    _scheduleNotify();
  }

  /// 注销某路由的规格（页面 dispose 时调用）。
  void removeSpec(Route<dynamic> route) {
    if (_specs.remove(route) != null) _scheduleNotify();
  }

  /// 合并同一帧内的多次变更，并在**安全时机**通知（避免构建/布局期间触发重建）。
  void _scheduleNotify() {
    if (_notifyScheduled) return;
    final SchedulerPhase phase = SchedulerBinding.instance.schedulerPhase;
    final bool inFrame = phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks;
    if (!inFrame) {
      notifyListeners();
      return;
    }
    _notifyScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      notifyListeners();
    });
  }

  void _markRouteChanged() => _scheduleNotify();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _markRouteChanged();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _markRouteChanged();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _markRouteChanged();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute == null) return;
    final int index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      _routes[index] = newRoute;
    } else {
      _routes.add(newRoute);
    }
    if (oldRoute != null && _specs.containsKey(oldRoute)) {
      _specs[newRoute] = _specs.remove(oldRoute)!;
    }
    _markRouteChanged();
  }
}

/// 壳层单实例返回按钮（全局唯一）。
///
/// 挂在 `AppShell.builder` 内、Navigator **之上**（同层于 `AppEscapeScope`），
/// 叠加在路由内容之上但**不属于任何路由子树** ⇒ 转场动画带不走它。
///
/// 位置**固定**（[defaultLeft] / [defaultTop]，对齐标准页顶部安全行内的悬浮位），
/// 显隐只做**淡入淡出**（不位移）；隐藏时不吸事件。
class GlobalBackButton extends StatelessWidget {
  const GlobalBackButton({super.key, required this.controller});

  final GlobalBackButtonController controller;

  /// 默认左边距（对外框定位）。
  static const double defaultLeft = 8;

  /// 默认上边距（= 50 高安全行内居中 42×42 按钮：`(50 - 42) / 2`）。
  static const double defaultTop = 4;

  /// 外框尺寸（恒定，保证固定位不漂移）。
  static const double boxSize = 42;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: defaultLeft,
      top: defaultTop,
      child: ListenableBuilder(
        listenable: controller,
        builder: (BuildContext context, Widget? _) {
          final tokens = AppThemeHost.of(context);
          final BackButtonSpec spec = controller.spec;
          final bool visible = controller.visible;
          final bool isClose = controller.isFullscreenDialogRoute;

          final IconData iconData =
              spec.icon ?? (isClose ? AppIcons.clear() : AppIcons.back());
          final String tooltip = spec.tooltip ?? (isClose ? '关闭' : '返回');
          final Color color = spec.color ?? tokens.colors.onSurfaceVariant;
          final Color background = spec.background ??
              tokens.colors.surfaceContainerHighest.withValues(alpha: 0.92);
          final bool ring = spec.ringShadow ?? (spec.background == null);

          Widget core = MiuixIconButton(
            onPressed: () {
              if (spec.onPressed != null) {
                spec.onPressed!();
                return;
              }
              spec.onBeforePop?.call();
              controller.navigator?.maybePop();
            },
            minWidth: boxSize,
            minHeight: boxSize,
            backgroundColor: background,
            child: AppTooltip(
              message: tooltip,
              child: AppIcon(
                iconData,
                size: spec.iconSize,
                color: color,
                shadows: spec.shadows,
              ),
            ),
          );

          if (ring) {
            core = DecoratedBox(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: core,
            );
          }

          return AnimatedOpacity(
            opacity: visible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: IgnorePointer(
              ignoring: !visible,
              child: Semantics(button: true, label: tooltip, child: core),
            ),
          );
        },
      ),
    );
  }
}

/// 页面便捷宿主：把本页的返回按钮规格登记到 [GlobalBackButtonController]。
///
/// 用法（**不需要任何定制的标准页可省略**，壳层按默认规格渲染）：
/// ```dart
/// BackButtonOwner(
///   controller: appBackButtonController,
///   listenable: _scrollRatio,          // 规格随状态变化时（可选）
///   specBuilder: () => BackButtonSpec(color: ..., onBeforePop: ...),
///   child: AppScaffold(...),
/// )
/// ```
/// [child] 以引用透传 ⇒ 规格变化/监听触发**只重建本宿主自身**，不连带整页重建。
class BackButtonOwner extends StatefulWidget {
  const BackButtonOwner({
    super.key,
    required this.controller,
    required this.specBuilder,
    this.listenable,
    required this.child,
  });

  /// 目标控制器（通常为 `main.dart` 的 `appBackButtonController`）。
  final GlobalBackButtonController controller;

  /// 规格构造器（在依赖/监听变化时被调用，返回本页当前规格）。
  final BackButtonSpec Function() specBuilder;

  /// 触发规格重算的监听源（可选；如滚动进度 notifier）。
  final Listenable? listenable;

  final Widget child;

  @override
  State<BackButtonOwner> createState() => _BackButtonOwnerState();
}

class _BackButtonOwnerState extends State<BackButtonOwner> {
  Route<dynamic>? _route;

  @override
  void initState() {
    super.initState();
    widget.listenable?.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final Route<dynamic>? route = ModalRoute.of(context);
    if (!identical(route, _route)) {
      final Route<dynamic>? old = _route;
      _route = route;
      if (old != null) widget.controller.removeSpec(old);
    }
    _sync();
  }

  @override
  void didUpdateWidget(BackButtonOwner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listenable != widget.listenable) {
      oldWidget.listenable?.removeListener(_sync);
      widget.listenable?.addListener(_sync);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeSpec(_route!);
    }
    _sync();
  }

  void _sync() {
    final Route<dynamic>? route = _route;
    if (route == null) return;
    widget.controller.setSpec(route, widget.specBuilder());
  }

  @override
  void dispose() {
    widget.listenable?.removeListener(_sync);
    final Route<dynamic>? route = _route;
    if (route != null) widget.controller.removeSpec(route);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}