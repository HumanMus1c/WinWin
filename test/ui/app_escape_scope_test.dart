import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:winwin/core/input/app_escape_scope.dart';
import 'package:winwin/core/input/escape_layer_registry.dart';

/// 全局 Esc 路由器（[AppEscapeScope]）分层语义测试。
///
/// 覆盖：返回上一级 / 输入框取消聚焦 / 对话框关闭 / 二级浮层 LIFO 关闭 /
/// 失效登记自愈 / 根页面无操作。
void main() {
  Widget host({
    required GlobalKey<NavigatorState> navigatorKey,
    required AppEscapeNavigatorObserver observer,
    required Widget home,
  }) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [observer],
      builder: (context, child) => AppEscapeScope(
        navigatorKey: navigatorKey,
        observer: observer,
        child: child ?? const SizedBox.shrink(),
      ),
      home: home,
    );
  }

  Widget pushButtonPage({required String label, required Widget target}) {
    return Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => target),
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }

  testWidgets('压栈页面可被 Esc 返回上一级', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final observer = AppEscapeNavigatorObserver();
    await tester.pumpWidget(
      host(
        navigatorKey: navigatorKey,
        observer: observer,
        home: pushButtonPage(
          label: 'go',
          target: const Scaffold(body: Center(child: Text('second'))),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('second'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('second'), findsNothing);
    expect(find.text('go'), findsOneWidget);
  });

  testWidgets('输入框聚焦：Esc 取消聚焦且不返回', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final observer = AppEscapeNavigatorObserver();
    await tester.pumpWidget(
      host(
        navigatorKey: navigatorKey,
        observer: observer,
        home: pushButtonPage(
          label: 'go',
          target: Scaffold(
            body: Center(child: TextField(autofocus: true)),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    final editable = find.byType(EditableText);
    expect(editable, findsOneWidget);
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // 仅取消聚焦，页面保留。
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isFalse,
    );
  });

  testWidgets('对话框在最上层：Esc 关闭对话框且不返回页面', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final observer = AppEscapeNavigatorObserver();
    await tester.pumpWidget(
      host(
        navigatorKey: navigatorKey,
        observer: observer,
        home: pushButtonPage(
          label: 'go',
          target: Scaffold(
            body: Center(
              child: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const AlertDialog(title: Text('dlg')),
                  ),
                  child: const Text('open-dialog'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open-dialog'));
    await tester.pumpAndSettle();
    expect(find.text('dlg'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // 对话框关闭（不保存），页面仍在。
    expect(find.text('dlg'), findsNothing);
    expect(find.text('open-dialog'), findsOneWidget);
  });

  testWidgets('二级浮层：Esc 按 LIFO 关闭并消费，之后才返回页面', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final observer = AppEscapeNavigatorObserver();
    await tester.pumpWidget(
      host(
        navigatorKey: navigatorKey,
        observer: observer,
        home: pushButtonPage(
          label: 'go',
          target: const Scaffold(body: Center(child: Text('second'))),
        ),
      ),
    );

    var firstOpen = true;
    var secondOpen = true;
    final calls = <String>[];
    final offFirst = EscapeLayerRegistry.instance.register(() {
      if (!firstOpen) return false;
      firstOpen = false;
      calls.add('first');
      return true;
    });
    final offSecond = EscapeLayerRegistry.instance.register(() {
      if (!secondOpen) return false;
      secondOpen = false;
      calls.add('second');
      return true;
    });
    addTearDown(() {
      offFirst();
      offSecond();
    });

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // 第一次 Esc：关闭最上层浮层（second），页面不返回。
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(calls, ['second']);
    expect(find.text('second'), findsOneWidget);
    offSecond();

    // 第二次 Esc：关闭剩余浮层（first），页面仍不返回。
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(calls, ['second', 'first']);
    expect(find.text('second'), findsOneWidget);
    offFirst();

    // 第三次 Esc：无浮层，返回上一级。
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('second'), findsNothing);
  });

  testWidgets('失效登记自愈：漏注销的浮层不吞 Esc', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final observer = AppEscapeNavigatorObserver();
    await tester.pumpWidget(
      host(
        navigatorKey: navigatorKey,
        observer: observer,
        home: pushButtonPage(
          label: 'go',
          target: const Scaffold(body: Center(child: Text('second'))),
        ),
      ),
    );

    // 模拟“浮层已自行关闭但忘记注销”的失效登记。
    var staleOpen = false;
    final offStale = EscapeLayerRegistry.instance.register(() => staleOpen);
    addTearDown(offStale);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    // 失效登记被剔除后仍按“返回上一级”处理。
    expect(find.text('second'), findsNothing);
  });

  testWidgets('根页面：Esc 无操作且不崩溃', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final observer = AppEscapeNavigatorObserver();
    await tester.pumpWidget(
      host(
        navigatorKey: navigatorKey,
        observer: observer,
        home: const Scaffold(body: Center(child: Text('root'))),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('root'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
