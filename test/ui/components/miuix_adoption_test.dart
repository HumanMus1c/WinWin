import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:winwin/pages/setting/widgets/normal_item.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/inherited_ui_style.dart';
import 'package:winwin/theme/miuix_theme_bridge.dart';
import 'package:winwin/theme/ui_style.dart';
import 'package:winwin/ui/components/app_components.dart';

Widget wrapMiuix(Widget child, {bool dark = false}) => MaterialApp(
      home: MiuixThemeScope(
        isDark: dark,
        child: UiStyleScope(
          style: UiStyle.miuix,
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    );

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

  group('Miuix 组件替换（阶段2）', () {
    testWidgets('AppTextField：渲染 MiuixTextField 且格式化器在控制器层生效', (tester) async {
      final digitsCtrl = TextEditingController();
      final denyCtrl = TextEditingController();
      addTearDown(digitsCtrl.dispose);
      addTearDown(denyCtrl.dispose);

      await tester.pumpWidget(
        wrapMiuix(
          Column(
            children: [
              AppTextField(
                controller: digitsCtrl,
                label: '手机号',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              AppTextField(
                controller: denyCtrl,
                label: '账号',
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'\s')),
                ],
              ),
            ],
          ),
        ),
      );

      expect(find.byType(MiuixTextField), findsNWidgets(2));
      await tester.enterText(find.byType(MiuixTextField).first, '1a2 3');
      await tester.pump();
      expect(digitsCtrl.text, '123');

      await tester.enterText(find.byType(MiuixTextField).last, 'a b c');
      await tester.pump();
      expect(denyCtrl.text, 'abc');
    });

    testWidgets('AppSegmentedControl：渲染 MiuixTabRow 且切换回调正确', (tester) async {
      var selected = 0;
      await tester.pumpWidget(
        wrapMiuix(
          AppSegmentedControl<int>(
            value: 0,
            segments: const [(0, '密码'), (1, '短信'), (2, '扫码')],
            onChanged: (v) => selected = v,
          ),
        ),
      );

      expect(find.byType(MiuixTabRow), findsOneWidget);
      await tester.tap(find.text('扫码'));
      await tester.pump();
      expect(selected, 2);
    });

    testWidgets('AppGroup/AppListItem/NormalItem：渲染 MiuixCard 与行组件', (tester) async {
      await tester.pumpWidget(
        wrapMiuix(
          AppGroup(
            children: [
              const AppListItem(
                icon: Icons.code,
                title: '项目说明',
                subtitle: 'GPL-3.0',
              ),
              NormalItem(leading: const Icon(Icons.settings), title: '设置'),
            ],
          ),
        ),
      );

      expect(find.byType(MiuixCard), findsOneWidget);
      expect(find.byType(MiuixBasicComponent), findsNWidgets(2));
      expect(find.text('项目说明'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
    });

    testWidgets('NormalItem：miuix 行点击回调可用', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrapMiuix(
          NormalItem(
            title: '账号切换',
            onTap: (ctx, refresh) => tapped = true,
          ),
        ),
      );
      await tester.tap(find.text('账号切换'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });
  });

  group('Miuix 图标升级（阶段3c）', () {
    test('映射表初始化安全（byName 全部非空）且未映射回退 null', () {
      // 触发整表初始化：任一 byName 拼写错误都会在此抛错。
      expect(miuixVectorForGlyph(CupertinoIcons.settings), isNotNull);
      expect(miuixVectorForGlyph(CupertinoIcons.house_fill), isNotNull);
      expect(miuixVectorForGlyph(CupertinoIcons.star_fill), isNotNull);
      expect(miuixVectorForGlyph(CupertinoIcons.ellipsis), isNotNull);
      expect(miuixVectorForGlyph(CupertinoIcons.person), isNull);
    });

    testWidgets('AppIcon：miuix 映射字形渲染 MiuixIcon；未映射与 M3 回退 Icon',
        (tester) async {
      await tester.pumpWidget(
        wrapMiuix(
          Column(
            children: const [
              AppIcon(CupertinoIcons.settings, size: 20),
              AppIcon(CupertinoIcons.person, size: 20),
            ],
          ),
        ),
      );
      expect(find.byType(MiuixIcon), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.person), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          home: UiStyleScope(
            style: UiStyle.material3,
            child: Scaffold(
              body: const AppIcon(CupertinoIcons.settings, size: 20),
            ),
          ),
        ),
      );
      expect(find.byType(MiuixIcon), findsNothing);
      expect(find.byIcon(CupertinoIcons.settings), findsOneWidget);
    });
  });
}
