import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/common/widgets/video_card/video_card_info.dart';

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
  });
}
