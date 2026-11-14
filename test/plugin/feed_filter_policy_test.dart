import 'package:flutter_test/flutter_test.dart';

import 'package:winwin/models/video/rec_video_item.dart';
import 'package:winwin/plugin/builtin/feed_filter/feed_filter_policy.dart';

RcmdVideoItemModel _item({
  String title = '普通视频',
  int duration = 120,
  int? view = 10000,
  int? like = 500,
  int? mid = 1,
  String ownerName = 'UP',
  bool isFollowed = false,
  String? goto = 'av',
  String? tname,
}) {
  final item = RcmdVideoItemModel.fromJson({
    'title': title,
    'duration': duration,
    'bvid': 'BV1xx',
    'goto': goto,
    'owner': {'mid': mid, 'name': ownerName},
    'stat': {'view': view, 'like': like},
    'is_followed': isFollowed,
    'tname': ?tname,
  });
  return item;
}

void main() {
  group('FeedFilterPolicy 基础规则', () {
    test('时长低于阈值被隐藏', () {
      final config = const FeedFilterConfig(minDurationForRcmd: 60);
      expect(
        FeedFilterPolicy.shouldShow(
          config: config,
          item: _item(duration: 30),
          kind: FeedKind.recommend,
        ),
        isFalse,
      );
      expect(
        FeedFilterPolicy.shouldShow(
          config: config,
          item: _item(duration: 120),
          kind: FeedKind.recommend,
        ),
        isTrue,
      );
    });

    test('播放量与点赞率', () {
      const config = FeedFilterConfig(
        minPlayForRcmd: 1000,
        minLikeRatioForRecommend: 2,
      );
      expect(
        FeedFilterPolicy.shouldShow(
          config: config,
          item: _item(view: 500, like: 100),
          kind: FeedKind.recommend,
        ),
        isFalse,
      );
      // 2% 阈值：500 / 10000 = 5% 通过；100 / 10000 = 1% 被隐藏。
      expect(
        FeedFilterPolicy.shouldShow(
          config: config,
          item: _item(view: 10000, like: 500),
          kind: FeedKind.recommend,
        ),
        isTrue,
      );
      expect(
        FeedFilterPolicy.shouldShow(
          config: config,
          item: _item(view: 10000, like: 100),
          kind: FeedKind.recommend,
        ),
        isFalse,
      );
    });

    test('白名单优先于所有规则', () {
      const config = FeedFilterConfig(
        minDurationForRcmd: 600,
        recommendBlockedMids: {1: 'UP'},
        whitelistMids: {1: 'UP'},
      );
      expect(
        FeedFilterPolicy.shouldShow(
          config: config,
          item: _item(duration: 10, mid: 1),
          kind: FeedKind.recommend,
        ),
        isTrue,
      );
    });

    test('已关注豁免仅推荐流生效', () {
      const config = FeedFilterConfig(
        minDurationForRcmd: 60,
        exemptFilterForFollowed: true,
        applyToSearch: true,
      );
      final followed = _item(duration: 10, isFollowed: true);
      expect(
        FeedFilterPolicy.shouldShow(
          config: config,
          item: followed,
          kind: FeedKind.recommend,
        ),
        isTrue,
      );
      expect(
        FeedFilterPolicy.shouldShow(
          config: config,
          item: followed,
          kind: FeedKind.search,
        ),
        isFalse,
      );
    });

    test('标题/分区关键词与屏蔽用户', () {
      final config = FeedFilterConfig(
        banWordForRecommend: '广告\n恰饭',
        banWordForZone: '鬼畜',
        recommendBlockedMids: const {9: 'blocked'},
      );
      final titleRegex =
          FeedFilterPolicy.parseBanWordToRegex(config.banWordForRecommend);
      final zoneRegex =
          FeedFilterPolicy.parseBanWordToRegex(config.banWordForZone);

      expect(
        FeedFilterPolicy.shouldShow(
          config: config,
          item: _item(title: '这是广告'),
          kind: FeedKind.recommend,
          titleRegex: titleRegex,
        ),
        isFalse,
      );
      expect(
        FeedFilterPolicy.shouldShow(
          config: config,
          item: _item(tname: '鬼畜区'),
          kind: FeedKind.recommend,
          zoneRegex: zoneRegex,
        ),
        isFalse,
      );
      expect(
        FeedFilterPolicy.shouldShow(
          config: config,
          item: _item(mid: 9),
          kind: FeedKind.recommend,
        ),
        isFalse,
      );
    });

    test('来源开关：热门/排行/搜索默认不应用', () {
      const config = FeedFilterConfig(minDurationForRcmd: 60);
      expect(
        FeedFilterPolicy.shouldShow(
          config: config,
          item: _item(duration: 10),
          kind: FeedKind.popular,
        ),
        isTrue,
      );
      expect(
        FeedFilterPolicy.shouldShow(
          config: config,
          item: _item(duration: 10),
          kind: FeedKind.search,
        ),
        isTrue,
      );
    });

    test('番剧卡片跳过统计类过滤', () {
      const config = FeedFilterConfig(
        minDurationForRcmd: 600,
        minPlayForRcmd: 100000,
      );
      expect(
        FeedFilterPolicy.shouldShow(
          config: config,
          item: _item(duration: 10, view: 0, goto: 'bangumi'),
          kind: FeedKind.recommend,
        ),
        isTrue,
      );
    });

    test('关键词换行解析与 UID 解析', () {
      final regex = FeedFilterPolicy.parseBanWordToRegex('广告|恰饭\n  \n推广');
      expect(regex, isNotNull);
      expect(regex!.hasMatch('这是广告|恰饭视频'), isTrue);

      final mids = FeedFilterPolicy.parseUidMap('123\n某人 (456)');
      expect(mids.keys, containsAll([123, 456]));
      final text = FeedFilterPolicy.uidMapToEditorText(mids);
      expect(text.contains('123'), isTrue);
      expect(text.contains('(456)'), isTrue);
    });

    test('配置 JSON 往返', () {
      const config = FeedFilterConfig(
        minDurationForRcmd: 60,
        banWordForRecommend: '广告',
        recommendBlockedMids: {1: 'UP'},
        exemptFilterForFollowed: false,
      );
      final again = FeedFilterConfig.fromJson(config.toJson());
      expect(again.minDurationForRcmd, 60);
      expect(again.banWordForRecommend, '广告');
      expect(again.recommendBlockedMids[1], 'UP');
      expect(again.exemptFilterForFollowed, isFalse);
    });
  });
}
