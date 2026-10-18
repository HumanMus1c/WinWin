import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:winwin/common/widgets/app_dialog_shell.dart';
import 'package:winwin/core/input/app_escape_scope.dart';
import 'package:winwin/core/input/escape_layer_registry.dart';
import 'package:winwin/core/shell/app_dialogs.dart';
import 'package:winwin/core/shell/app_routes.dart';
import 'package:winwin/ui/components/app_components.dart';

import '../support/app_test_host.dart';

/// 全局 Esc 路由器（[AppEscapeScope]）分层语义测试。
///
/// 覆盖：返回上一级 / 输入框取消聚焦 / 对话框关闭 / 二级浮层 LIFO 关闭 /
/// 失效登记自愈 / 根页面无操作。
///
/// 宿主：统一测试宿主（[AppTestApp]）的 builder 链已含 `AppEscapeScope`
/// （与 `main.dart` 同构）；对话框走零-material 的 [showAppDialog] /
/// [AppAlertDialog]，输入框走 [AppTextField]。
void main() {
  Widget host({
    required GlobalKey<NavigatorState> navigatorKey,
    required AppEscapeNavigatorObserver observer,
    required Widget home,
  }) {
    return AppTestApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [observer],
      escapeObserver: observer,
      home: home,
    );
  }

  Widget pushButtonPage({required String label, required Widget target}) {
    return Builder(
      builder: (context) => AppTestScaffold(
        body: Center(
          child: GestureDetector(
            onTap: () => Navigator.of(context).push(
              AppRoute<void>(builder: (_) => target),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(label),
            ),
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
          target: const AppTestScaffold(body: Center(child: Text('second'))),
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
          target: AppTestScaffold(
            body: Center(child: AppTextField(autofocus: true)),
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
    expect(find.byType(AppTextField), findsOneWidget);
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
          target: AppTestScaffold(
            body: Center(
              child: Builder(
                builder: (context) => GestureDetector(
                  onTap: () => showAppDialog<void>(
                    context: context,
                    builder: (_) => const AppAlertDialog(title: Text('dlg')),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('open-dialog'),
                  ),
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
          target: const AppTestScaffold(body: Center(child: Text('second'))),
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
          target: const AppTestScaffold(body: Center(child: Text('second'))),
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
        home: const AppTestScaffold(body: Center(child: Text('root'))),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('root'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}