import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/models/bangumi/bangumi_detail.dart';

void main() {
  group('BangumiDetail Episode & Trailer Normalization Tests', () {
    test('Interleaves regular episodes and trailers into 1-episode-1-trailer format', () {
      final detail = BangumiDetail(
        seasonId: 28747,
        mediaId: 28223043,
        title: '凡人修仙传',
        episodes: [
          const BangumiEpisode(id: 1, title: '1', longTitle: '风起天南1'),
          const BangumiEpisode(id: 2, title: '2', longTitle: '风起天南2'),
          // 模拟 B 站接口集中返回的预告块
          const BangumiEpisode(
            id: 101,
            title: '77',
            longTitle: '星海飞驰1',
            badge: '预告',
          ),
          const BangumiEpisode(
            id: 102,
            title: '78',
            longTitle: '星海飞驰2',
            badge: '预告',
          ),
          const BangumiEpisode(
            id: 103,
            title: '191',
            longTitle: '慕兰之战15',
            badge: '预告',
          ),
          // 模拟集中返回的正片块
          const BangumiEpisode(
            id: 77,
            title: '77',
            longTitle: '星海飞驰1',
            badge: '会员',
          ),
          const BangumiEpisode(
            id: 78,
            title: '78',
            longTitle: '星海飞驰2',
            badge: '会员',
          ),
        ],
        sections: [
          const BangumiSection(
            id: 38936,
            title: '预告',
            type: 1,
            episodes: [
              BangumiEpisode(
                id: 201,
                title: '第2集预告',
                longTitle: '风起天南2预告',
              ),
              // 重复 id 的预告应被自动去重
              BangumiEpisode(
                id: 101,
                title: '星海飞驰第1集预告',
              ),
            ],
          ),
          const BangumiSection(
            id: 214158,
            title: '特别花絮',
            type: 2,
            episodes: [
              BangumiEpisode(id: 301, title: '花絮1'),
              BangumiEpisode(id: 302, title: '花絮2'),
            ],
          ),
          const BangumiSection(
            id: 78974,
            title: 'UP论道',
            type: 2,
            episodes: [
              BangumiEpisode(id: 401, title: '论道1'),
            ],
          ),
        ],
      );

      final normalized = detail.normalizeEpisodesAndTrailers();

      // 1. 验证独立的预告板块被移除，保留其他衍生板块
      expect(normalized.sections.any((s) => s.title == '预告'), isFalse);
      expect(normalized.sections.map((s) => s.title), containsAll(['特别花絮', 'UP论道']));

      // 2. 验证预告与正片按序号交错紧随（先是这集的预告，后面紧跟这集的正集）
      // 期望顺序：
      // - 第1集正片 (id: 1, 无预告)
      // - 第2集预告 (id: 201) -> 紧跟 第2集正片 (id: 2)
      // - 第77集预告 (id: 101) -> 紧跟 第77集正片 (id: 77)
      // - 第78集预告 (id: 102) -> 紧跟 第78集正片 (id: 78)
      // - 第191集预告 (id: 103, 未来未播出预告追加在末尾，最新的视频就是下集的预告)
      final epIds = normalized.episodes.map((e) => e.id).toList();
      expect(epIds, equals([1, 201, 2, 101, 77, 102, 78, 103]));

      // 3. 验证预告分集的 badge 均被统一设置为 '预告'
      final ep201 = normalized.episodes.firstWhere((e) => e.id == 201);
      expect(ep201.badge, equals('预告'));
      expect(ep201.isTrailer, isTrue);

      final ep101 = normalized.episodes.firstWhere((e) => e.id == 101);
      expect(ep101.badge, equals('预告'));
      expect(ep101.isTrailer, isTrue);

      final ep77 = normalized.episodes.firstWhere((e) => e.id == 77);
      expect(ep77.badge, equals('会员'));
      expect(ep77.isTrailer, isFalse);
    });

    test('fromJson automatically applies normalizeEpisodesAndTrailers', () {
      final json = {
        'season_id': 1234,
        'media_id': 5678,
        'title': '测试番剧',
        'episodes': [
          {'id': 1, 'title': '1', 'long_title': '第一集', 'badge': ''},
          {'id': 2, 'title': '2', 'long_title': '第二集', 'badge': ''},
        ],
        'section': [
          {
            'id': 999,
            'title': '预告',
            'type': 1,
            'episodes': [
              {'id': 101, 'title': '第1集预告', 'long_title': ''},
            ],
          },
          {
            'id': 888,
            'title': '精彩花絮',
            'type': 2,
            'episodes': [
              {'id': 201, 'title': '花絮1', 'long_title': ''},
            ],
          },
        ],
      };

      final detail = BangumiDetail.fromJson(json);

      expect(detail.sections.length, equals(1));
      expect(detail.sections.first.title, equals('精彩花絮'));
      expect(detail.episodes.length, equals(3));
      expect(detail.episodes[0].id, equals(101));
      expect(detail.episodes[0].badge, equals('预告'));
      expect(detail.episodes[1].id, equals(1));
      expect(detail.episodes[2].id, equals(2));
    });
  });
}
