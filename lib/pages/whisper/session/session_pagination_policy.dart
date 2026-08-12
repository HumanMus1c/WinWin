/// 私信会话分页策略（移植自 BiliPai `InboxSessionPaginationPolicy`）。
///
/// 解决三类问题：
/// 1. 置顶会话排序——按 top_ts / session_ts 双键降序，置顶恒在列表顶部；
/// 2. 分页重复——按 talker_id+session_type 等键去重，合并页时过滤已存在会话；
/// 3. 边界重复页——end_ts 游标严格递减，整页重复时用更早的游标自动重试。
abstract final class SessionPaginationPolicy {
  /// 会话唯一键：talker_id 优先，异常会话用 last_msg 兜底。
  static String sessionKey(Map<String, dynamic> session) {
    final talkerId = (session['talker_id'] as num?)?.toInt() ?? 0;
    final sessionType = (session['session_type'] as num?)?.toInt() ?? 0;
    if (talkerId > 0) return '${talkerId}_$sessionType';

    final lastMsg = session['last_msg'] as Map?;
    final msgKey = (lastMsg?['msg_key'] as num?)?.toInt() ?? 0;
    if (msgKey > 0) return 'msg_$msgKey';
    final seqno = (lastMsg?['msg_seqno'] as num?)?.toInt() ?? 0;
    if (seqno > 0) return 'seq_$seqno';
    final sessionTs = (session['session_ts'] as num?)?.toInt() ?? 0;
    if (sessionTs > 0) return 'session_ts_$sessionTs';
    final ts = (lastMsg?['timestamp'] as num?)?.toInt() ?? 0;
    if (ts > 0) {
      final sender = (lastMsg?['sender_uid'] as num?)?.toInt() ?? 0;
      final msgType = (lastMsg?['msg_type'] as num?)?.toInt() ?? 0;
      return 'time_${ts}_${sender}_$msgType';
    }
    return 'invalid_${talkerId}_$sessionType';
  }

  /// 置顶优先排序：top_ts 降序（置顶会话置顶），同级按 session_ts 降序。
  static List<Map<String, dynamic>> sortSessions(
          List<Map<String, dynamic>> sessions) =>
      [...sessions]
        ..sort((a, b) {
          final topA = (a['top_ts'] as num?)?.toInt() ?? 0;
          final topB = (b['top_ts'] as num?)?.toInt() ?? 0;
          if (topA != topB) return topB.compareTo(topA);
          final tsA = _normalizeSessionTs((a['session_ts'] as num?)?.toInt() ?? 0);
          final tsB = _normalizeSessionTs((b['session_ts'] as num?)?.toInt() ?? 0);
          return tsB.compareTo(tsA);
        });

  /// 排序 + 去重。
  static List<Map<String, dynamic>> normalizeSessions(
      List<Map<String, dynamic>> sessions) {
    final seen = <String>{};
    return sortSessions(sessions)
        .where((s) => seen.add(sessionKey(s)))
        .toList();
  }

  /// 下一页游标：末条会话 session_ts 归一化为微秒后 -1（严格更早，避免边界重复）。
  /// 若新游标不早于本次请求游标，则在请求游标上继续递减，防止重复页卡住。
  static int resolveNextEndTs(
      List<Map<String, dynamic>> sessions, int requestedEndTs) {
    final lastTs = sessions.isEmpty
        ? 0
        : (sessions.last['session_ts'] as num?)?.toInt() ?? 0;
    final normalized = _normalizeSessionTs(lastTs);
    if (normalized <= 0) return 0;
    final strictOlder = normalized - 1;
    if (requestedEndTs > 0 && strictOlder >= requestedEndTs) {
      return (requestedEndTs - 1).clamp(0, requestedEndTs);
    }
    return strictOlder;
  }

  /// 合并分页结果。返回记录含：
  /// - sessions：合并后的完整列表（已排序去重）
  /// - newCount：本页新增会话数
  /// - nextEndTs / hasMore：下一页游标与是否还有更多
  /// - shouldRetry：整页重复时建议用新游标自动重试
  static ({
    List<Map<String, dynamic>> sessions,
    int newCount,
    int nextEndTs,
    bool hasMore,
    bool shouldRetry,
  }) mergePage({
    required List<Map<String, dynamic>> existing,
    required List<Map<String, dynamic>> incoming,
    required bool responseHasMore,
    required int requestedEndTs,
    bool canRetryDuplicatePage = true,
  }) {
    final normalizedExisting = normalizeSessions(existing);
    final existingKeys = normalizedExisting.map(sessionKey).toSet();
    final newSessions = normalizeSessions(incoming)
        .where((s) => !existingKeys.contains(sessionKey(s)))
        .toList();
    final nextEndTs = resolveNextEndTs(incoming, requestedEndTs);
    final canAdvanceCursor = nextEndTs > 0 && nextEndTs != requestedEndTs;
    final isDuplicatePage = newSessions.isEmpty && incoming.isNotEmpty;
    final shouldRetry = canRetryDuplicatePage &&
        responseHasMore &&
        isDuplicatePage &&
        canAdvanceCursor;
    final hasMore = responseHasMore &&
        nextEndTs > 0 &&
        (newSessions.isNotEmpty || shouldRetry);
    return (
      sessions: normalizeSessions([...normalizedExisting, ...newSessions]),
      newCount: newSessions.length,
      nextEndTs: nextEndTs,
      hasMore: hasMore,
      shouldRetry: shouldRetry,
    );
  }

  static int _normalizeSessionTs(int ts) {
    if (ts <= 0) return 0;
    if (ts >= 1000000000000000) return ts; // 已是微秒
    if (ts >= 1000000000000) return ts * 1000; // 毫秒 → 微秒
    return ts * 1000000; // 秒 → 微秒
  }
}
