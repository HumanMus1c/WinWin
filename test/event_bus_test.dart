import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/core/event/event_bus.dart';

void main() {
  group('EventBus Tests', () {
    test('emit and on receives correct event and filters types', () async {
      final bus = EventBus();
      final followEvents = <FollowEvent>[];
      final watchLaterEvents = <WatchLaterEvent>[];

      final sub1 = bus.on<FollowEvent>().listen((e) => followEvents.add(e));
      final sub2 = bus.on<WatchLaterEvent>().listen((e) => watchLaterEvents.add(e));

      bus.emit(const FollowEvent(mid: 123456, isFollowing: true));
      bus.emit(const WatchLaterEvent(aid: 98765, bvid: 'BV1xx', inWatchLater: true));
      bus.emit(const FollowEvent(mid: 123456, isFollowing: false));

      // 等待微任务队列排空
      await Future<void>.delayed(Duration.zero);

      expect(followEvents.length, equals(2));
      expect(followEvents[0].mid, equals(123456));
      expect(followEvents[0].isFollowing, isTrue);
      expect(followEvents[1].isFollowing, isFalse);

      expect(watchLaterEvents.length, equals(1));
      expect(watchLaterEvents[0].aid, equals(98765));
      expect(watchLaterEvents[0].bvid, equals('BV1xx'));
      expect(watchLaterEvents[0].inWatchLater, isTrue);

      await sub1.cancel();
      await sub2.cancel();
    });

    test('multiple subscribers receive same event', () async {
      final bus = EventBus();
      int count1 = 0;
      int count2 = 0;

      final sub1 = bus.on<FollowEvent>().listen((_) => count1++);
      final sub2 = bus.on<FollowEvent>().listen((_) => count2++);

      bus.emit(const FollowEvent(mid: 111, isFollowing: true));
      await Future<void>.delayed(Duration.zero);

      expect(count1, equals(1));
      expect(count2, equals(1));

      await sub1.cancel();
      await sub2.cancel();
    });

    test('canceling subscription stops receiving events', () async {
      final bus = EventBus();
      int count = 0;

      final sub = bus.on<FollowEvent>().listen((_) => count++);

      bus.emit(const FollowEvent(mid: 222, isFollowing: true));
      await Future<void>.delayed(Duration.zero);
      expect(count, equals(1));

      await sub.cancel();

      bus.emit(const FollowEvent(mid: 222, isFollowing: false));
      await Future<void>.delayed(Duration.zero);
      expect(count, equals(1)); // 不再增加
    });
  });
}
