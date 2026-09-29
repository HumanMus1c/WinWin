import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/theme/app_theme.dart';

Future<void> _pumpAndShow(
  WidgetTester tester,
  String message, {
  Size surface = const Size(1280, 800),
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = surface;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      scaffoldMessengerKey: appScaffoldMessengerKey,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showToast(context, message),
              child: const Text('show'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('show'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

double _cardWidth(WidgetTester tester) {
  final messageText = find.descendant(of: find.byType(SnackBar), matching: find.byType(Text));
  final card = find.ancestor(of: messageText, matching: find.byType(Material)).first;
  return tester.getSize(card).width;
}

void main() {
  testWidgets('短消息：宽度自适应内容（明显小于封顶）', (tester) async {
    await _pumpAndShow(tester, '已复制 BV 号：BV1xx411c7mD');
    final width = _cardWidth(tester);
    debugPrint('PROBE_SHORT width=$width');
    expect(width, lessThan(400));
    expect(width, greaterThan(80));
  });

  testWidgets('长消息（含 URL）：封顶 400 并换行', (tester) async {
    await _pumpAndShow(
      tester,
      '请求错误：Connection failed\n'
      'https://api.bilibili.com/x/player/playurl?avid=123456&cid=789012345678&platform=pc&high_quality=1',
    );
    final width = _cardWidth(tester);
    debugPrint('PROBE_LONG width=$width');
    expect(width, lessThanOrEqualTo(400));
    expect(width, greaterThan(280));
  });

  testWidgets('窄窗口：遵守屏幕留白约束', (tester) async {
    await _pumpAndShow(
      tester,
      '请求错误：Connection failed\nhttps://api.bilibili.com/very/long/path?with=query&and=more',
      surface: const Size(360, 640),
    );
    final scaffoldCtx = tester.element(find.byType(Scaffold));
    debugPrint(
      'PROBE_NARROW_ENV mq=${MediaQuery.sizeOf(scaffoldCtx)} '
      'dpr=${tester.view.devicePixelRatio} view=${tester.view.physicalSize}',
    );
    final width = _cardWidth(tester);
    debugPrint('PROBE_NARROW width=$width');
    expect(width, lessThanOrEqualTo(360 - 32));
  });
}
