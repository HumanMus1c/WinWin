import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'escape_layer_registry.dart';

/// 全局 Esc 路由器的路由栈观察器。
///
/// 维护当前路由栈，供 [AppEscapeScope] 判断“最上层是否为弹层路由”
/// （对话框 / 底部弹层 / 菜单 / 下拉等 [PopupRoute]）。
class AppEscapeNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> _routes = <Route<dynamic>>[];

  /// 路由栈顶是否为弹层路由（[PopupRoute] 的子类）。
  bool get hasPopupOnTop => _routes.isNotEmpty && _routes.last is PopupRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
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
  }
}

/// 当前主焦点是否位于文本输入框（TextField / TextFormField / 可编辑文本等）。
///
/// 输入框内部的 [Focus] 节点挂在 [EditableText] 子树内，据此判定。
bool isTextInputFocused() {
  final BuildContext? context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  return context.findAncestorWidgetOfExactType<EditableText>() != null;
}

/// 全局 Esc 分层路由器。
///
/// 挂在 `MaterialApp.builder` 内（Navigator 之上、框架 Shortcuts 之下）：
/// 对任意路由——包括压栈页面与对话框——的焦点链都是祖先，因此“任一界面”
/// 都能收到未被内层消费的 Esc；同时排在播放器 / 图片画廊 / MenuAnchor 菜单
/// 等内层消费者之后、框架 `Escape → DismissIntent` 映射之前，不破坏既有
/// 内层语义。
///
/// 分层语义（每层消耗一次 Esc，不级联）：
///   1. 路由级弹层在最上层（对话框 / 底部弹层 / 菜单）→ 关闭（不保存）；
///   2. 自定义二级浮层（见 [EscapeLayerRegistry]）→ 关闭最上层一个；
///   3. 焦点位于输入框 → 取消聚焦；
///   4. 可返回 → 返回上一级（[Navigator.maybePop]）。
class AppEscapeScope extends StatelessWidget {
  const AppEscapeScope({
    super.key,
    required this.navigatorKey,
    required this.observer,
    required this.child,
  });

  /// 根 Navigator 引用（本组件位于 Navigator 之上，无法用 `Navigator.of` 获取）。
  final GlobalKey<NavigatorState> navigatorKey;

  /// 路由栈观察器（须注册到 MaterialApp.navigatorObservers）。
  final AppEscapeNavigatorObserver observer;

  final Widget child;

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    final NavigatorState? navigator = navigatorKey.currentState;
    if (navigator == null) return KeyEventResult.ignored;

    // 1) 路由级弹层关闭（不保存）：对话框 / 底部弹层 / 菜单 / 下拉。
    if (observer.hasPopupOnTop) {
      navigator.maybePop();
      return KeyEventResult.handled;
    }
    // 2) 自定义二级浮层（表情面板 / 弹幕样式 / 章节面板 / 音量弹层）LIFO 关闭。
    if (EscapeLayerRegistry.instance.closeTopmost()) {
      return KeyEventResult.handled;
    }
    // 3) 输入框聚焦：取消聚焦（消耗本次 Esc，不返回）。
    final FocusNode? primaryFocus = FocusManager.instance.primaryFocus;
    if (isTextInputFocused()) {
      primaryFocus?.unfocus();
      return KeyEventResult.handled;
    }
    // 4) 返回上一级。
    if (navigator.canPop()) {
      navigator.maybePop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKeyEvent,
      child: child,
    );
  }
}
