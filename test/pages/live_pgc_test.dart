import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/http/live.dart';
import 'package:winwin/pages/pgc/view.dart';

void main() {
  group('LiveItemModel Tests', () {
    test('parses getRoomList payload correctly with isLiving defaulting to true', () {
      final json = <String, dynamic>{
        'roomid': 7734200,
        'uid': 50329118,
        'title': '【直播】英雄联盟赛事',
        'uname': '赛事官方',
        'online': 64967224,
        'user_cover': 'http://i0.hdslb.com/bfs/live/test_cover.jpg',
        'cover': '',
        'face': 'http://i2.hdslb.com/bfs/face/test_face.jpg',
        'area_name': '游戏赛事',
      };

      final item = LiveItemModel.fromJson(json);

      expect(item.roomId, 7734200);
      expect(item.uid, 50329118);
      expect(item.title, '【直播】英雄联盟赛事');
      expect(item.uname, '赛事官方');
      expect(item.online, 64967224);
      expect(item.cover, 'https://i0.hdslb.com/bfs/live/test_cover.jpg');
      expect(item.face, 'https://i2.hdslb.com/bfs/face/test_face.jpg');
      expect(item.areaName, '游戏赛事');
      expect(item.isLiving, isTrue);
    });

    test('respects explicit live_status if present', () {
      final livingJson = <String, dynamic>{'roomid': 101, 'live_status': 1};
      final offlineJson = <String, dynamic>{'roomid': 102, 'live_status': 0};

      expect(LiveItemModel.fromJson(livingJson).isLiving, isTrue);
      expect(LiveItemModel.fromJson(offlineJson).isLiving, isFalse);
    });
  });

  group('PgcSubTab Tests', () {
    test('contains expected secondary classifiers', () {
      expect(PgcSubTab.values.length, 2);
      expect(PgcSubTab.myFollow.label, '我的追番');
      expect(PgcSubTab.hot.label, '热门追番');
    });
  });
}
