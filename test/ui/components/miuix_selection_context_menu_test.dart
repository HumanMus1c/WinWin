import 'package:cupertino_ui/cupertino_ui.dart'
    show cupertinoDesktopTextSelectionHandleControls;
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:winwin/common/widgets/miuix_context_menu.dart';
import 'package:winwin/core/shell/app_theme_host.dart';

/// 回归：Windows 平台上 SelectableRegion 的右键菜单必须走
/// [buildMiuixTextSelectionContextMenu]（Miuix 面板），而非选择控件自带的
/// 默认工具栏。
///
/// 前提机制（Flutter 迁移口径）：仅当 selectionControls 混入
/// `TextSelectionHandleControls`（如 cupertinoDesktopTextSelectionHandleControls）
/// 时，`SelectableRegion.contextMenuBuilder` 才会被采用；普通控件会被忽略并
/// 回退到控件自带工具栏（详见 B7-c1 补丁#2 复盘）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host(Widget child) => MaterialApp(
        home: AppThemeHost(
          tokens: AppThemeHost.tokensFor(Brightness.dark),
          child: Scaffold(body: Center(child: child)),
        ),
      );

  testWidgets('Windows 右键文本选择：显示 Miuix 菜单而非默认工具栏', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    await tester.pumpWidget(
      host(
        SizedBox(
          width: 300,
          child: SelectableRegion(
            selectionControls: cupertinoDesktopTextSelectionHandleControls,
            contextMenuBuilder: buildMiuixTextSelectionContextMenu,
            child: const Text('Hello selection world for context menu test'),
          ),
        ),
      ),
    );

    // 鼠标拖选一段文本（从首行行内起点向右拖）。
    final textFinder = find.byType(Text).first;
    final start = tester.getTopLeft(textFinder) + const Offset(4, 8);
    final drag = await tester.startGesture(start, kind: PointerDeviceKind.mouse);
    await drag.moveTo(start + const Offset(140, 0));
    await drag.up();
    await tester.pumpAndSettle();

    // 右键点在选区内（保留选区 → 菜单应含复制 + 全选）。
    final rightTap = await tester.startGesture(
      start + const Offset(70, 0),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await rightTap.up();
    await tester.pumpAndSettle();

    // 期望：Miuix 菜单（标题 + 中文条目）；默认英文工具栏不出现。
    expect(find.text('文本操作'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Select all'), findsNothing);
    expect(tester.takeException(), isNull);

    // 恢复平台覆写（须在测试体内完成：框架的 foundation 变量校验先于
    // tearDown 执行）。
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Windows 右键 SelectableText：显示 Miuix 菜单而非默认工具栏', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    await tester.pumpWidget(
      host(
        SizedBox(
          width: 300,
          child: SelectableText(
            'Hello selectable text for context menu test',
            selectionControls: cupertinoDesktopTextSelectionHandleControls,
            contextMenuBuilder: buildMiuixEditableTextContextMenu,
          ),
        ),
      ),
    );

    // 鼠标拖选一段文本（从首行行内起点向右拖）。
    final textFinder = find.byType(SelectableText).first;
    final start = tester.getTopLeft(textFinder) + const Offset(4, 8);
    final drag = await tester.startGesture(start, kind: PointerDeviceKind.mouse);
    await drag.moveTo(start + const Offset(140, 0));
    await drag.up();
    await tester.pumpAndSettle();

    // 右键点在选区内（保留选区 → 菜单应含复制 + 全选）。
    final rightTap = await tester.startGesture(
      start + const Offset(70, 0),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await rightTap.up();
    await tester.pumpAndSettle();

    // 期望：Miuix 菜单（标题 + 中文条目）；默认英文工具栏不出现。
    expect(find.text('文本操作'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Select all'), findsNothing);
    expect(tester.takeException(), isNull);

    debugDefaultTargetPlatformOverride = null;
  });
}
