import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';
import 'package:winwin/ui/components/immersive_title_bar.dart';

/// 沉浸标题条布局回归测试。
///
/// 防回归点：标题条高度（Windows 11 标准 32 逻辑像素）、右上三键尺寸与
/// 排列（46×32，紧贴窗口右侧）、拖动区占满其余宽度。
void main() {
  testWidgets('沉浸标题条：32px 占位 + 右上三键（Win11 标准尺寸）',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: ImmersiveTitleBarShell(
          child: const ColoredBox(
            color: Color(0xFF00AA00),
            child: SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    // 三键：最小化 / 最大化 / 关闭，自左向右 46×32。
    final buttons = find.byType(WindowCaptionButton);
    expect(buttons, findsNWidgets(3));
    expect(tester.getSize(buttons.at(0)), const Size(46, 32));
    expect(tester.getTopLeft(buttons.at(0)).dx, 1200 - 138);
    expect(tester.getTopLeft(buttons.at(2)).dx, 1200 - 46);
    expect(tester.getTopLeft(buttons.at(2)).dy, 0);

    // 拖动区占据标题条其余宽度，位于窗口左上角。
    final dragArea = find.byType(DragToMoveArea);
    expect(dragArea, findsOneWidget);
    expect(tester.getSize(dragArea), Size(1200 - 138, kWindowCaptionHeight));
    expect(tester.getTopLeft(dragArea), Offset.zero);
  });
}
