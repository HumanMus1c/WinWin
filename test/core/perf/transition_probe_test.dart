import 'package:flutter/scheduler.dart' show FrameTiming;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/core/perf/transition_probe.dart';
import 'package:winwin/core/shell/app_routes.dart';

/// 页面转场探针回归测试。
///
/// 防回归点：
/// 1. 默认关闭时**零开销**（不记录、不产出报告）；
/// 2. 聚合口径正确：用时/配置时长/帧数/平均与最差 build·raster/超预算帧数/方向；
/// 3. 转场核自动开窗与收窗（push/pop 各产出一条结论）。
void main() {
  tearDown(() {
    TransitionProbe.enabled = false;
    TransitionProbe.verbose = false;
    TransitionProbe.instance.reports.clear();
    expect(TransitionProbe.instance.isRecording, isFalse);
  });

  test('默认关闭：begin/recordFrame/end 全部空操作（零开销）', () {
    final probe = TransitionProbe.instance;
    probe.begin('route', reverse: false, configuredMs: 300);
    expect(probe.isRecording, isFalse);
    probe.recordFrame(buildMs: 100, rasterMs: 100);
    probe.end();
    expect(probe.reports, isEmpty);
  });

  test('聚合口径：用时/帧数/平均与最差耗时/超预算帧数/方向', () {
    final probe = TransitionProbe.instance;
    TransitionProbe.enabled = true;

    probe.begin('TestRoute', reverse: false, configuredMs: 300);
    expect(probe.isRecording, isTrue);
    // 预算 16.7ms：build 超 1 帧（20），raster 超 2 帧（18/30）。
    probe.recordFrame(buildMs: 8, rasterMs: 6);
    probe.recordFrame(buildMs: 20, rasterMs: 18);
    probe.recordFrame(buildMs: 12, rasterMs: 30);
    probe.end();
    expect(probe.isRecording, isFalse);

    expect(probe.reports, hasLength(1));
    final report = probe.reports.single;
    expect(report, contains('route=TestRoute'));
    expect(report, contains('dir=push'));
    expect(report, contains('cfg=300ms'));
    expect(report, contains('frames=3'));
    expect(report, contains('build(avg=13.33 max=20.00 jank=1)'));
    expect(report, contains('raster(avg=18.00 max=30.00 jank=2)'));
  });

  test('方向标记：pop 反向窗口', () {
    final probe = TransitionProbe.instance;
    TransitionProbe.enabled = true;

    probe.begin('TestRoute', reverse: true, configuredMs: 200);
    probe.recordFrame(buildMs: 4, rasterMs: 5);
    probe.end();

    final report = probe.reports.single;
    expect(report, contains('dir=pop'));
    expect(report, contains('cfg=200ms'));
    expect(report, contains('build(avg=4.00 max=4.00 jank=0)'));
    expect(report, contains('raster(avg=5.00 max=5.00 jank=0)'));
  });

  test('帧号单调过滤：批处理回灌的旧帧不计入 frames/fps', () {
    final probe = TransitionProbe.instance;
    TransitionProbe.enabled = true;

    // 批处理特性：首批可能包含开窗前的旧帧（帧号小于已见最大值）。
    FrameTiming frame(int number, {int buildUs = 4000, int rasterUs = 5000}) =>
        FrameTiming(
          vsyncStart: 0,
          buildStart: 0,
          buildFinish: buildUs,
          rasterStart: buildUs,
          rasterFinish: buildUs + rasterUs,
          rasterFinishWallTime: buildUs + rasterUs,
          frameNumber: number,
        );

    // 未记录时投递 100~102：游标推进，但不计入任何窗口。
    probe.feedFrameTimings(<FrameTiming>[frame(100), frame(101), frame(102)]);

    probe.begin('FilterRoute', reverse: false, configuredMs: 300);
    // 首批回灌 98~102（旧帧） + 新帧 103（应只计入 103）。
    probe.feedFrameTimings(<FrameTiming>[
      frame(98),
      frame(99),
      frame(100),
      frame(101),
      frame(102),
      frame(103, buildUs: 20000, rasterUs: 30000),
    ]);
    probe.end();

    final report = probe.reports.single;
    expect(report, contains('frames=1'), reason: '仅新帧入选');
    expect(report, contains('build(avg=20.00 max=20.00 jank=1)'));
    expect(report, contains('raster(avg=30.00 max=30.00 jank=1)'));
    expect(report, contains('stale=5'), reason: '回灌旧帧计数可查');
  });

  testWidgets('转场核驱动：push 与 pop 各产出一条结论（自动开窗/收窗）',
      (tester) async {
    TransitionProbe.enabled = true;
    final probe = TransitionProbe.instance;
    final navKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Navigator(
          key: navKey,
          onGenerateRoute: (RouteSettings settings) => AppRoute<void>(
            builder: (_) => const Center(child: Text('首页')),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(probe.reports, isEmpty, reason: '首屏路由不产生转场记录');

    navKey.currentState!.push(
      AppRoute<void>(builder: (_) => const Center(child: Text('二级页'))),
    );
    await tester.pump();
    expect(probe.isRecording, isTrue, reason: 'push 开始应开窗');
    await tester.pump(const Duration(milliseconds: 400));
    expect(probe.isRecording, isFalse, reason: 'push 结束应收窗');
    expect(probe.reports, hasLength(1));
    expect(probe.reports.last, contains('dir=push'));

    navKey.currentState!.pop();
    await tester.pump();
    expect(probe.isRecording, isTrue, reason: 'pop 开始应开窗');
    await tester.pump(const Duration(milliseconds: 400));
    expect(probe.reports, hasLength(2));
    expect(probe.reports.last, contains('dir=pop'));
  });
}
