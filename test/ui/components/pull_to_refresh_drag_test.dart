import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:winwin/common/widgets/app_scroll_bar.dart';
import 'package:winwin/common/widgets/refresh_indicator.dart';
import 'package:winwin/ui/components/app_tab_view.dart';

import '../../support/app_test_host.dart';

/// 下拉刷新回归（2026-11-02 实机反馈：首页 / 动态 / 消息中心无法下拉刷新）。
///
/// 两处根因都属**继承型 `ScrollConfiguration` 副作用**——把只针对某个滚动视图
/// （或其容器的滚动条）定制的 `ScrollBehavior` 用 `ScrollConfiguration` 包住了
/// 一大片子树，于是 `dragDevices`（默认不含 `PointerDeviceKind.mouse`）沿树继承，
/// 子树里的滚动视图失去鼠标拖拽能力 ⇒ 下拉手势根本到不了刷新指示器。
///
/// 本组用例一律用**鼠标**拖拽（触摸设备默认就在 `dragDevices` 里，测不出该缺陷）。
void main() {
  Widget feed({ScrollController? controller}) => ListView(
        controller: controller,
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 1200, child: Text('长内容')),
        ],
      );

  Future<void> dragDownWithMouse(WidgetTester tester, Finder target) async {
    await tester.drag(target, const Offset(0, 300), kind: PointerDeviceKind.mouse);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('AppScrollBar 包裹的滚动视图：鼠标下拉仍可触发刷新（首页/热门/关注/番剧结构）',
      (tester) async {
    var called = 0;
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(appTestHost(
      SizedBox(
        height: 400,
        child: AppScrollBar(
          controller: controller,
          child: AppRefreshIndicator(
            onRefresh: () async => called++,
            child: feed(controller: controller),
          ),
        ),
      ),
    ));

    await dragDownWithMouse(tester, find.byType(ListView));
    expect(called, greaterThanOrEqualTo(1));
  });

  testWidgets('AppTabView 子页内的滚动视图：鼠标下拉仍可触发刷新（动态页结构）',
      (tester) async {
    var called = 0;
    final tabs = AppTabController(length: 2);

    await tester.pumpWidget(appTestHost(
      MediaQuery(
        // 宽屏（≥ kAppTabBreakpoint）才走「关闭鼠标拖动翻页」分支——缺陷正在该分支。
        data: const MediaQueryData(size: Size(1200, 800)),
        child: SizedBox(
          height: 400,
          child: AppTabView(
            controller: tabs,
            tabs: const ['全部', '视频'],
            floating: true,
            children: [
              AppRefreshIndicator(
                edgeOffset: AppTabView.floatingTopReserve,
                onRefresh: () async => called++,
                child: feed(),
              ),
              AppRefreshIndicator(
                edgeOffset: AppTabView.floatingTopReserve,
                onRefresh: () async => called++,
                child: feed(),
              ),
            ],
          ),
        ),
      ),
    ));

    await dragDownWithMouse(tester, find.byType(ListView).first);
    expect(called, greaterThanOrEqualTo(1));
  });
}
