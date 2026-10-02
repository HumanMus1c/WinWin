import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/inherited_ui_style.dart';
import 'package:winwin/theme/miuix_theme_bridge.dart';
import 'package:winwin/theme/ui_style.dart';
import 'package:winwin/ui/components/app_components.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Miuix 桥接配色（阶段1）', () {
    test('浅色按 colors.dart 的 miuix 调色板逐字段映射', () {
      final colors = miuixBridgeLightColors();
      expect(colors.primary, miuixLightPrimary);
      expect(colors.onPrimary, miuixLightOnPrimary);
      expect(colors.primaryContainer, miuixLightPrimaryContainer);
      expect(colors.background, miuixLightBackground);
      expect(colors.surface, miuixLightSurface);
      expect(colors.surfaceContainer, miuixLightSurfaceContainer);
      expect(colors.surfaceContainerHighest, miuixLightSurfaceContainerHighest);
      expect(colors.onSurface, miuixLightOnSurface);
      expect(colors.outline, miuixLightOutline);
      expect(colors.dividerLine, miuixLightOutlineVariant);
      expect(colors.error, miuixLightError);
    });

    test('深色按 colors.dart 的 miuix 调色板逐字段映射', () {
      final colors = miuixBridgeDarkColors();
      expect(colors.primary, miuixDarkPrimary);
      expect(colors.background, miuixDarkBackground);
      expect(colors.surface, miuixDarkSurface);
      expect(colors.surfaceContainer, miuixDarkSurfaceContainer);
      expect(colors.onSurface, miuixDarkOnSurface);
      expect(colors.dividerLine, miuixDarkOutlineVariant);
      expect(colors.error, miuixDarkError);
    });

    test('字体非空时注入全部 14 个文本样式字段', () {
      final styles = miuixBridgeTextStyles('Microsoft YaHei');
      final all = [
        styles.main,
        styles.paragraph,
        styles.body1,
        styles.body2,
        styles.button,
        styles.footnote1,
        styles.footnote2,
        styles.headline1,
        styles.headline2,
        styles.subtitle,
        styles.title1,
        styles.title2,
        styles.title3,
        styles.title4,
      ];
      expect(all, hasLength(14));
      for (final style in all) {
        expect(style.fontFamily, 'Microsoft YaHei');
      }
      expect(miuixBridgeTextStyles(null).main.fontFamily, isNull);
    });
  });

  group('Miuix 组件替换（阶段1）', () {
    Widget wrapMiuix(Widget child, {bool dark = false}) => MaterialApp(
          home: MiuixThemeScope(
            isDark: dark,
            child: UiStyleScope(
              style: UiStyle.miuix,
              child: Scaffold(body: Center(child: child)),
            ),
          ),
        );

    testWidgets('miuix 风格：四类控件替换为 Miuix 原生组件', (tester) async {
      var toggled = false;
      await tester.pumpWidget(
        wrapMiuix(
          Column(
            children: [
              AppSwitch(value: false, onChanged: (v) => toggled = v),
              AppPrimaryButton(onPressed: () {}, child: const Text('确定')),
              const AppCard(child: Text('卡片')),
              const AppProgressBar(value: 0.5),
            ],
          ),
        ),
      );

      expect(find.byType(MiuixSwitch), findsOneWidget);
      expect(find.byType(MiuixButton), findsOneWidget);
      expect(find.byType(MiuixCard), findsOneWidget);
      expect(find.byType(MiuixLinearProgressIndicator), findsOneWidget);

      await tester.tap(find.byType(MiuixSwitch));
      await tester.pumpAndSettle();
      expect(toggled, isTrue);
    });

    testWidgets('material3 风格：四类控件保持原实现（无 Miuix 组件）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: UiStyleScope(
            style: UiStyle.material3,
            child: Scaffold(
              body: Column(
                children: [
                  AppSwitch(value: false, onChanged: (_) {}),
                  AppPrimaryButton(onPressed: () {}, child: const Text('确定')),
                  const AppCard(child: Text('卡片')),
                  const AppProgressBar(value: 0.5),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.byType(Switch), findsOneWidget);
      expect(find.byType(MiuixSwitch), findsNothing);
      expect(find.byType(MiuixButton), findsNothing);
      expect(find.byType(MiuixCard), findsNothing);
      expect(find.byType(MiuixLinearProgressIndicator), findsNothing);
    });
  });
}
