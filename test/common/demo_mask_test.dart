import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/common/skeleton/skeleton.dart';
import 'package:winwin/common/widgets/demo_mask.dart';
import 'package:winwin/core/storage/storage_pref.dart';

import '../support/app_test_host.dart';

void main() {
  tearDown(() {
    Pref.demoModeNotifier.value = false;
  });

  group('DemoMask Tests', () {
    testWidgets('演示开启显示骨架，关闭恢复真实内容', (tester) async {
      Widget build() => AppTestApp(
            home: DemoMask(
              skeleton: () => const Text('skeleton'),
              child: () => const Text('content'),
            ),
          );

      await tester.pumpWidget(build());
      expect(find.text('content'), findsOneWidget);
      expect(find.text('skeleton'), findsNothing);

      Pref.demoModeNotifier.value = true;
      await tester.pump();
      expect(find.text('skeleton'), findsOneWidget);
      expect(find.text('content'), findsNothing);

      Pref.demoModeNotifier.value = false;
      await tester.pump();
      expect(find.text('content'), findsOneWidget);
      expect(find.text('skeleton'), findsNothing);
    });

    testWidgets('DemoListSkeleton 渲染为列表骨架', (tester) async {
      await tester.pumpWidget(
        const AppTestApp(
          home: AppTestScaffold(
            body: DemoListSkeleton(itemCount: 3),
          ),
        ),
      );

      expect(find.byType(DemoListSkeleton), findsOneWidget);
      expect(find.byType(SkeletonLine), findsNWidgets(6));
    });
  });
}