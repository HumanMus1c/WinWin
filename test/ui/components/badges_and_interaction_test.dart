import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/common/widgets/level_badge.dart';
import 'package:winwin/common/widgets/medal_widget.dart';
import 'package:winwin/theme/contrast_policy.dart';
import 'package:winwin/theme/inherited_ui_style.dart';
import 'package:winwin/theme/ui_style.dart';
import 'package:winwin/ui/components/app_components.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserVipBadge Tests', () {
    test('resolveUserVipBadgeLabel behaves accurately', () {
      expect(resolveUserVipBadgeLabel('十年大会员', 2), '十年大会员');
      expect(resolveUserVipBadgeLabel('   ', 2), '年度大会员');
      expect(resolveUserVipBadgeLabel(null, 2), '年度大会员');
      expect(resolveUserVipBadgeLabel(null, 1), '大会员');
      expect(resolveUserVipBadgeLabel(null, 0), '大会员');
    });

    test('resolveVipBadgeColors ensures WCAG 4.5:1 contrast', () {
      final accessible = resolveVipBadgeColors(
        containerColor: const Color(0xFFFFD8E4), // 浅粉色
        preferredContentColor: const Color(0xFF31111D), // 深暗色
        surfaceColor: Colors.white,
        onSurface: Colors.black,
        onBackground: Colors.black,
        inverseOnSurface: Colors.white,
      );

      expect(accessible.containerColor, isNotNull);
      expect(accessible.contentColor, isNotNull);
      final contrast = calculateContrastRatio(
        accessible.contentColor,
        accessible.containerColor,
      );
      expect(contrast, greaterThanOrEqualTo(kAccessibleTextMinContrast));
    });

    testWidgets('UserVipBadge renders properly in regular and compact modes',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                UserVipBadge(vipType: 2),
                UserVipBadge(vipType: 1, compact: true),
              ],
            ),
          ),
        ),
      );

      expect(find.text('年度大会员'), findsOneWidget);
      expect(find.text('大会员'), findsOneWidget);
    });
  });

  group('OfficialVerifyBadge Tests', () {
    test('resolveOfficialVerifyBadge accurately determines tone and text', () {
      final personal = resolveOfficialVerifyBadge(0, title: '知名UP主');
      expect(personal, isNotNull);
      expect(personal!.tone, OfficialVerifyBadgeTone.personal);
      expect(personal.text, '知名UP主');

      final org = resolveOfficialVerifyBadge(1, desc: '官方认证机构');
      expect(org, isNotNull);
      expect(org!.tone, OfficialVerifyBadgeTone.organization);
      expect(org.text, '官方认证机构');

      final invalid = resolveOfficialVerifyBadge(-1);
      expect(invalid, isNull);
    });

    test('resolveOfficialVerifyBadgeFromRole distinguishes organization roles', () {
      final orgRole = resolveOfficialVerifyBadgeFromRole(1, 3);
      expect(orgRole, isNotNull);
      expect(orgRole!.tone, OfficialVerifyBadgeTone.organization);

      final personalRole = resolveOfficialVerifyBadgeFromRole(0, 1);
      expect(personalRole, isNotNull);
      expect(personalRole!.tone, OfficialVerifyBadgeTone.personal);

      final invalid = resolveOfficialVerifyBadgeFromRole(-1, 3);
      expect(invalid, isNull);
    });

    testWidgets('OfficialVerifyBadge renders in both Tag and Avatar modes',
        (tester) async {
      final personalSpec = resolveOfficialVerifyBadge(0, title: 'bilibili 知名UP主')!;
      final orgSpec = resolveOfficialVerifyBadge(1, title: '官方机构')!;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                OfficialVerifyBadge(badge: personalSpec),
                OfficialVerifyBadge(badge: orgSpec, compact: true),
              ],
            ),
          ),
        ),
      );

      expect(find.text('bilibili 知名UP主'), findsOneWidget);
      expect(find.byIcon(Icons.bolt), findsOneWidget);
    });
  });

  group('AppDesktopInteraction Tests', () {
    testWidgets('AppDesktopInteraction renders child and triggers tap',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppDesktopInteraction(
              onTap: () => tapped = true,
              child: const Text('Desktop Target'),
            ),
          ),
        ),
      );

      expect(find.text('Desktop Target'), findsOneWidget);
      await tester.tap(find.text('Desktop Target'));
      expect(tapped, isTrue);
    });
  });

  group('AppPressFeedback Tests', () {
    testWidgets('AppPressFeedback scales down on tap down and rebounds',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppPressFeedback(
              onTap: () => tapped = true,
              child: const SizedBox(
                width: 100,
                height: 50,
                child: Text('Press Target'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Press Target'), findsOneWidget);
      await tester.tap(find.text('Press Target'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });
  });

  group('LevelBadge & MedalWidget Dual Style Tests', () {
    testWidgets('renders LevelBadge in Material 3 and Miuix without crash',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                UiStyleScope(
                  style: UiStyle.material3,
                  child: LevelBadge(level: 6),
                ),
                UiStyleScope(
                  style: UiStyle.miuix,
                  child: LevelBadge(level: 5),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(LevelBadge), findsNWidgets(2));
    });

    testWidgets('renders MedalWidget in Material 3 and Miuix without crash',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                UiStyleScope(
                  style: UiStyle.material3,
                  child: MedalWidget(
                    medalName: '牌子A',
                    level: 16,
                    backgroundColor: Color(0xFFFB7299),
                  ),
                ),
                UiStyleScope(
                  style: UiStyle.miuix,
                  child: MedalWidget(
                    medalName: '牌子B',
                    level: 20,
                    backgroundColor: Color(0xFF00A1D6),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('牌子A'), findsOneWidget);
      expect(find.text('16'), findsOneWidget);
      expect(find.text('牌子B'), findsOneWidget);
      expect(find.text('20'), findsOneWidget);
    });

    testWidgets('renders AppSwitch and AppSegmentedControl in both styles',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const UiStyleScope(
                  style: UiStyle.material3,
                  child: AppSwitch(value: true, onChanged: null),
                ),
                const UiStyleScope(
                  style: UiStyle.miuix,
                  child: AppSwitch(value: false, onChanged: null),
                ),
                UiStyleScope(
                  style: UiStyle.material3,
                  child: AppSegmentedControl<int>(
                    value: 0,
                    segments: const [(0, 'Tab1'), (1, 'Tab2')],
                    onChanged: (_) {},
                  ),
                ),
                UiStyleScope(
                  style: UiStyle.miuix,
                  child: AppSegmentedControl<int>(
                    value: 1,
                    segments: const [(0, 'TabA'), (1, 'TabB')],
                    onChanged: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Tab1'), findsOneWidget);
      expect(find.text('TabA'), findsOneWidget);
    });
  });
}
