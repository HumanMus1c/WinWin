import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/common/skeleton/skeleton.dart';
import 'package:winwin/common/skeleton/video_card_h.dart';
import 'package:winwin/common/skeleton/video_card_v.dart';

void main() {
  group('Skeleton Primitives Tests', () {
    testWidgets('SkeletonBox renders with correct dimensions and shape', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SkeletonBox(
              width: 100,
              height: 50,
            ),
          ),
        ),
      );

      final boxFinder = find.byType(SkeletonBox);
      expect(boxFinder, findsOneWidget);

      final containerFinder = find.descendant(of: boxFinder, matching: find.byType(Container));
      expect(containerFinder, findsOneWidget);
    });

    testWidgets('SkeletonLine renders with specified or default height', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SkeletonLine(
              width: 120,
              height: 16,
            ),
          ),
        ),
      );

      expect(find.byType(SkeletonLine), findsOneWidget);
      expect(find.byType(SkeletonBox), findsOneWidget);
    });

    testWidgets('SkeletonCircle renders circular box with radius/size', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SkeletonCircle(radius: 20),
          ),
        ),
      );

      final circleFinder = find.byType(SkeletonCircle);
      expect(circleFinder, findsOneWidget);

      final circleWidget = tester.widget<SkeletonCircle>(circleFinder);
      expect(circleWidget.size, 40);
    });
  });

  group('Video Card Skeleton Tests', () {
    testWidgets('VideoCardVSkeleton renders properly with Card shell', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VideoCardVSkeleton(),
          ),
        ),
      );

      expect(find.byType(VideoCardVSkeleton), findsOneWidget);
      expect(find.byType(Card), findsOneWidget);
      expect(find.byType(Skeleton), findsOneWidget);
    });

    testWidgets('VideoCardHSkeleton renders with inCard true and false', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                VideoCardHSkeleton(inCard: true),
                VideoCardHSkeleton(inCard: false),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(VideoCardHSkeleton), findsNWidgets(2));
      expect(find.byType(Card), findsOneWidget);
    });
  });
}
