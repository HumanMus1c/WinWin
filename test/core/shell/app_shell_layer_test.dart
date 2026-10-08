import 'package:flutter/material.dart' as legacy;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart' show MiuixScaffold;
import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/core/input/app_escape_scope.dart';
import 'package:winwin/core/shell/app_dialogs.dart';
import 'package:winwin/core/shell/app_routes.dart';
import 'package:winwin/core/shell/app_scaffold.dart';
import 'package:winwin/core/shell/app_shell.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/core/shell/app_transition.dart';
import 'package:material_ui/material_ui.dart' as modern;
import 'package:winwin/core/shell/miuix_compat.dart';
import 'package:winwin/theme/app_theme.dart';

/// MD3 库级退役（Part B）L0 替身层回归测试。
///
/// 防回归点：
/// 1. `AppTokens/AppThemeHost`：主题取用通道（未挂宿主时按平台亮度回退）；
/// 2. `AppScaffold`：页面骨架替身（MiuixScaffold + token 背景）；
/// 3. `AppRoute`：路由替身（PageRoute + Miuix 转场核 + 300ms）；
/// 4. `AppDialogRoute/showAppDialog`：**仍是 PopupRoute**（Esc 分层语义依赖）
///    与 barrier/返回值契约；
/// 5. `MiuixCompat`：为 flutter_miuix 内部 SDK TextField 提供 Material 祖先与
///    MaterialLocalizations（release 缺失曾崩溃）；
/// 6. `AppShell`：WidgetsApp 壳（pageRouteBuilder 产出 AppRoute、主题宿主注入、
///    文本基底显式声明避免"黄绿双下划线"）。
void main() {
  testWidgets('AppThemeHost：未挂宿主按平台亮度回退，挂载后向子树供给 Token',
      (tester) async {
    late AppTokens fallback;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(builder: (context) {
          fallback = AppThemeHost.of(context);
          return const SizedBox.shrink();
        }),
      ),
    );
    // 测试环境默认平台亮度为浅色（无宿主时的回退口径）。
    expect(fallback.isDark, isFalse);
    expect(fallback.shapes, isNotNull);

    late AppTokens provided;
    await tester.pumpWidget(
      AppThemeHost(
        tokens: AppThemeHost.tokensFor(Brightness.dark),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(builder: (context) {
            provided = AppThemeHost.of(context);
            return const SizedBox.shrink();
          }),
        ),
      ),
    );
    expect(provided.isDark, isTrue);
  });

  testWidgets('AppScaffold：渲染 body 且背景取 Token 应用背景色', (tester) async {
    final tokens = AppThemeHost.tokensFor(Brightness.dark);
    await tester.pumpWidget(
      AppThemeHost(
        tokens: tokens,
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: AppScaffold(body: Text('页面内容')),
        ),
      ),
    );
    expect(find.text('页面内容'), findsOneWidget);
    final scaffold = tester.widget<MiuixScaffold>(find.byType(MiuixScaffold));
    expect(scaffold.containerColor, tokens.colors.background);
  });

  test('AppRoute：页面路由替身（PageRoute + Miuix 转场时长）', () {
    final route = AppRoute<void>(builder: (_) => const SizedBox.shrink());
    expect(route, isA<PageRoute<void>>());
    expect(route.transitionDuration, kMiuixTransitionDuration);
    expect(route.reverseTransitionDuration, kMiuixTransitionDuration);
  });

  testWidgets('AppRoute：经 Navigator 推入时挂载 Miuix 转场核并渲染内容',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Navigator(
          key: navKey,
          onGenerateRoute: (RouteSettings settings) =>
              AppRoute<void>(builder: (_) => const Text('首页')),
        ),
      ),
    );
    expect(find.text('首页'), findsOneWidget);

    navKey.currentState!.push(
      AppRoute<void>(builder: (_) => const Text('二级页')),
    );
    await tester.pump();
    expect(
      find.byType(MiuixPageTransition),
      findsWidgets,
      reason: '转场期间应挂载 Miuix 动画核（缩放 ≤1 + 锚 topCenter）',
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('二级页'), findsOneWidget);
  });

  testWidgets('转场性能取向：旧页静止（零变换），仅新页淡入+位移且不缩放',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Navigator(
          key: navKey,
          onGenerateRoute: (RouteSettings settings) => AppRoute<void>(
            builder: (_) => const Center(child: Text('旧页')),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    final Rect oldSettled = tester.getRect(find.text('旧页'));

    navKey.currentState!.push(
      AppRoute<void>(builder: (_) => const Center(child: Text('新页'))),
    );
    await tester.pump();
    final Rect oldDuring = tester.getRect(find.text('旧页'));
    final Rect newDuring = tester.getRect(find.text('新页'));

    await tester.pump(const Duration(milliseconds: 400));
    final Rect newSettled = tester.getRect(find.text('新页'));

    // 旧页（被覆盖的当前页）：转场期间位置/尺寸零变化 —— 不加任何特效。
    expect(
      oldDuring,
      oldSettled,
      reason: '被覆盖的当前页必须完全静止（不加变换/透明度层）',
    );

    // 新页：自下方滑入（纯位移），最终归位；全过程尺寸不变（未缩放）。
    expect(newDuring.top, greaterThan(newSettled.top), reason: '新页应自下方滑入');
    expect(newDuring.size, newSettled.size, reason: '新页不得缩放（仅位移）');

    // 结构约束：转场核内不得出现缩放动画（缩放会触发整页重光栅化）。
    expect(
      find.descendant(
        of: find.byType(MiuixPageTransition),
        matching: find.byType(ScaleTransition),
      ),
      findsNothing,
      reason: '转场核内不得使用 ScaleTransition',
    );
  });

  test('AppDialogRoute：PopupRoute 契约（Esc 分层）+ barrier 默认值', () {
    final route = AppDialogRoute<void>(builder: (_) => const SizedBox.shrink());
    expect(route, isA<PopupRoute<void>>());
    expect(route.barrierDismissible, isTrue);
    expect(route.barrierColor, const Color(0x8A000000));
    expect(route.barrierLabel, isNotEmpty);
    expect(route.transitionDuration, kMiuixTransitionDuration);

    final sheet = AppSheetRoute<void>(builder: (_) => const SizedBox.shrink());
    expect(sheet, isA<PopupRoute<void>>());
    expect(sheet.isScrollControlled, isFalse);
  });

  testWidgets('showAppDialog：弹出、渲染并原样返回结果', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    late BuildContext hostContext;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Navigator(
          key: navKey,
          onGenerateRoute: (RouteSettings settings) => PageRouteBuilder<void>(
            pageBuilder: (context, animation, secondaryAnimation) => Builder(
              builder: (context) {
                hostContext = context;
                return const Text('宿主页');
              },
            ),
          ),
        ),
      ),
    );

    final Future<String?> result = showAppDialog<String>(
      hostContext,
      builder: (_) => const Text('对话框内容'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('对话框内容'), findsOneWidget);

    navKey.currentState!.pop('已确认');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(await result, '已确认');
  });

  testWidgets('MiuixCompat：子树获得 Material 祖先 / MaterialLocalizations / SDK Theme',
      (tester) async {
    late legacy.MaterialLocalizations localizations;
    late Brightness brightness;
    await tester.pumpWidget(
      AppThemeHost(
        tokens: AppThemeHost.tokensFor(Brightness.dark),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MiuixCompat(
            child: Builder(builder: (context) {
              localizations = legacy.MaterialLocalizations.of(context);
              brightness = legacy.Theme.of(context).brightness;
              // Material 祖先存在时该调用不抛（flutter_miuix 的 TextField 依赖）。
              legacy.Material.of(context);
              return const SizedBox.shrink();
            }),
          ),
        ),
      ),
    );
    expect(localizations.cutButtonLabel, isNotEmpty);
    expect(brightness, Brightness.dark);
  });

  testWidgets('AppShell：过渡期 Material 主题/本地化齐备（MaterialApp 等价面）',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    final theme = AppTheme.lightFor();
    late modern.ThemeData seenTheme;
    late modern.MaterialLocalizations localizations;

    await tester.pumpWidget(
      AppShell(
        title: 'WinWin',
        isDark: false,
        navigatorKey: navKey,
        escapeObserver: AppEscapeNavigatorObserver(),
        theme: theme,
        home: Builder(builder: (context) {
          // 应用侧主题/本地化消费者走 material_ui（SDK material 仅服务 flutter_miuix
          // 内部组件，见 MiuixCompat）。
          seenTheme = modern.Theme.of(context);
          localizations = modern.MaterialLocalizations.of(context);
          return const Text('首页');
        }),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // 过渡期主题：B2 迁移 Theme.of 消费者前，Material 控件仍须拿到应用主题。
    expect(seenTheme.brightness, theme.brightness);
    expect(seenTheme.colorScheme.primary, theme.colorScheme.primary);
    // 本地化：material_ui 侧的 MaterialLocalizations 不得缺失（Material 控件依赖；
    // SDK 的 Global* 委托实现的是 SDK 类型，不可互换）。
    expect(localizations.cutButtonLabel, isNotEmpty);
    // 文本基底：显式 DefaultTextStyle（非 WidgetsApp 的"黄绿双下划线"错误样式）。
    expect(
      DefaultTextStyle.of(tester.element(find.text('首页'))).style.decoration,
      TextDecoration.none,
    );
  });

  testWidgets('AppShell：WidgetsApp 壳可挂首页、注入 Token、路由走 AppRoute',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    final escapeObserver = AppEscapeNavigatorObserver();
    late AppTokens tokens;

    await tester.pumpWidget(
      AppShell(
        title: 'WinWin',
        isDark: true,
        navigatorKey: navKey,
        escapeObserver: escapeObserver,
        home: Builder(builder: (context) {
          tokens = AppThemeHost.of(context);
          return const Text('首页');
        }),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('首页'), findsOneWidget);
    expect(tokens.isDark, isTrue);

    navKey.currentState!.push(AppRoute<void>(builder: (_) => const Text('二级页')));
    await tester.pump();
    expect(find.byType(MiuixPageTransition), findsWidgets);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('二级页'), findsOneWidget);
  });
}
