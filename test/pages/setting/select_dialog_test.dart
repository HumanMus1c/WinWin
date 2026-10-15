import 'package:material_ui/material_ui.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:winwin/core/input/app_escape_scope.dart';
import 'package:winwin/pages/setting/widgets/select_dialog.dart';
import 'package:winwin/ui/components/app_tooltip.dart';

/// [SelectDialog] / [showSelectDialog] 契约测试。
///
/// 锁定两条核心契约（迁移复盘 §4 遗留项 4）：
/// - 点选即提交：点任一选项 → 立即 pop 所选值（宿主据此落盘）；
/// - Esc 取消不写入：Esc 关闭弹窗并返回 null，宿主不落盘。
/// 另覆盖关闭按钮取消与副标题渲染（minWidth 320 防说明文案硬换行）。
///
/// 宿主复刻真实链路：UiStyleScope + MaterialApp + AppEscapeScope
/// （与 `main.dart` 同构，去除本用例无关的兼容桥接）。
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

  const values = <(int, String)>[(0, '不重试'), (1, '1 次'), (2, '2 次')];

  /// 复刻设置页调用点：`if (res != null) { 落盘; setState(); }`。
  Widget launcher({
    required GlobalKey<NavigatorState> navigatorKey,
    required AppEscapeNavigatorObserver observer,
    required void Function(int?) onWritten,
    Widget Function(BuildContext, int)? subtitleBuilder,
    String title = '重试次数',
    List<(int, String)> options = values,
  }) {
    return host(
      navigatorKey: navigatorKey,
      observer: observer,
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => Center(
            child: TextButton(
              onPressed: () async {
                final res = await showSelectDialog<int>(
                  context,
                  title: title,
                  value: 1,
                  values: options,
                  subtitleBuilder: subtitleBuilder,
                );
                if (res != null) {
                  setState(() => onWritten(res));
                }
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('点选即提交：点选项后弹窗关闭且宿主收到所选值', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final observer = AppEscapeNavigatorObserver();
    int? written;

    await tester.pumpWidget(
      launcher(
        navigatorKey: navigatorKey,
        observer: observer,
        onWritten: (v) => written = v,
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('重试次数'), findsOneWidget);

    await tester.tap(find.text('2 次'));
    await tester.pumpAndSettle();

    // 点选即提交：宿主收到值，弹窗关闭。
    expect(written, 2);
    expect(find.text('重试次数'), findsNothing);
  });

  testWidgets('Esc 取消不写入：弹窗关闭、宿主未收到值、页面保留', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final observer = AppEscapeNavigatorObserver();
    int? written;

    await tester.pumpWidget(
      launcher(
        navigatorKey: navigatorKey,
        observer: observer,
        onWritten: (v) => written = v,
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('重试次数'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // 取消语义：不写入，仅关闭弹窗，页面保留。
    expect(written, isNull);
    expect(find.text('重试次数'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('关闭按钮取消：返回 null 且不写入', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final observer = AppEscapeNavigatorObserver();
    int? written;

    await tester.pumpWidget(
      launcher(
        navigatorKey: navigatorKey,
        observer: observer,
        onWritten: (v) => written = v,
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('重试次数'), findsOneWidget);

    await tester.tap(find.byWidgetPredicate(
        (w) => w is AppTooltip && w.message == '关闭'));
    await tester.pumpAndSettle();

    expect(written, isNull);
    expect(find.text('重试次数'), findsNothing);
  });

  testWidgets('副标题完整渲染且弹窗宽度不低于 320', (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      final observer = AppEscapeNavigatorObserver();

      await tester.pumpWidget(
        launcher(
          navigatorKey: navigatorKey,
          observer: observer,
          onWritten: (_) {},
          title: '界面风格',
          options: const [(0, 'Material 3'), (1, 'Miuix')],
          // 复刻真实调用点的 31 字符说明文案（曾触发硬换行的边界样本）。
          subtitleBuilder: (_, index) => Text(
            index == 0 ? 'M3 原生控件 + 标准 tonal elevation' : 'Miuix 扁平控件',
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('M3 原生控件 + 标准 tonal elevation'), findsOneWidget);

      // 路由外壳铺满全屏（Align），实际卡片是内部受 ConstrainedBox 约束、
      // 由 [MiuixDialogShell] 自绘的 [MiuixSurface]（B7-c6-1 起 `Dialog` 的
      // Material 卡片已换为零-material 替身，故锚点改为可见表面）。
      // 宽度应落在 [320, 420]（minWidth 320 防硬换行）。
      final card = find
          .descendant(
            of: find.byType(SelectDialog<int>),
            matching: find.byType(MiuixSurface),
          )
          .first;
      final width = tester.getSize(card).width;
      expect(width, greaterThanOrEqualTo(320));
      expect(width, lessThanOrEqualTo(420));

      await tester.tap(find.byWidgetPredicate(
        (w) => w is AppTooltip && w.message == '关闭'));
      await tester.pumpAndSettle();
      expect(find.text('界面风格'), findsNothing);
  });
}
