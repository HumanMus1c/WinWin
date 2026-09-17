import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/ui/components/glass_contrast_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ContrastStyle Tests', () {
    test('glyphShadows has 4 directional coverage', () {
      expect(ContrastStyle.glyphShadows.length, 4);
      expect(ContrastStyle.glyphShadows[0].blurRadius, 3.0);
      expect(ContrastStyle.boldGlyphShadows.length, 4);
      expect(ContrastStyle.boldGlyphShadows[0].blurRadius, 4.0);
    });

    test('labelStyle includes glyphShadows', () {
      expect(ContrastStyle.labelStyle.shadows, ContrastStyle.glyphShadows);
      expect(ContrastStyle.labelStyle.color, Colors.white);
    });
  });

  group('GlassCapsule Widget Tests', () {
    testWidgets('Renders with BackdropFilter and ClipRRect for rectangle shape',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GlassCapsule(
              blur: 14.0,
              borderRadius: 10.0,
              child: Text('Hello Glass'),
            ),
          ),
        ),
      );

      final clipFinder = find.byType(ClipRRect);
      expect(clipFinder, findsOneWidget);

      final filterFinder = find.byType(BackdropFilter);
      expect(filterFinder, findsOneWidget);

      final filter = tester.widget<BackdropFilter>(filterFinder);
      expect(filter.filter, ImageFilter.blur(sigmaX: 14.0, sigmaY: 14.0));
      expect(find.text('Hello Glass'), findsOneWidget);
    });

    testWidgets('Renders with ClipOval when shape is circle', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GlassCapsule(
              shape: BoxShape.circle,
              blur: 16.0,
              child: Icon(Icons.play_arrow),
            ),
          ),
        ),
      );

      expect(find.byType(ClipOval), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('Omits BackdropFilter when blur is 0', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GlassCapsule(
              blur: 0,
              child: Text('No Blur'),
            ),
          ),
        ),
      );

      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.text('No Blur'), findsOneWidget);
    });
  });

  group('ContrastIcon & ContrastText Tests', () {
    testWidgets('ContrastIcon applies shadows correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ContrastIcon(
              Icons.star,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      );

      final iconFinder = find.byType(Icon);
      expect(iconFinder, findsOneWidget);

      final icon = tester.widget<Icon>(iconFinder);
      expect(icon.icon, Icons.star);
      expect(icon.shadows, ContrastStyle.glyphShadows);
    });

    testWidgets('ContrastText retains shadows', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ContrastText('High Contrast Text'),
          ),
        ),
      );

      final textFinder = find.byType(Text);
      expect(textFinder, findsOneWidget);

      final text = tester.widget<Text>(textFinder);
      expect(text.data, 'High Contrast Text');
      expect(text.style?.shadows, ContrastStyle.glyphShadows);
    });
  });

  group('GlassControlButton Tests', () {
    testWidgets('Tap triggers onPressed and displays tooltip', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GlassControlButton(
              icon: Icons.play_arrow,
              tooltip: '播放',
              useGlass: true,
              onPressed: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.byType(Tooltip), findsOneWidget);
      expect(find.byType(GlassCapsule), findsOneWidget);

      await tester.tap(find.byType(GlassControlButton));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });
  });

  group('ProgressiveGlass Widget Tests', () {
    testWidgets('Renders with multiple sliced BackdropFilter layers',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProgressiveGlass(
              blur: 16.0,
              slices: 8,
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              child: Text('Progressive Blur Content'),
            ),
          ),
        ),
      );

      expect(find.byType(ClipRect), findsWidgets);
      expect(find.byType(BackdropFilter), findsWidgets);
      expect(find.text('Progressive Blur Content'), findsOneWidget);
    });

    testWidgets('Omits BackdropFilter when blur is 0',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProgressiveGlass(
              blur: 0,
              child: Text('Zero Blur Progressive'),
            ),
          ),
        ),
      );

      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.text('Zero Blur Progressive'), findsOneWidget);
    });

    testWidgets('Uses ClipRRect when borderRadius is specified', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProgressiveGlass(
              blur: 12.0,
              slices: 6,
              borderRadius: BorderRadius.circular(8.0),
              child: const Text('Rounded Glass'),
            ),
          ),
        ),
      );

      expect(find.byType(ClipRRect), findsOneWidget);
      expect(find.byType(BackdropFilter), findsWidgets);
      expect(find.text('Rounded Glass'), findsOneWidget);
    });
  });
}
