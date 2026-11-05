import 'package:cupertino_ui/cupertino_ui.dart'
    show cupertinoDesktopTextSelectionHandleControls;
import 'package:flutter/widgets.dart';

import 'package:winwin/common/widgets/miuix_context_menu.dart';

/// 区域级可选中容器（取代 material `SelectionArea`）。
///
/// 用于包裹「一段连续纯展示文本」的共同父级：子树内所有 [Text] 纳入同一个
/// 选择区域，支持跨文本连选；单段文本直接用 [AppSelectableText]。
/// 与 [AppSelectableText] 共用桌面 Handle 选择控件与 Miuix 右键菜单。
///
/// 约束：只包裹无交互的展示区域；按钮/卡片/可点击行等交互容器不要包，
/// 否则拖选会与点击竞争。已含 [AppSelectableText] 的区域不要重复包裹。
class AppSelectionArea extends StatelessWidget {
  const AppSelectionArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SelectableRegion(
      selectionControls: cupertinoDesktopTextSelectionHandleControls,
      contextMenuBuilder: buildMiuixTextSelectionContextMenu,
      child: child,
    );
  }
}

/// 可选中文本替身（取代 material `SelectableText`）。
///
/// 以 widgets 层 [SelectableRegion] 承载：桌面 Handle 选择控件（混入
/// TextSelectionHandleControls 后 `contextMenuBuilder` 才会被采用，见
/// B7-c1 补丁#2 复盘）+ Miuix 右键菜单构建器；视觉为普通 [Text]。
class AppSelectableText extends StatelessWidget {
  const AppSelectableText(
    this.data, {
    super.key,
    this.style,
    this.maxLines,
    this.textAlign,
  })  : textSpan = null,
        isRich = false;

  /// 富文本变体（取代 material `SelectableText.rich`）。
  const AppSelectableText.rich(
    TextSpan this.textSpan, {
    super.key,
    this.style,
    this.maxLines,
    this.textAlign,
  })  : data = null,
        isRich = true;

  final String? data;
  final TextSpan? textSpan;
  final TextStyle? style;
  final int? maxLines;
  final TextAlign? textAlign;

  /// 是否为富文本变体。
  final bool isRich;

  @override
  Widget build(BuildContext context) {
    return SelectableRegion(
      selectionControls: cupertinoDesktopTextSelectionHandleControls,
      contextMenuBuilder: buildMiuixTextSelectionContextMenu,
      // 注：rich/plain 统一走同一构建器。material `SelectableText.rich` 原先
      // 用的是 EditableTextState 签名的构建器，与 widgets 层 SelectableRegion
      // 的 SelectableRegionState 签名不兼容，故不沿用。
      child: isRich
          ? Text.rich(
              textSpan!,
              style: style,
              maxLines: maxLines,
              textAlign: textAlign,
              overflow: maxLines == null ? null : TextOverflow.ellipsis,
            )
          : Text(
              data!,
              style: style,
              maxLines: maxLines,
              textAlign: textAlign,
              overflow: maxLines == null ? null : TextOverflow.ellipsis,
            ),
    );
  }
}
