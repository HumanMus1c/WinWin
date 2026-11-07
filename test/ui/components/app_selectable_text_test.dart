import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/ui/components/app_selectable_text.dart';

import '../../support/app_test_host.dart';

void main() {
  const text = '这是一段用于验证鼠标拖拽选中的评论正文文本';

  Widget host() => appTestHost(
        SizedBox(
          width: 300,
          height: 200,
          child: ListView(
            children: const [
              SizedBox(height: 60),
              AppSelectableText(text),
              SizedBox(height: 600),
            ],
          ),
        ),
      );

  testWidgets('鼠标拖拽文本优先选择，不移动父级列表', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    final position =
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    final gesture = await tester.startGesture(
      tester.getCenter(find.text(text)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final status = SelectableRegionSelectionStatusScope.maybeOf(
      tester.element(find.text(text)),
    )?.value;
    expect(position.pixels, 0.0);
    expect(status, SelectableRegionSelectionStatus.finalized);
  });

  testWidgets('文本之外的鼠标拖拽仍可滚动列表', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    final position =
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    final gesture = await tester.startGesture(
      const Offset(150, 30),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(position.pixels, 40.0);
  });
}
