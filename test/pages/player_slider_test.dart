import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_test_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Player Progress Slider Tests', () {
    test('Millisecond precision prevents fractional second jumps', () {
      const dur = Duration(seconds: 120, milliseconds: 500);
      const pos = Duration(seconds: 15, milliseconds: 400);

      final durMs = dur.inMilliseconds;
      final maxSec = durMs > 0 ? durMs / 1000.0 : 1.0;
      final posSec = pos.inMilliseconds / 1000.0;
      final value = posSec.clamp(0.0, maxSec);

      expect(maxSec, 120.5);
      expect(posSec, 15.4);
      expect(value, 15.4);

      // Verify seek target from slider value v = 15.4 retains 15400ms
      const clickedV = 15.4;
      final seekTarget = Duration(milliseconds: (clickedV * 1000).round());
      expect(seekTarget.inMilliseconds, 15400);
      expect(seekTarget.inSeconds, 15);
    });

    test('Clamping target duration boundary conditions', () {
      const dur = Duration(seconds: 60);
      final durMs = dur.inMilliseconds;

      // Seek beyond end
      final beyondEnd = const Duration(seconds: 70);
      final clampedBeyond = durMs > 0
          ? Duration(milliseconds: beyondEnd.inMilliseconds.clamp(0, durMs))
          : beyondEnd;
      expect(clampedBeyond, const Duration(seconds: 60));

      // Seek before start
      final beforeStart = const Duration(seconds: -5);
      final clampedBefore = durMs > 0
          ? Duration(milliseconds: beforeStart.inMilliseconds.clamp(0, durMs))
          : beforeStart;
      expect(clampedBefore, Duration.zero);
    });

    testWidgets('MiuixSlider 交互按毫秒精度派发 seek（载体现为 flutter_miuix）',
        (tester) async {
      Duration? dispatchedSeek;
      double dragSeconds = 0;
      final position = ValueNotifier(const Duration(seconds: 10));
      final duration = ValueNotifier(const Duration(seconds: 100));

      await tester.pumpWidget(
        AppTestApp(
          home: AppTestScaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                final durMs = duration.value.inMilliseconds;
                final maxSec = durMs > 0 ? durMs / 1000.0 : 1.0;
                final posSec = position.value.inMilliseconds / 1000.0;
                final value = posSec.clamp(0.0, maxSec);

                return SizedBox(
                  width: 400,
                  child: MiuixSlider(
                    value: value,
                    min: 0,
                    max: maxSec,
                    onValueChanged: (v) => setState(() => dragSeconds = v),
                    // MiuixSlider 无「带去参的 onChangeEnd」：以最后值按毫秒
                    // 换算派发 seek（保持「无整秒跳变」精度契约）。
                    onValueChangeFinished: () {
                      final target =
                          Duration(milliseconds: (dragSeconds * 1000).round());
                      position.value = target;
                      dispatchedSeek = target;
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );

      final sliderFinder = find.byType(MiuixSlider);
      expect(sliderFinder, findsOneWidget);

      // 从中心向右拖动一小段后释放（覆盖 起手 → 更新 → 结束 全路径）。
      final center = tester.getCenter(sliderFinder);
      final gesture = await tester.startGesture(center);
      await tester.pump();
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(dispatchedSeek, isNotNull);
      // 终点位于中心（50s）右侧；且按毫秒精确换算（无整秒截断跳变）。
      expect(dispatchedSeek!.inMilliseconds, greaterThan(50000));
      expect(dispatchedSeek, equals(position.value));
      expect(
          dispatchedSeek!.inMilliseconds, equals((dragSeconds * 1000).round()));
    });

    test('Buffered progress preserves highest floor when seeking backwards', () {
      int maxContinuousBufferedMs = 0;
      int calculateBuffered(int posMs, int durMs, int bufDuration) {
        int calculated = posMs + bufDuration;
        if (posMs <= maxContinuousBufferedMs && calculated < maxContinuousBufferedMs) {
          calculated = maxContinuousBufferedMs;
        }
        if (calculated > maxContinuousBufferedMs) {
          maxContinuousBufferedMs = calculated;
        }
        return calculated.clamp(0, durMs);
      }

      const durMs = 120000; // 120s
      // 1. Initial play: at 20s, buffered 30s ahead -> 50s
      final buf1 = calculateBuffered(20000, durMs, 30000);
      expect(buf1, 50000);
      expect(maxContinuousBufferedMs, 50000);

      // 2. Fast forward to 40s (within buffered range), buffered 15s ahead -> 55s
      final buf2 = calculateBuffered(40000, durMs, 15000);
      expect(buf2, 55000);
      expect(maxContinuousBufferedMs, 55000);

      // 3. User seeks back to 10s: demuxer reports small 2s buffer at 10s
      // Without protection, naive posMs + bufMs would collapse to 12s.
      // With protection, it must NOT shrink below 55s!
      final buf3 = calculateBuffered(10000, durMs, 2000);
      expect(buf3, 55000); // Preserved! Does not collapse to 12000!
      expect(maxContinuousBufferedMs, 55000);

      // 4. User seeks far forward to 90s: beyond 55s, buffers 5s ahead -> 95s
      final buf4 = calculateBuffered(90000, durMs, 5000);
      expect(buf4, 95000);
      expect(maxContinuousBufferedMs, 95000);
    });

    testWidgets('Hover preview updates locally without triggering parent rebuilds', (tester) async {
      int parentBuildCount = 0;
      final hoverNotifier = ValueNotifier<({double fraction, double seconds})?>(null);
      const maxSec = 100.0;
      const sliderWidth = 400.0;

      await tester.pumpWidget(
        AppTestApp(
          home: AppTestScaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                parentBuildCount++;
                return SizedBox(
                  width: sliderWidth,
                  height: 60,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ValueListenableBuilder<({double fraction, double seconds})?>(
                        valueListenable: hoverNotifier,
                        builder: (context, hover, _) {
                          if (hover == null) return const SizedBox.shrink();
                          return Positioned(
                            bottom: 28,
                            left: hover.fraction * sliderWidth,
                            child: Text('Hover: ${hover.seconds.toInt()}s'),
                          );
                        },
                      ),
                      MouseRegion(
                        key: const ValueKey('slider_mouse_region'),
                        onHover: (e) {
                          final fraction = (e.localPosition.dx / sliderWidth).clamp(0.0, 1.0);
                          hoverNotifier.value = (
                            fraction: fraction,
                            seconds: fraction * maxSec,
                          );
                        },
                        onExit: (_) {
                          hoverNotifier.value = null;
                        },
                        child: const SizedBox(
                          width: sliderWidth,
                          height: 20,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );

      expect(parentBuildCount, 1);
      expect(find.textContaining('Hover:'), findsNothing);

      // Simulate mouse hover at x = 200 (50%)
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      final mouseRegionFinder = find.byKey(const ValueKey('slider_mouse_region'));
      await gesture.moveTo(tester.getCenter(mouseRegionFinder));
      await tester.pump();

      // Tooltip is rendered!
      expect(find.textContaining('Hover: 50s'), findsOneWidget);
      // Crucial assertion: Parent build count must STILL be 1! (Zero setState, zero parent rebuild!)
      expect(parentBuildCount, 1);

      // Move mouse to x = 300 (75%)
      await gesture.moveTo(tester.getTopLeft(mouseRegionFinder) + const Offset(300, 10));
      await tester.pump();

      expect(find.textContaining('Hover: 75s'), findsOneWidget);
      expect(parentBuildCount, 1);

      // Move mouse out
      await gesture.moveTo(const Offset(600, 600));
      await tester.pump();

      expect(find.textContaining('Hover:'), findsNothing);
      expect(parentBuildCount, 1);

      await gesture.removePointer();
    });
  });
}
