import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/common/widgets/level_badge.dart';
import 'package:winwin/common/widgets/medal_widget.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:winwin/theme/contrast_policy.dart';
import 'package:winwin/ui/components/app_components.dart';

import '../../support/app_test_host.dart';

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
        surfaceColor: const Color(0xFFFFFFFF),
        onSurface: const Color(0xFF000000),
        onBackground: const Color(0xFF000000),
        inverseOnSurface: const Color(0xFFFFFFFF),
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
        const AppTestApp(
          home: AppTestScaffold(
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
        AppTestApp(
          home: AppTestScaffold(
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
      expect(find.byIcon(CupertinoIcons.bolt), findsOneWidget);
    });
  });

  group('AppDesktopInteraction Tests', () {
    testWidgets('AppDesktopInteraction renders child and triggers tap',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        AppTestApp(
          home: AppTestScaffold(
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
        AppTestApp(
          home: AppTestScaffold(
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

  group('LevelBadge & MedalWidget 单轨渲染测试（阶段5d-L4-2）', () {
    testWidgets('renders LevelBadge without crash', (tester) async {
      await tester.pumpWidget(
        const AppTestApp(
          home: AppTestScaffold(
            body: LevelBadge(level: 6),
          ),
        ),
      );

      expect(find.byType(LevelBadge), findsOneWidget);
    });

    testWidgets('renders MedalWidget without crash', (tester) async {
      await tester.pumpWidget(
        const AppTestApp(
          home: AppTestScaffold(
            body: MedalWidget(
              medalName: '牌子A',
              level: 16,
              backgroundColor: Color(0xFFFB7299),
            ),
          ),
        ),
      );

      expect(find.text('牌子A'), findsOneWidget);
      expect(find.text('16'), findsOneWidget);
    });

    testWidgets('renders AppSwitch and AppSegmentedControl via flutter_miuix',
        (tester) async {
      await tester.pumpWidget(
        AppTestApp(
          home: AppTestScaffold(
            body: Column(
              children: [
                const AppSwitch(value: true, onChanged: null),
                AppSegmentedControl<int>(
                  value: 1,
                  segments: const [(0, 'TabA'), (1, 'TabB')],
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('TabA'), findsOneWidget);
      // 阶段5d-L1/L4-2：M3 冻结分支与双风格宿主均已移除——恒渲染 flutter_miuix 组件。
      expect(find.byType(MiuixSwitch), findsOneWidget);
      // 不得出现 Material 的 Switch（按 runtimeType 判定，避免直接依赖 material_ui）。
      expect(
        find.byWidgetPredicate((w) => w.runtimeType.toString() == 'Switch'),
        findsNothing,
      );
      expect(find.byType(MiuixTabRow), findsOneWidget);
    });
  });
}