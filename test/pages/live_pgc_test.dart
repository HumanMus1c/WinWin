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

    test('parses followed live stream with room_cover correctly', () {
      final json = <String, dynamic>{
        'roomid': 88888,
        'uid': 123456,
        'title': '正在直播中',
        'uname': '关注主播',
        'room_cover': 'http://i0.hdslb.com/bfs/live/follow_cover.jpg',
        'watched_show': {
          'num': 15000,
          'text_small': '1.5万',
        },
        'area_name': '单机游戏',
        'live_status': 1,
      };

      final item = LiveItemModel.fromJson(json);
      expect(item.roomId, 88888);
      expect(item.uid, 123456);
      expect(item.title, '正在直播中');
      expect(item.cover, 'https://i0.hdslb.com/bfs/live/follow_cover.jpg');
      expect(item.online, 15000);
      expect(item.areaName, '单机游戏');
      expect(item.isLiving, isTrue);
    });
  });

  group('LiveAreaItem & LiveFollowData Tests', () {
    test('defaultAreas provides core live parent areas', () {
      expect(LiveAreaItem.defaultAreas.isNotEmpty, isTrue);
      final names = LiveAreaItem.defaultAreas.map((e) => e.name).toList();
      expect(names.contains('网游'), isTrue);
      expect(names.contains('手游'), isTrue);
      expect(names.contains('单机游戏'), isTrue);
      expect(names.contains('娱乐'), isTrue);
      expect(names.contains('虚拟主播'), isTrue);
    });

    test('LiveAreaItem parses api payload with children correctly', () {
      final json = <String, dynamic>{
        'id': 2,
        'name': '网游',
        'list': [
          {'id': 86, 'name': '英雄联盟'},
          {'id': 329, 'name': '无畏契约'},
        ],
      };
      final item = LiveAreaItem.fromJson(json);
      expect(item.id, 2);
      expect(item.name, '网游');
      expect(item.children.length, 2);
      expect(item.children[0].name, '英雄联盟');
      expect(item.children[1].name, '无畏契约');
    });

    test('LiveFollowData filters living items only', () {
      final json = <String, dynamic>{
        'live_count': 1,
        'count': 2,
        'list': [
          {
            'roomid': 1001,
            'title': '直播中主播',
            'live_status': 1,
            'uname': '主播A',
          },
          {
            'roomid': 1002,
            'title': '未开播主播',
            'live_status': 0,
            'uname': '主播B',
          },
        ],
      };
      final followData = LiveFollowData.fromJson(json);
      expect(followData.liveCount, 1);
      expect(followData.count, 2);
      expect(followData.list.length, 1);
      expect(followData.list.first.roomId, 1001);
      expect(followData.list.first.uname, '主播A');
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

