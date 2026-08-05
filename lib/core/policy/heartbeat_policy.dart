// Ported from BiliPai (Kotlin) -> WinWin (Dart)
// Original: com/android/purebilibili/data/repository/PlaybackHeartbeatPolicy.kt
//
// Playback heartbeat policy: builds the field map sent to bilibili's
// heartbeat ("progress") endpoint during video playback.

/// Aggregates playback heartbeat policy helpers as static methods.
class HeartbeatPolicy {
  HeartbeatPolicy._();

  /// Resolves the `play_type` field for a heartbeat ping.
  ///
  /// Returns 1 when both [playedTimeSec] and [realPlayedTimeSec] are
  /// zero (or negative) — i.e. this is the first heartbeat of the
  /// session. Otherwise returns 0 (a continuing-progress heartbeat).
  static int resolvePlaybackHeartbeatPlayType(
    int playedTimeSec,
    int realPlayedTimeSec,
  ) {
    return (playedTimeSec <= 0 && realPlayedTimeSec <= 0) ? 1 : 0;
  }

  /// Builds the field map for a heartbeat request.
  ///
  /// Only non-empty / positive fields are included; bilibili's backend
  /// treats absent fields the same as zero/empty so we omit them to keep
  /// the payload small.
  ///
  /// Fixed fields: `type`=3, `dt`=2, `outer`=0, `spmid`='333.788.0.0'.
  /// Optional fields (`epid`, `sid`, `mid`, `sub_type`, `csrf`) are
  /// included only when they carry a meaningful value.
  static Map<String, dynamic> buildPlaybackHeartbeatFields({
    required String bvid,
    required int aid,
    required int cid,
    int epid = 0,
    int sid = 0,
    int? mid,
    required int playedTimeSec,
    required int realPlayedTimeSec,
    required int startTsSec,
    required String csrf,
    int videoType = 3,
    int? subType,
  }) {
    final safePlayedTimeSec = playedTimeSec < 0 ? 0 : playedTimeSec;
    final safeRealPlayedTimeSec =
        realPlayedTimeSec < 0 ? 0 : realPlayedTimeSec;
    final safeStartTsSec = startTsSec < 0 ? 0 : startTsSec;

    final fields = <String, dynamic>{};

    if (aid > 0) fields['aid'] = aid.toString();
    if (bvid.isNotEmpty) fields['bvid'] = bvid;
    if (cid > 0) fields['cid'] = cid.toString();
    if (epid > 0) fields['epid'] = epid.toString();
    if (sid > 0) fields['sid'] = sid.toString();
    if (mid != null && mid > 0) fields['mid'] = mid.toString();

    fields['played_time'] = safePlayedTimeSec.toString();
    fields['real_played_time'] = safeRealPlayedTimeSec.toString();
    fields['realtime'] = safeRealPlayedTimeSec.toString();
    fields['start_ts'] = safeStartTsSec.toString();
    fields['type'] = videoType.toString();

    if (subType != null && subType > 0) {
      fields['sub_type'] = subType.toString();
    }

    fields['dt'] = '2';
    fields['outer'] = '0';
    fields['play_type'] = resolvePlaybackHeartbeatPlayType(
      safePlayedTimeSec,
      safeRealPlayedTimeSec,
    ).toString();
    fields['spmid'] = '333.788.0.0';
    fields['from_spmid'] = '';
    fields['refer_url'] = '';

    if (csrf.isNotEmpty) fields['csrf'] = csrf;

    return fields;
  }
}
