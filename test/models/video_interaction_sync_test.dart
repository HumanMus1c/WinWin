import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/models/video/reply_item.dart';
import 'package:winwin/models/video/video_relation.dart';

void main() {
  group('VideoRelationModel tests', () {
    test('正确解析标准布尔与数值型互动关系数据', () {
      final json = {
        'like': true,
        'dislike': false,
        'coin': 2,
        'favorite': true,
        'season_fav': false,
        'attention': true,
      };
      final model = VideoRelationModel.fromJson(json);
      expect(model.like, isTrue);
      expect(model.dislike, isFalse);
      expect(model.coin, equals(2));
      expect(model.favorite, isTrue);
      expect(model.seasonFav, isFalse);
      expect(model.attention, isTrue);
    });

    test('兼容容错解析整型标记（1/0）互动数据', () {
      final json = {
        'like': 1,
        'dislike': 0,
        'coin': '1',
        'favorite': 1,
        'season_fav': 0,
        'attention': 0,
      };
      final model = VideoRelationModel.fromJson(json);
      expect(model.like, isTrue);
      expect(model.dislike, isFalse);
      expect(model.coin, equals(1));
      expect(model.favorite, isTrue);
      expect(model.seasonFav, isFalse);
      expect(model.attention, isFalse);
    });

    test('空值或缺省字段解析为安全默认值', () {
      final model = VideoRelationModel.fromJson({});
      expect(model.like, isFalse);
      expect(model.dislike, isFalse);
      expect(model.coin, equals(0));
      expect(model.favorite, isFalse);
      expect(model.seasonFav, isFalse);
      expect(model.attention, isFalse);
    });

    test('copyWith 正确复制与改写状态', () {
      const initial = VideoRelationModel(like: false, coin: 0);
      final updated = initial.copyWith(like: true, coin: 2);
      expect(updated.like, isTrue);
      expect(updated.coin, equals(2));
      expect(updated.dislike, isFalse);
    });
  });

  group('ReplyItemModel 点赞/点踩姿态与 UP主标记测试', () {
    test('正确从顶层 json.action 解析已点赞姿态 (action=1)', () {
      final json = {
        'rpid': 123456,
        'like': 42,
        'action': 1,
      };
      final reply = ReplyItemModel.fromJson(json);
      expect(reply.action, equals(1));
      expect(reply.isLiked, isTrue);
      expect(reply.isDisliked, isFalse);
      expect(reply.like, equals(42));
    });

    test('正确从顶层 json.action 解析已点踩姿态 (action=2)', () {
      final json = {
        'rpid': 123457,
        'like': 10,
        'action': 2,
      };
      final reply = ReplyItemModel.fromJson(json);
      expect(reply.action, equals(2));
      expect(reply.isLiked, isFalse);
      expect(reply.isDisliked, isTrue);
    });

    test('顶层 action 为 0 时为无操作态', () {
      final json = {
        'rpid': 123458,
        'like': 5,
        'action': 0,
      };
      final reply = ReplyItemModel.fromJson(json);
      expect(reply.action, equals(0));
      expect(reply.isLiked, isFalse);
      expect(reply.isDisliked, isFalse);
    });

    test('兼容从 reply_control.action 容错回退', () {
      final json = {
        'rpid': 123459,
        'reply_control': {'action': 1},
      };
      final reply = ReplyItemModel.fromJson(json);
      expect(reply.action, equals(1));
      expect(reply.isLiked, isTrue);
    });

    test('正确解析 UP 主互动标记 (up_action)', () {
      final json = {
        'rpid': 123460,
        'up_action': {
          'like': true,
          'reply': false,
        },
      };
      final reply = ReplyItemModel.fromJson(json);
      expect(reply.upAction, isNotNull);
      expect(reply.upAction?.like, isTrue);
      expect(reply.upAction?.reply, isFalse);
    });

    test('copyWith 支持更新 action 与 upAction', () {
      final reply = ReplyItemModel(rpid: 1, action: 0, like: 10);
      final liked = reply.copyWith(
        action: 1,
        like: 11,
        upAction: const ReplyUpAction(like: true),
      );
      expect(liked.action, equals(1));
      expect(liked.isLiked, isTrue);
      expect(liked.like, equals(11));
      expect(liked.upAction?.like, isTrue);
    });
  });
}
