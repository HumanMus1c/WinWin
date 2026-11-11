import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/core/policy/cdn_failover_policy.dart';

void main() {
  final t0 = DateTime(2026, 11, 1, 12);
  late CdnFailoverPolicy policy;

  setUp(() {
    policy = CdnFailoverPolicy();
  });

  group('CdnFailoverPolicy', () {
    test('首次失败冷却 30 秒，到期后可再次选择', () {
      policy.recordFailure('a', now: t0);

      expect(
        policy.shouldSkip('a', now: t0.add(const Duration(seconds: 29))),
        isTrue,
      );
      expect(
        policy.shouldSkip('a', now: t0.add(const Duration(seconds: 30))),
        isFalse,
      );
    });

    test('连续失败按 30s → 2m → 10m 退避，成功清零', () {
      policy.recordFailure('a', now: t0);
      policy.recordFailure(
        'a',
        now: t0.add(const Duration(seconds: 31)),
      );
      expect(policy.failureCount('a'), 2);
      expect(
        policy.shouldSkip(
          'a',
          now: t0.add(const Duration(minutes: 2, seconds: 30)),
        ),
        isTrue,
      );
      expect(
        policy.shouldSkip(
          'a',
          now: t0.add(const Duration(minutes: 2, seconds: 32)),
        ),
        isFalse,
      );

      policy.recordFailure('a', now: t0.add(const Duration(minutes: 3)));
      expect(policy.failureCount('a'), 3);
      expect(
        policy.shouldSkip('a', now: t0.add(const Duration(minutes: 12))),
        isTrue,
      );
      expect(
        policy.shouldSkip('a', now: t0.add(const Duration(minutes: 13))),
        isFalse,
      );

      policy.recordFailure('a', now: t0.add(const Duration(minutes: 14)));
      expect(policy.failureCount('a'), 4);
      expect(
        policy.shouldSkip('a', now: t0.add(const Duration(minutes: 23))),
        isTrue,
      );
      expect(
        policy.shouldSkip('a', now: t0.add(const Duration(minutes: 24))),
        isFalse,
      );

      policy.recordSuccess('a');
      expect(policy.failureCount('a'), 0);
      expect(policy.shouldSkip('a', now: t0), isFalse);
    });

    test('nextIndex 跳过冷却中的候选', () {
      final candidates = ['a', 'b', 'c'];
      policy.recordFailure('b', now: t0);

      expect(policy.nextIndex(candidates, 0, now: t0), 2);
    });

    test('excludeCurrent 保证自愈时换源', () {
      final candidates = ['a', 'b', 'c'];

      expect(
        policy.nextIndex(candidates, 0, excludeCurrent: true, now: t0),
        1,
      );
    });

    test('全部候选都在冷却时退回顺序轮换', () {
      final candidates = ['a', 'b', 'c'];
      for (final candidate in candidates) {
        policy.recordFailure(candidate, now: t0);
      }

      expect(
        policy.nextIndex(candidates, 0, excludeCurrent: true, now: t0),
        1,
      );
    });

    test('从列表头选择时跳过冷却候选', () {
      final candidates = ['a', 'b', 'c'];
      policy.recordFailure('a', now: t0);

      expect(policy.nextIndex(candidates, -1, now: t0), 1);
    });

    test('空列表返回 null', () {
      expect(policy.nextIndex(const [], 0), isNull);
    });

    test('reset 清空全部失败记忆', () {
      policy.recordFailure('a', now: t0);
      policy.reset();

      expect(policy.failureCount('a'), 0);
      expect(policy.shouldSkip('a', now: t0), isFalse);
    });
  });
}
