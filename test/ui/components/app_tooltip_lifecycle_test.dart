import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/ui/components/app_tooltip.dart';

import '../../support/app_test_host.dart';

/// 宿主：统一测试宿主（`AppTestApp`）的 builder 链已含 `MiuixThemeScope`
/// → `MiuixTheme`，浮层挂载于 Navigator 的 Overlay 之上，与 main.dart 同构。
Widget _host(Widget child) => AppTestApp(
      home: AppTestScaffold(body: Center(child: child)),
    );

Future<TestGesture> _hoverIn(WidgetTester tester, Finder target) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  await tester.pump();
  await gesture.moveTo(tester.getCenter(target));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 60));
  return gesture;
}

Future<void> _hoverOut(WidgetTester tester, TestGesture gesture) async {
  await gesture.moveTo(const Offset(8, 8));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('悬停显示提示泡，移出后隐藏', (tester) async {
    await tester.pumpWidget(
      _host(
        const AppTooltip(
          message: '提示-悬停',
          child: SizedBox(key: ValueKey('anchor-hover'), width: 60, height: 24),
        ),
      ),
    );
    final anchor = find.byKey(const ValueKey('anchor-hover'));
    expect(find.text('提示-悬停'), findsNothing);

    final gesture = await _hoverIn(tester, anchor);
    expect(find.text('提示-悬停'), findsOneWidget);

    await _hoverOut(tester, gesture);
    expect(find.text('提示-悬停'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('悬停期间宿主高频重建：不抛异常且提示泡保持', (tester) async {
    Widget buildTree(int revision) => _host(
          AppTooltip(
            message: '提示-重建',
            child: SizedBox(
              key: const ValueKey('anchor-rebuild'),
              width: 60,
              height: 24,
            ),
          ),
        );

    await tester.pumpWidget(buildTree(0));
    await _hoverIn(tester, find.byKey(const ValueKey('anchor-rebuild')));
    expect(find.text('提示-重建'), findsOneWidget);

    for (var revision = 1; revision <= 6; revision++) {
      await tester.pumpWidget(buildTree(revision));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    expect(find.text('提示-重建'), findsOneWidget);
  });

  testWidgets('悬停显示中宿主被移除：浮层随动清理且不抛异常', (tester) async {
    await tester.pumpWidget(
      _host(
        const AppTooltip(
          message: '提示-移除',
          child: SizedBox(key: ValueKey('anchor-remove'), width: 60, height: 24),
        ),
      ),
    );
    await _hoverIn(tester, find.byKey(const ValueKey('anchor-remove')));
    expect(find.text('提示-移除'), findsOneWidget);

    await tester.pumpWidget(
      _host(const SizedBox(width: 10, height: 10)),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('提示-移除'), findsNothing);
  });

  testWidgets('全局单活动槽：后悬停者接管，旧提示泡收起', (tester) async {
    await tester.pumpWidget(
      _host(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            AppTooltip(
              message: '泡A',
              child:
                  SizedBox(key: ValueKey('anchor-a'), width: 60, height: 24),
            ),
            SizedBox(width: 24),
            AppTooltip(
              message: '泡B',
              child:
                  SizedBox(key: ValueKey('anchor-b'), width: 60, height: 24),
            ),
          ],
        ),
      ),
    );

    final gesture = await _hoverIn(
      tester,
      find.byKey(const ValueKey('anchor-a')),
    );
    expect(find.text('泡A'), findsOneWidget);

    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('anchor-b'))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('泡B'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(find.text('泡A'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('长按显示提示泡', (tester) async {
    await tester.pumpWidget(
      _host(
        const AppTooltip(
          message: '提示-长按',
          child: SizedBox(key: ValueKey('anchor-longpress'), width: 60, height: 24),
        ),
      ),
    );
    await tester.longPress(
      find.byKey(const ValueKey('anchor-longpress')),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('提示-长按'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}