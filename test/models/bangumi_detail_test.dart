import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/models/bangumi/bangumi_detail.dart';

void main() {
  group('BangumiDetail Model Tests (Aligned with PiliPlus)', () {
    test('fromJson preserves original episode order and all sections intact', () {
      final json = {
        'season_id': 28747,
        'media_id': 28223043,
        'title': '凡人修仙传',
        'episodes': [
          {'id': 1, 'title': '1', 'long_title': '风起天南1', 'badge': ''},
          {'id': 2, 'title': '2', 'long_title': '风起天南2', 'badge': ''},
          {'id': 77, 'title': '77', 'long_title': '星海飞驰1', 'badge': '会员'},
          {'id': 78, 'title': '78', 'long_title': '星海飞驰2', 'badge': '会员'},
        ],
        'section': [
          {
            'id': 38936,
            'title': '预告',
            'type': 1,
            'episodes': [
              {'id': 201, 'title': '第2集预告', 'long_title': '风起天南2预告'},
              {'id': 101, 'title': '星海飞驰第1集预告', 'long_title': ''},
            ],
          },
          {
            'id': 214158,
            'title': '特别花絮',
            'type': 2,
            'episodes': [
              {'id': 301, 'title': '花絮1', 'long_title': ''},
              {'id': 302, 'title': '花絮2', 'long_title': ''},
            ],
          },
          {
            'id': 78974,
            'title': 'UP论道',
            'type': 2,
            'episodes': [
              {'id': 401, 'title': '论道1', 'long_title': ''},
            ],
          },
        ],
      };

      final detail = BangumiDetail.fromJson(json);

      // 1. 验证正集列表保持原始接口顺序，不被人工插播篡改
      final epIds = detail.episodes.map((e) => e.id).toList();
      expect(epIds, equals([1, 2, 77, 78]));

      // 2. 验证所有衍生板块（包括预告、花絮、UP论道等）全部完整保留
      expect(detail.sections.length, equals(3));
      expect(detail.sections.map((s) => s.title), containsAll(['预告', '特别花絮', 'UP论道']));

      final trailerSec = detail.sections.firstWhere((s) => s.title == '预告');
      expect(trailerSec.episodes.length, equals(2));
      expect(trailerSec.episodes.first.id, equals(201));
    });
  });
}
