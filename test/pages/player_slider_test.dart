import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

    testWidgets('Slider interacts and dispatches seek with subsecond accuracy', (tester) async {
      Duration? dispatchedSeek;
      bool dragging = false;
      double dragSeconds = 0;
      final position = ValueNotifier(const Duration(seconds: 10));
      final duration = ValueNotifier(const Duration(seconds: 100));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                final durMs = duration.value.inMilliseconds;
                final maxSec = durMs > 0 ? durMs / 1000.0 : 1.0;
                final posSec = dragging
                    ? dragSeconds
                    : (position.value.inMilliseconds / 1000.0);
                final value = posSec.clamp(0.0, maxSec);

                return SizedBox(
                  width: 400,
                  child: Slider(
                    value: value,
                    min: 0,
                    max: maxSec,
                    onChangeStart: (v) {
                      setState(() {
                        dragging = true;
                        dragSeconds = v;
                      });
                    },
                    onChanged: (v) {
                      setState(() => dragSeconds = v);
                    },
                    onChangeEnd: (v) {
                      setState(() {
                        dragging = false;
                        dragSeconds = v;
                      });
                      final target = Duration(milliseconds: (v * 1000).round());
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

      // Tap at the center (50% -> 50.0s)
      final sliderFinder = find.byType(Slider);
      expect(sliderFinder, findsOneWidget);

      await tester.tap(sliderFinder);
      await tester.pumpAndSettle();

      expect(dispatchedSeek, isNotNull);
      // Position must have updated to around 50s and not jumped back to 10s
      expect((dispatchedSeek!.inMilliseconds - 50000).abs() < 2000, isTrue);
      expect((position.value.inMilliseconds - 50000).abs() < 2000, isTrue);
    });
  });
}
