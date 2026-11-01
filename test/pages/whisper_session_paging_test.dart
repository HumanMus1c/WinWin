import 'package:flutter_test/flutter_test.dart';

import 'package:winwin/pages/whisper/session/session_pagination_policy.dart';

/// 会话列表分页策略不变量（2026-11-01 消息中心滚到底不出新会话回归）。
///
/// 背景：`session_type=4`（全部/特别关注）服务端忽略 `end_ts` 与 `pn`，
/// 任何游标都从最新开始返回同一段，且单批上限 100。该分类必须一次取满
/// 并判定「没有更多」；否则整页重复会触发无效重试，滚到底不再出现新内容。
Map<String, dynamic> _session(int talkerId, int sessionTs, {int topTs = 0}) =>
    {
      'talker_id': talkerId,
      'session_type': 1,
      'session_ts': sessionTs,
      'top_ts': topTs,
    };

void main() {
  group('消息中心会话列表分页策略（滚到底不出新会话回归）', () {
    test('「全部」分类判定为不支持游标分页（含特别关注）', () {
      expect(
        SessionPaginationPolicy.supportsCursorPaging(
          specialMode: false,
          sessionType: SessionPaginationPolicy.allSessionType,
        ),
        isFalse,
      );
      expect(
        SessionPaginationPolicy.supportsCursorPaging(
          specialMode: true,
          sessionType: SessionPaginationPolicy.allSessionType,
        ),
        isFalse,
      );
      // 其余分类（私信/关注/未关注等）游标分页正常。
      for (final type in [1, 2, 7, 8, 9]) {
        expect(
          SessionPaginationPolicy.supportsCursorPaging(
            specialMode: false,
            sessionType: type,
          ),
          isTrue,
        );
      }
    });

    test('全部模式：整页重复且服务端 has_more=1 时按「没有更多」处理', () {
      final existing = List.generate(
        22,
        (i) => _session(1000 + i, 1793535148121541 - i * 1000000),
      );
      final incoming = existing.take(11).toList();
      final merged = SessionPaginationPolicy.mergePage(
        existing: existing,
        incoming: incoming,
        // 全部模式调用方必须传 false（服务端游标无效，has_more 不可信）。
        responseHasMore: false,
        requestedEndTs: 0,
      );
      expect(merged.shouldRetry, isFalse);
      expect(merged.hasMore, isFalse);
      expect(merged.sessions.length, 22);
    });

    test('全部模式首批取满 100 条：完整合并且判定没有更多', () {
      final incoming = List.generate(
        SessionPaginationPolicy.allSessionFetchSize,
        (i) => _session(2000 + i, 1793535148121541 - i * 1000000),
      );
      final merged = SessionPaginationPolicy.mergePage(
        existing: const [],
        incoming: incoming,
        responseHasMore: false,
        requestedEndTs: 0,
      );
      expect(merged.sessions.length, SessionPaginationPolicy.allSessionFetchSize);
      expect(merged.newCount, SessionPaginationPolicy.allSessionFetchSize);
      expect(merged.hasMore, isFalse);
      // 游标仍记录（用于后续按分类恢复分页或调试），但不参与「还有更多」判定。
      expect(merged.nextEndTs, greaterThan(0));
    });

    test('支持游标的分类：整页重复 + has_more=1 时仍走更早游标重试', () {
      final existing = List.generate(
        11,
        (i) => _session(3000 + i, 1793458835297974 - i * 1000000),
      );
      final merged = SessionPaginationPolicy.mergePage(
        existing: existing,
        incoming: existing.toList(),
        responseHasMore: true,
        requestedEndTs: 1793458835297973,
      );
      expect(merged.shouldRetry, isTrue);
      expect(merged.hasMore, isTrue);
    });
  });
}
