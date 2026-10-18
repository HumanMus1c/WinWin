import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/pages/danmaku/controller.dart';
import 'package:winwin/plugin/canvas_danmaku/canvas_danmaku.dart';

import '../support/app_test_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Danmaku Controller & Screen Tests', () {
    test('WinWinDanmakuController lifecycle and isDisposed state', () {
      final dm = WinWinDanmakuController(cid: 123456);
      expect(dm.isDisposed, isFalse);
      expect(dm.cid, 123456);

      // startMs > endMs 应当立即返回空列表，避免 .clamp() 倒流造成重复拉取
      expect(dm.getDanmakuRange(200, 100), isEmpty);

      dm.dispose();
      expect(dm.isDisposed, isTrue);
      expect(dm.getDanmakuRange(0, 1000), isEmpty);
    });

    testWidgets('DanmakuScreen handles zero size and small height without throwing RangeError', (tester) async {
      DanmakuController<dynamic>? engine;

      const option = DanmakuOption(
        fontSize: 15,
        area: 1.0,
        safeArea: true,
        duration: 7.0,
        staticDuration: 4.0,
      );

      await tester.pumpWidget(
        AppTestApp(
          home: AppTestScaffold(
            body: DanmakuScreen<dynamic>(
              createdController: (c) {
                engine = c;
              },
              option: option,
              size: Size.zero,
            ),
          ),
        ),
      );

      expect(engine, isNotNull);
      expect(engine!.getTrackCount(), 0);

      // 模拟最大化后尺寸突增
      await tester.pumpWidget(
        AppTestApp(
          home: AppTestScaffold(
            body: DanmakuScreen<dynamic>(
              createdController: (c) {
                engine = c;
              },
              option: option,
              size: const Size(1920, 1080),
            ),
          ),
        ),
      );

      expect(engine!.getTrackCount(), greaterThan(0));

      // 模拟尺寸收缩到非常小（导致 area ~/ height - 1 < 0）
      await tester.pumpWidget(
        AppTestApp(
          home: AppTestScaffold(
            body: DanmakuScreen<dynamic>(
              createdController: (c) {
                engine = c;
              },
              option: option,
              size: const Size(100, 10),
            ),
          ),
        ),
      );

      // 应安全回退到 0，不崩溃
      expect(engine!.getTrackCount(), 0);
    });
  });
}