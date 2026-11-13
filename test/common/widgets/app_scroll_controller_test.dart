import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/common/widgets/app_scroll_controller.dart';

/// [AppScrollController] 滚轮补间回归测试（2026-11-13 滚动体验轮）。
///
/// 口径：
/// - 鼠标滚轮单刻度（|delta| ≥ 阈值）不再立即跳变，而是按距离补间到位；
/// - 连续滚轮从「在途目标」继续累加，不回到当前像素重新起算；
/// - 触控板/高精度小增量保持立即跟手（零延迟）。
Widget _host(ScrollController controller) => MediaQuery(
      data: const MediaQueryData(size: Size(400, 400)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 400,
          height: 400,
          child: ListView.builder(
            controller: controller,
            itemExtent: 50,
            itemCount: 200,
            itemBuilder: (_, i) => Text('row $i'),
          ),
        ),
      ),
    );

Future<void> _wheel(WidgetTester tester, TestPointer pointer, double dy) async {
  await tester.sendEventToBinding(pointer.hover(const Offset(200, 200)));
  await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
}

void main() {
  testWidgets('滚轮单刻度按补间推进（不是立即跳变）', (tester) async {
    final controller = AppScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller));

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await _wheel(tester, pointer, 100);
    await tester.pump();

    // 动画起点：尚未直接跳到 100。
    expect(controller.offset, lessThan(100));

    await tester.pump(const Duration(milliseconds: 60));
    final mid = controller.offset;
    expect(mid, greaterThan(0));
    expect(mid, lessThan(100));

    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(100, 0.01));
  });

  testWidgets('连续滚轮从在途目标继续累加（两次刻度 → 200）', (tester) async {
    final controller = AppScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller));

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await _wheel(tester, pointer, 100);
    await tester.pump(const Duration(milliseconds: 30));
    await _wheel(tester, pointer, 100);
    await tester.pumpAndSettle();

    expect(controller.offset, closeTo(200, 1));
  });

  testWidgets('小增量（触控板）立即跟手', (tester) async {
    final controller = AppScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller));

    final pointer = TestPointer(2, PointerDeviceKind.trackpad);
    await _wheel(tester, pointer, 10);
    await tester.pump();

    expect(controller.offset, closeTo(10, 0.01));
  });
}
