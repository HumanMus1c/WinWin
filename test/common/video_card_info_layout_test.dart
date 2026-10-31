import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart'
    show MiuixCard, MiuixPressFeedbackType, MiuixPressable;
import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/common/widgets/video_card/video_card_info.dart';
import 'package:winwin/utils/grid.dart';
import '../support/app_test_host.dart';

Widget _card(String title) {
  return MiuixCard(
    child: MiuixPressable(
      feedbackType: MiuixPressFeedbackType.sink,
      sinkAmount: 0.98,
      onPressed: () {},
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 140,
                  height: 140 * 9 / 16,
                  color: const Color(0xFF333333),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: VideoCardInfoColumn(
                    title: title,
                    ownerName: 'UP',
                    timeText: '观看于 今天 21:30',
                    progressText: '已看 12:34 / 29:00',
                    trailing: const SizedBox(width: 24, height: 24),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Container(height: 4, color: const Color(0xFF888888)),
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('历史卡片单行 / 两行标题的信息行纵向对齐', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      appTestHost(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 1000,
            height: 400,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(12),
                  sliver: SliverGrid.builder(
                    gridDelegate: Grid.videoCardHDelegate(
                      maxCrossAxisExtent: 440.0,
                      mainAxisExtent: 110.0,
                    ),
                    itemCount: 2,
                    itemBuilder: (context, index) => _card(
                      index == 0
                          ? '单行标题'
                          : '两行标题这是一段足够长的标题用来占满第二行测试布局',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final up0 = tester.getTopLeft(find.text('UP').at(0));
    final up1 = tester.getTopLeft(find.text('UP').at(1));
    expect((up0.dy - up1.dy).abs(), lessThan(1.0));
  });
}
