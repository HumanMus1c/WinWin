import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/utils/load_more_gate.dart';

/// [LoadMoreGate] 回归测试（2026-11-13 滚动体验轮）。
///
/// 口径：滚轮平滑补间后滚动通知变成「每帧一次」，原「距底不足 N 屏就请求」
/// 的写法会让贴底时每帧重发请求；门闩必须保证：
/// - 跨过阈值只放行一次；
/// - 回滚超过迟滞带后重新武装；
/// - 内容长度变化（新批次落地）后重新武装。
Widget _host(Widget child) => MediaQuery(
      data: const MediaQueryData(size: Size(400, 400)),
      child: Directionality(textDirection: TextDirection.ltr, child: child),
    );

Widget _list(ScrollController controller, {int itemCount = 100}) => SizedBox(
      width: 400,
      height: 400,
      child: ListView.builder(
        controller: controller,
        itemExtent: 50,
        itemCount: itemCount,
        itemBuilder: (_, i) => Text('row $i'),
      ),
    );

void main() {
  testWidgets('距底 1 屏只放行一次；回滚超过迟滞带后重新武装', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final gate = LoadMoreGate(minInterval: Duration.zero);

    await tester.pumpWidget(_host(_list(controller)));
    expect(controller.position.hasContentDimensions, isTrue);

    // 顶部：距底远，不触发。
    expect(gate.shouldTrigger(controller.position), isFalse);

    // 贴底：触发一次。
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    expect(gate.shouldTrigger(controller.position), isTrue);

    // 仍贴底：不重复触发。
    expect(gate.shouldTrigger(controller.position), isFalse);
    expect(gate.shouldTrigger(controller.position), isFalse);

    // 回滚到顶部：重新武装，但本轮不放行。
    controller.jumpTo(0);
    await tester.pump();
    expect(gate.shouldTrigger(controller.position), isFalse);

    // 再次贴底：放行。
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    expect(gate.shouldTrigger(controller.position), isTrue);
  });

  testWidgets('内容变长（新批次落地）后重新武装', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final gate = LoadMoreGate(minInterval: Duration.zero);

    await tester.pumpWidget(_host(_list(controller, itemCount: 8)));
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    expect(gate.shouldTrigger(controller.position), isTrue);
    expect(gate.shouldTrigger(controller.position), isFalse);

    // 追加内容：maxScrollExtent 变化 ⇒ 重新武装。
    await tester.pumpWidget(_host(_list(controller, itemCount: 40)));
    await tester.pump();
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    expect(gate.shouldTrigger(controller.position), isTrue);
  });

  testWidgets('冷却时间内同一位置不重复放行', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final gate = LoadMoreGate(
      minInterval: const Duration(milliseconds: 200),
    );

    await tester.pumpWidget(_host(_list(controller)));
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    expect(gate.shouldTrigger(controller.position), isTrue);

    // 回滚并立刻再次贴底：冷却未过，仍不放行。
    controller.jumpTo(0);
    await tester.pump();
    expect(gate.shouldTrigger(controller.position), isFalse);
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    expect(gate.shouldTrigger(controller.position), isFalse);

    // 冷却使用真实时间（DateTime.now），需让出真实时钟。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 220)),
    );
    expect(gate.shouldTrigger(controller.position), isTrue);
  });
}
