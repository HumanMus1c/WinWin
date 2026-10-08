import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:winwin/core/input/app_escape_scope.dart';
import 'package:winwin/core/shell/app_shell.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/app_theme.dart';

/// AppShell 的 **Material 环境等价面**回归测试（B1 修复轮）。
///
/// 症状背景：B1 把 MaterialApp 换成 AppShell 时，本地化委托误用了 SDK
/// （flutter_localizations）的 Global* —— 它们实现的是 **SDK 类型**的
/// `MaterialLocalizations`，而应用侧 Material 控件读的是 **material_ui 类型**，
/// 二者不可互换 → 运行期 `No MaterialLocalizations found`（release 下表现为
/// 灰块且不可点：首页搜索框、全局返回按钮、SelectDialog 弹不出）。
///
/// 本组用例把"Material 控件在新壳下必须能正常构建"固化为回归门槛。
void main() {
  Future<void> pumpShell(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(
      AppShell(
        title: 'parity',
        isDark: false,
        navigatorKey: GlobalKey<NavigatorState>(),
        escapeObserver: AppEscapeNavigatorObserver(),
        theme: AppTheme.lightFor(),
        home: home,
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('material TextField（首页搜索框形态）可构建且无异常', (tester) async {
    await pumpShell(
      tester,
      const Scaffold(
        body: Center(
          child: SizedBox(
            height: 38,
            child: TextField(
              readOnly: true,
              decoration: InputDecoration(hintText: '搜索'),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppBackButton（全局返回按钮）可构建且无异常', (tester) async {
    await pumpShell(
      tester,
      const Scaffold(body: Center(child: AppBackButton())),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('material showDialog + Dialog（SelectDialog 形态）可弹出且无异常',
      (tester) async {
    late BuildContext hostContext;
    await pumpShell(
      tester,
      Scaffold(
        body: Builder(builder: (context) {
          hostContext = context;
          return const SizedBox.shrink();
        }),
      ),
    );
    expect(tester.takeException(), isNull);

    showDialog<void>(
      context: hostContext,
      builder: (_) => const Dialog(child: SizedBox(width: 120, height: 120)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.byType(Dialog), findsOneWidget, reason: '对话框应实际弹出');
  });
}
