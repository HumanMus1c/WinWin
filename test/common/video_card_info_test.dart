import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/common/widgets/video_card/video_card_adapter.dart';
import 'package:winwin/common/widgets/video_card/video_card_info.dart';
import 'package:winwin/models/video/rec_video_item.dart';

void main() {
  group('VideoCardInfoText', () {
    final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    test('观看时间带「观看于」前缀并保留时分', () {
      final text = VideoCardInfoText.playedAt(now);
      expect(text, startsWith('观看于 '));
      expect(text.length, greaterThan('观看于 '.length));
    });

    test('空时间不展示', () {
      expect(VideoCardInfoText.playedAt(null), '');
      expect(VideoCardInfoText.playedAt(0), '');
      expect(VideoCardInfoText.publishedAt(null), '');
      expect(VideoCardInfoText.publishedAt(0), '');
    });

    test('发布时间带「发布于」前缀', () {
      final text = VideoCardInfoText.publishedAt(now);
      expect(text, startsWith('发布于 '));
      expect(text.length, greaterThan('发布于 '.length));
    });

    test('进度文案统一为「已看 x / y」', () {
      expect(VideoCardInfoText.progress(null, 1740), '');
      expect(VideoCardInfoText.progress(0, 1740), '');
      expect(VideoCardInfoText.progress(-1, 1740), '已看完');
      expect(VideoCardInfoText.progress(754, 1740), '已看 12:34 / 29:00');
      expect(VideoCardInfoText.progress(754, 0), '已看 12:34');
    });

    test('Map 卡片数据解析点赞与发布时间', () {
      final data = VideoCardData.from({
        'bvid': 'BV1test',
        'aid': 123,
        'title': '测试',
        'duration': 100,
        'owner': {'name': 'UP', 'mid': 123},
        'stat': {'view': 26000, 'danmaku': 129, 'like': 12000},
        'pubdate': 1700000000,
      });
      expect(data.likeCount, 12000);
      expect(data.publishedAt, 1700000000);
      expect(data.playCount, 26000);
      expect(data.ownerName, 'UP');
    });

    test('App 推荐流的「X万点赞」推荐理由转为点赞数', () {
      final item = RcmdVideoItemAppModel.fromJson({
        'goto': 'av',
        'bvid': 'BV1test',
        'title': '测试',
        'duration': 100,
        'rcmd_reason': '3万点赞',
        'args': {'up_id': 1, 'up_name': 'UP'},
        'player_args': {'aid': 123, 'cid': 456, 'duration': 100},
        'cover_left_text_1': '85.2万',
        'cover_left_text_2': '3427',
      });
      // App 流没有 stat.like，点赞数从推荐理由里解析。
      expect(item.stat.like, 30000);
      expect(item.rcmdReason, '3万点赞');
      expect(VideoCardData.from(item).likeCount, 30000);
    });
  });
}
