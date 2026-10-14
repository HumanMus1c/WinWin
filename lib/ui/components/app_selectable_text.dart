import 'package:cupertino_ui/cupertino_ui.dart'
    show cupertinoDesktopTextSelectionHandleControls;
import 'package:flutter/widgets.dart';

import 'package:winwin/common/widgets/miuix_context_menu.dart';

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
  });

  final String data;
  final TextStyle? style;
  final int? maxLines;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return SelectableRegion(
      selectionControls: cupertinoDesktopTextSelectionHandleControls,
      contextMenuBuilder: buildMiuixTextSelectionContextMenu,
      child: Text(
        data,
        style: style,
        maxLines: maxLines,
        textAlign: textAlign,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
      ),
    );
  }
}
