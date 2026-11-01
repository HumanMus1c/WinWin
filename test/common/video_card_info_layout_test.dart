import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart'
    show MiuixCard, MiuixPressFeedbackType, MiuixPressable;
import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/common/widgets/video_card/video_card_adapter.dart';
import 'package:winwin/common/widgets/video_card/video_card_info.dart';
import 'package:winwin/common/widgets/video_card/video_card_v.dart';
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

  testWidgets('聊天竖卡 shrinkWrap 高度按内容收缩，不被视口拉高', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      appTestHost(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 320,
            child: VideoCardV(
              videoItem: const VideoCardData(
                bvid: 'BV1chat',
                title: '聊天视频标题两行测试',
                duration: 96,
                playCount: 1000,
                danmakuCount: 10,
              ),
              shrinkWrap: true,
              showMenu: false,
              enableContextMenu: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final size = tester.getSize(find.byType(VideoCardV));
    expect(size.width, 320);
    expect(size.height, lessThan(320));
  });

  testWidgets('首页竖卡在 90px 信息区内不溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    const longTitle = '幼儿吃银鳕鱼致血汞异常！银鳕鱼等海鱼都不能吃？?这是一段更长的标题继续测试第二行右侧是否裁切';
    await tester.pumpWidget(
      appTestHost(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 1000,
            height: 600,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(12),
                  sliver: SliverGrid.builder(
                    gridDelegate: Grid.videoCardVDelegate(
                      maxCrossAxisExtent: 240.0,
                      mainAxisExtent: 100.0,
                    ),
                    itemCount: 1,
                    itemBuilder: (context, index) => VideoCardV(
                      videoItem: VideoCardData(
                        bvid: 'BV1home',
                        title: longTitle,
                        duration: 96,
                        ownerName: '测试UP主',
                        mid: 123,
                        playCount: 26000,
                        danmakuCount: 129,
                        likeCount: 12000,
                        isFollowed: true,
                        publishedAt: now - 3 * 24 * 3600,
                      ),
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

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(VideoCardV)).height, greaterThan(200));

    final paragraph = tester.renderObject<RenderParagraph>(
      find.text(longTitle),
    );
    expect(paragraph.didExceedMaxLines, isTrue);
    expect(paragraph.size.width, lessThanOrEqualTo(226.0));
    expect(paragraph.size.height, greaterThan(30.0));
  });
}
