import 'package:flutter/widgets.dart';

import 'ui_style.dart';

/// 广播当前 [UiStyle] 的 [InheritedWidget]。
///
/// 参照 BiliPai 的 `LocalUiPreset` / `LocalAndroidNativeVariant`
/// CompositionLocal。在 `main.dart` 用 [UiStyleScope] 包裹根树后，
/// 任意后代组件通过 [UiStyle.of] 读取当前风格。
///
/// 依赖更新时（[UiStyleNotifier] 触发 [ValueNotifier] 通知），
/// [UiStyleScope] 的 `ValueListenableBuilder` 会重建整个 InheritedWidget，
/// 依赖它的子树随之重建。
class InheritedUiStyle extends InheritedWidget {
  const InheritedUiStyle({
    super.key,
    required this.style,
    required super.child,
  });

  /// 当前生效的 [UiStyle]。
  final UiStyle style;

  /// 从最近的 [InheritedUiStyle] 祖先读取当前 [UiStyle]。
  ///
  /// 若树中无 [InheritedUiStyle]（如测试环境），回退到 [UiStyle.ios]
  /// （默认风格），避免抛异常。
  static UiStyle of(BuildContext context) {
    final widget =
        context.dependOnInheritedWidgetOfExactType<InheritedUiStyle>();
    return widget?.style ?? UiStyle.ios;
  }

  @override
  bool updateShouldNotify(InheritedUiStyle oldWidget) =>
      style != oldWidget.style;
}

/// 在子树中提供 [UiStyle] 的包装器。
///
/// 用法：
/// ```dart
/// UiStyleScope(
///   style: UiStyle.ios,
///   child: ...,
/// )
/// ```
class UiStyleScope extends StatelessWidget {
  const UiStyleScope({
    super.key,
    required this.style,
    required this.child,
  });

  final UiStyle style;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InheritedUiStyle(style: style, child: child);
  }
}
