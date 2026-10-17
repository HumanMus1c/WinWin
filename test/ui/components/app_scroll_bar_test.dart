import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/common/widgets/app_scroll_bar.dart';

/// [AppScrollBar] 回归测试。
///
/// 背景（2026-10-17 运行日志分析）：`.winwin_logs.json` 中 release 构建反复上报
/// `Null check operator used on a null value` @ `ScrollPosition.maxScrollExtent`
/// （`scroll_position.dart:239` ⇒ `_maxScrollExtent!`），栈顶落在
/// `_AppScrollBarState._buildLane` 的 `AnimatedBuilder` 内
/// （`app_scroll_bar.dart` L309 / L339，随各反馈轮行号漂移）。
///
/// 根因：`ScrollController.hasClients` 为真**不等于**该位置已具备内容尺寸。
/// `_maxScrollExtent` / `_viewportDimension` 仅在滚动视图**完成布局**
/// （`applyContentDimensions`）后写值；而滚动视图一被构建即 `attach` 到控制器
/// （`hasClients = true`）。因此存在「已挂载、无内容尺寸」窗口，此时读取
/// `maxScrollExtent` 即空断言崩溃。
///
/// 修复口径：所有 `ScrollPosition` 读数先以 `hasContentDimensions` /
/// `hasPixels` 守卫，未就绪即视为「不可滚动」。
/// 测试用「裸挂 `ScrollPosition`」稳定复刻该窗口（不依赖布局时序竞态）。
class _FakeScrollContext implements ScrollContext {
  @override
  BuildContext? get notificationContext => null;
  @override
  BuildContext get storageContext => throw UnimplementedError();
  @override
  TickerProvider get vsync => const TestVSync();
  @override
  AxisDirection get axisDirection => AxisDirection.down;
  @override
  double get devicePixelRatio => 1.0;
  @override
  void setIgnorePointer(bool value) {}
  @override
  void setCanDrag(bool value) {}
  @override
  void setSemanticsActions(Set<SemanticsAction> actions) {}
  @override
  void saveOffset(double offset) {}
}

Widget _host(Widget child) => MediaQuery(
      data: const MediaQueryData(size: Size(800, 600)),
      child: Directionality(textDirection: TextDirection.ltr, child: child),
    );

Widget _list(ScrollController c) => ListView.builder(
      controller: c,
      itemCount: 60,
      itemBuilder: (_, i) => SizedBox(height: 48, child: Text('row $i')),
    );

void main() {
  testWidgets('位置已挂载但无内容尺寸时构建不抛异常（空断言回归）', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    controller.attach(
      ScrollPositionWithSingleContext(
        physics: const ClampingScrollPhysics(),
        context: _FakeScrollContext(),
        keepScrollOffset: false,
      ),
    );

    // 前置条件：控制器已挂载，但位置尚无内容尺寸（复刻崩溃窗口）。
    expect(controller.hasClients, isTrue);
    expect(controller.position.hasContentDimensions, isFalse);

    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 800,
          height: 600,
          child: AppScrollBar(controller: controller, child: const SizedBox.expand()),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('正常挂载（滚动视图已完成布局）渲染且不抛异常', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 800,
          height: 600,
          child: AppScrollBar(controller: controller, child: _list(controller)),
        ),
      ),
    );

    expect(controller.position.hasContentDimensions, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('控制器无 clients 时构建不抛异常', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 800,
          height: 600,
          child: AppScrollBar(controller: controller, child: const SizedBox.expand()),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}