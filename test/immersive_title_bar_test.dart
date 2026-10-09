import 'dart:ui' as ui;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';
import 'package:winwin/core/shell/app_routes.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/core/shell/app_transition.dart';
import 'package:winwin/theme/app_theme.dart';
import 'package:winwin/ui/components/immersive_title_bar.dart';

/// 沉浸标题条布局与页面转场回归测试。
///
/// 防回归点：
/// 1. 标题条高度（Win11 标准 32 逻辑像素）、右上三键尺寸与排列（46×32）、
///    拖动区占满其余宽度；
/// 2. 页面转场主题注册：windows/linux/android/fuchsia → Miuix 转场，
///    iOS/macOS → Cupertino（保留侧滑返回手势语义）；
/// 3. **进出页面（push/pop）全程，路由内容与转场缩放溢出不得覆盖标题条**——
///    该用例在"内容区无裁剪 + 溢出型转场"组合下精确失败
///    （2026-10-07 实证：无裁剪 + Zoom 转场时标题条下半部被旧页覆盖）。
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

  test('路由替身：AppRoute 承载 Miuix 转场核与统一时长（B3 起唯一页面路由）', () {
    final route = AppRoute<void>(builder: (_) => const SizedBox.shrink());
    expect(route.transitionDuration, kMiuixTransitionDuration);
    expect(route.reverseTransitionDuration, kMiuixTransitionDuration);
    // Material 侧转场主题已退役：过渡期主题不再注册 pageTransitionsTheme 覆写。
    for (final theme in [AppTheme.lightFor(), AppTheme.darkFor()]) {
      expect(
        theme.pageTransitionsTheme.builders[TargetPlatform.windows],
        isNot(isA<CupertinoPageTransitionsBuilder>()),
      );
    }
  });

  testWidgets('Miuix 转场：进出页面全程标题条零覆盖', (tester) async {
    await _runTransitionCoverageScenario(
      tester,
      label: 'Miuix 转场',
      transitions: AppTheme.lightFor().pageTransitionsTheme,
    );
  });

  testWidgets('兜底防线：即使换回会溢出的 Zoom 转场，标题条仍零覆盖', (tester) async {
    await _runTransitionCoverageScenario(
      tester,
      label: 'Zoom 转场（兜底防线）',
      // 模拟"回退到 material_ui 默认转场"或未来引入溢出型转场的场景：
      // 内容区裁剪（ClipRect）必须让标题条保持不被覆盖。
      transitions: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  });
}

/// 标题条底色（B2 起标题条改读 Token 通道：`AppTokens.colors.background`，
/// 取值即 [AppPalette.light] 的应用背景色）。
final String _stripHex = () {
  final argb = AppPalette.light.background.toARGB32().toRadixString(16);
  return argb.length >= 8 ? argb.substring(2) : argb.padLeft(6, '0');
}();

/// 标题条内的采样行（避开左端图标与右端三键）。
const List<int> _stripRows = <int>[2, 10, 16, 22, 28, 31];

/// 页面内容底色：旧页红 / 新页蓝。
const Color _homeColor = Color(0xFFFF0000);
const Color _pushedColor = Color(0xFF0000FF);

/// 执行一次"push → 等待 → pop"转场，并逐帧断言标题条未被页面内容覆盖。
Future<void> _runTransitionCoverageScenario(
  WidgetTester tester, {
  required String label,
  required PageTransitionsTheme transitions,
}) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final navKey = GlobalKey<NavigatorState>();
  final boundaryKey = GlobalKey();

  await tester.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightFor().copyWith(
          pageTransitionsTheme: transitions,
        ),
        navigatorKey: navKey,
        builder: (context, child) =>
            ImmersiveTitleBarShell(child: child ?? const SizedBox.shrink()),
        home: const ColoredBox(color: _homeColor, child: SizedBox.expand()),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
  await _expectStripIntact(tester, boundaryKey, '$label 初始态');

  navKey.currentState!.push(
        AppRoute<void>(
      builder: (_) =>
          const ColoredBox(color: _pushedColor, child: SizedBox.expand()),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 40));
    await _expectStripIntact(tester, boundaryKey, '$label push+${(i + 1) * 40}ms');
  }
  await tester.pump(const Duration(milliseconds: 400));
  await _expectStripIntact(tester, boundaryKey, '$label push 结束');
  // 转场已结束：内容区应是新页（蓝）——确认本场景确实发生了路由跳转。
  expect(
    await _bodyHex(tester, boundaryKey),
    '0000ff',
    reason: '$label：push 结束后内容区应为新页底色',
  );

  navKey.currentState!.pop();
  await tester.pump();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 40));
    await _expectStripIntact(tester, boundaryKey, '$label pop+${(i + 1) * 40}ms');
  }
  await tester.pump(const Duration(milliseconds: 400));
  await _expectStripIntact(tester, boundaryKey, '$label pop 结束');
  expect(
    await _bodyHex(tester, boundaryKey),
    'ff0000',
    reason: '$label：pop 结束后内容区应回到首页底色',
  );

  debugDefaultTargetPlatformOverride = null;
}

/// 断言标题条采样行全部保持壳层底色（未被任何页面内容覆盖）。
Future<void> _expectStripIntact(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String phase,
) async {
  final samples = await _sample(tester, boundaryKey);
  final covered = <String>[
    for (final row in _stripRows)
      if (samples['$row:600'] != _stripHex)
        'y$row=${samples['$row:600']}',
  ];
  expect(
    covered,
    isEmpty,
    reason: '$phase：标题条被页面内容覆盖（$covered，应为全 $_stripHex）',
  );
}

/// 内容区采样（y=100，避开转场期间缩放入场带来的边界）。
Future<String> _bodyHex(WidgetTester tester, GlobalKey boundaryKey) async {
  final samples = await _sample(tester, boundaryKey);
  return samples['100:600']!;
}

/// 抓取整窗画面并按 "y:x" 采样十六进制颜色（物理像素 = 逻辑像素，DPR 固定 1.0）。
Future<Map<String, String>> _sample(
  WidgetTester tester,
  GlobalKey boundaryKey,
) async {
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  var width = 0;
  late ByteData bytes;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    width = image.width;
    bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    image.dispose();
  });

  String hex(int x, int y) {
    final offset = (y * width + x) * 4;
    String h(int value) => value.toRadixString(16).padLeft(2, '0');
    return '${h(bytes.getUint8(offset))}${h(bytes.getUint8(offset + 1))}'
        '${h(bytes.getUint8(offset + 2))}';
  }

  return <String, String>{
    for (final y in _stripRows) '$y:600': hex(600, y),
    '100:600': hex(600, 100),
  };
}
