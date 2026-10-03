import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:winwin/common/widgets/level_badge.dart';
import 'package:winwin/common/widgets/medal_widget.dart';
import 'package:winwin/common/widgets/miuix_popup_menu.dart';
import 'package:winwin/common/widgets/refresh_indicator.dart';
import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/pages/setting/widgets/slider_dialog.dart';
import 'package:winwin/pages/setting/widgets/normal_item.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/inherited_ui_style.dart';
import 'package:winwin/theme/miuix_theme_bridge.dart';
import 'package:winwin/theme/ui_style.dart';
import 'package:winwin/theme/ui_style_notifier.dart';
import 'package:winwin/ui/components/app_components.dart';
import 'package:winwin/ui/components/frosted_bottom_bar.dart';

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

  group('Miuix 刷新（阶段3d）', () {
    testWidgets('AppRefreshIndicator：miuix 渲染 RefreshIndicator（原视觉回退）', (tester) async {
      await tester.pumpWidget(
        wrapMiuix(
          SizedBox(
            height: 400,
            child: AppRefreshIndicator(
              onRefresh: () async {},
              child: ListView(children: const [Text('内容')]),
            ),
          ),
        ),
      );
      expect(find.byType(RefreshIndicator), findsOneWidget);
      expect(find.byType(MiuixPullToRefresh), findsNothing);
    });

    testWidgets('AppRefreshIndicator：下拉可触发 onRefresh（原视觉下功能保持）', (tester) async {
      var called = 0;
      final completer = Completer<void>();
      await tester.pumpWidget(
        wrapMiuix(
          SizedBox(
            height: 400,
            child: AppRefreshIndicator(
              onRefresh: () {
                called++;
                return completer.future;
              },
              child: ListView(
                children: const [SizedBox(height: 800, child: Text('长内容'))],
              ),
            ),
          ),
        ),
      );

      await tester.drag(find.byType(ListView), const Offset(0, 300));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(called, greaterThanOrEqualTo(1));

      completer.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('MiuixSlider：宽松宽度语境（Column）下需显式撑满才可见', (tester) async {
      double? changed;
      await tester.pumpWidget(
        wrapMiuix(
          SizedBox(
            width: 400,
            height: 120,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 与面板 _SliderRow 相同的用法：宽松宽度下必须显式撑满，
                // 否则内部 CustomPaint 坍缩为 0 宽（滑块"缺失"根因）。
                SizedBox(
                  width: double.infinity,
                  child: MiuixSlider(
                    value: 0.2,
                    onValueChanged: (v) => changed = v,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final size = tester.getSize(find.byType(MiuixSlider));
      expect(size.width, greaterThan(0));
      expect(size.height, greaterThan(0));

      await tester.drag(find.byType(MiuixSlider), const Offset(160, 0));
      await tester.pumpAndSettle();
      expect(changed, isNotNull);
      expect(changed!, greaterThan(0.2));
    });

    testWidgets('AppSliderDialog：miuix 渲染 MiuixSlider 且确定返回当前值', (tester) async {
      double? result;
      // 宿主复刻 main.dart：UiStyleScope 包在 MaterialApp 外层，
      // 使 showDialog 路由（Navigator 层级）同样取到 miuix 风格。
      await tester.pumpWidget(
        UiStyleScope(
          style: UiStyle.miuix,
          child: MaterialApp(
            home: MiuixThemeScope(
              isDark: false,
              child: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () async {
                      result = await showDialog<double>(
                        context: context,
                        builder: (_) => const AppSliderDialog(
                          title: '字体大小',
                          value: 1.0,
                          min: 0.8,
                          max: 1.4,
                          divisions: 12,
                          suffix: 'x',
                          decimals: 2,
                        ),
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(MiuixSlider), findsOneWidget);
      expect(find.text('1.00x'), findsOneWidget);

      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(result, 1.0);
    });

    testWidgets('字体弹窗搜索框：固定高度 Column 下高度正常（MiuixCompat 包裹）', (tester) async {
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);
      await tester.pumpWidget(
        wrapMiuix(
          SizedBox(
            width: 460,
            height: 520,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: MiuixCompat(
                    child: MiuixTextField(
                      controller: ctrl,
                      label: '搜索字体…',
                      useLabelAsPlaceholder: true,
                      singleLine: true,
                      leadingIcon: const Icon(Icons.search, size: 20),
                      onChanged: (_) {},
                    ),
                  ),
                ),
                Expanded(child: ListView(children: const [Text('x')])),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // 回归：桥接缺失时 SDK TextField 内部渲染失败（release 大灰块 /
      // debug 断言），表现为搜索框高度异常溢出——这里锁定正常高度。
      final size = tester.getSize(find.byType(MiuixTextField));
      expect(size.width, greaterThan(300));
      expect(size.height, lessThan(100));
    });
  });

  group('阶段4：sweep 完全化', () {
    testWidgets('底栏：miuix 渲染 MiuixFloatingNavigationBar 且保留彩色图标', (tester) async {
      await tester.pumpWidget(
        wrapMiuix(
          SizedBox(
            height: 140,
            child: FrostedBottomBar(currentIndex: 0, onSelect: (_) {}),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(MiuixFloatingNavigationBar), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing);

      // 逐项彩色图标保留（选中首页 → 显式色标 iosBlue 不受 Miuix 着色影响）。
      final icon = tester.widget<Icon>(
        find
            .descendant(
              of: find.byType(MiuixFloatingNavigationBarItem).first,
              matching: find.byType(Icon),
            )
            .first,
      );
      expect(icon.color, iosBlue);
    });

    testWidgets('Toast：miuix 经 ToastHost 上浮显示 MiuixSurface 反色卡', (tester) async {
      await tester.pumpWidget(
        wrapMiuix(
          MiuixToastHost(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => showToast(context, '操作成功'),
                child: const Text('toast'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('toast'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 不再使用 SnackBar（横向分展过渡）；改为宿主内条目卡。
      expect(find.byType(SnackBar), findsNothing);
      expect(
        find.descendant(
          of: find.byType(MiuixToastHost),
          matching: find.byType(MiuixSurface),
        ),
        findsOneWidget,
      );
      expect(find.text('操作成功'), findsOneWidget);

      // 点击卡片关闭。
      await tester.tap(find.text('操作成功'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('操作成功'), findsNothing);
      miuixToastRequest.value = null;
    });

    testWidgets('Toast：无 context 路径（showAppSnackBar）经宿主走 miuix 分支', (tester) async {
      // showAppSnackBar 无 context：miuix 路径经全局通道直达宿主，
      // 不再依赖 ScaffoldMessenger（其 context 位于 builder 链之上）。
      UiStyleNotifier.instance.value = UiStyle.miuix;
      addTearDown(() {
        UiStyleNotifier.instance.value = UiStyle.material3;
        miuixToastRequest.value = null;
      });

      await tester.pumpWidget(
        wrapMiuix(MiuixToastHost(child: const SizedBox.shrink())),
      );

      showAppSnackBar('网络异常，请稍后重试');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SnackBar), findsNothing);
      expect(
        find.descendant(
          of: find.byType(MiuixToastHost),
          matching: find.byType(MiuixSurface),
        ),
        findsOneWidget,
      );
      expect(find.text('网络异常，请稍后重试'), findsOneWidget);

      // 等待自动收起（计时器归零 → 退出动画完成 → 卡片移除）。
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.byType(MiuixSurface), findsNothing);
    });

    testWidgets('ActionTile：miuix 按压原语为 MiuixPressable', (tester) async {
      await tester.pumpWidget(
        wrapMiuix(
          Row(children: [AppActionTile(count: '12', label: '动态', onTap: () {})]),
        ),
      );
      await tester.pump();
      expect(find.byType(MiuixPressable), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('动态'), findsOneWidget);
    });

    testWidgets('LevelExpBar：miuix 进度条为 MiuixLinearProgressIndicator', (tester) async {
      await tester.pumpWidget(
        wrapMiuix(
          const LevelExpBar(level: 5, currentExp: 100, nextExp: 200),
        ),
      );
      await tester.pump();
      expect(find.byType(MiuixLinearProgressIndicator), findsOneWidget);
    });

    testWidgets('MedalWidget：miuix onTap 用 MiuixPressable 包裹', (tester) async {
      await tester.pumpWidget(
        wrapMiuix(
          MedalWidget(
            medalName: '粉丝牌',
            level: 21,
            backgroundColor: Colors.pink,
            onTap: () {},
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(MiuixPressable), findsOneWidget);
      expect(find.text('粉丝牌'), findsOneWidget);
    });

    testWidgets('MiuixPopupMenu：点开显示条目、单组选择后收起并回调', (tester) async {
      var clicked = false;
      await tester.pumpWidget(
        wrapMiuix(
          Center(
            child: MiuixPopupMenu(
              entries: [
                MiuixDropdownEntry(
                  items: [
                    MiuixDropdownItem(
                      text: '选项甲',
                      onClick: () => clicked = true,
                    ),
                    MiuixDropdownItem(text: '选项乙'),
                  ],
                ),
              ],
              child: const Text('打开'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('选项甲'), findsOneWidget);
      expect(find.byType(MiuixSurface), findsOneWidget);

      await tester.tap(find.text('选项甲'));
      await tester.pump();
      // 点击先即时反馈、130ms 后收起（复测反馈：先变化再关闭）。
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(clicked, isTrue);
      expect(find.text('选项甲'), findsNothing);
    });
  });
}
