// Ported from BiliPai (Kotlin) -> WinWin (Dart)
// Original: com/android/purebilibili/data/repository/VideoLoadPolicy.kt
//
// Video loading policy: quality resolution, DASH fallback chains,
// cache decisions, playback auth, WBI params, and HDR auto-upgrade
// scheduling for bilibili video playback.
//
// Quality ladder (low -> high):
//   32  guest 480P
//   64  login 720P
//   80  1080P
//   112 1080P+ (high bitrate)
//   116 VIP 1080P+ / 4K-ready
//   120 4K
//   125 HDR
//   126 Dolby Vision
//   127 8K

/// Enum describing which playurl endpoint the response came from.
enum PlayUrlSource {
  app,
  dash,
  html5,
  legacy,
  guest,
}

/// Distinguishes an INITIAL (first-load) playurl request from an EXPLICIT
/// user-triggered quality switch.
enum PlayUrlRequestKind {
  initial,
  explicit,
}

/// Lightweight value object carrying the resolved lookup input for a
/// video info request. Either [bvid] (non-empty) or [aid] (> 0) is set.
class VideoInfoLookupInput {
  final String bvid;
  final int aid;

  const VideoInfoLookupInput({required this.bvid, required this.aid});
}

/// Minimal `Page` representation used by
/// [VideoLoadPolicy.resolveRequestedVideoCid].
///
/// The full `Page` model from the original Kotlin source is trimmed to
/// the only field the policy actually inspects: [cid].
class Page {
  final int cid;

  const Page({required this.cid});
}

/// Minimal `DashVideo` representation used by
/// [VideoLoadPolicy.hasExactPlayableRequestedTrack].
///
/// The original Kotlin source calls `video.getValidUrl()`; here it is
/// modeled as a String field that must be non-empty.
class DashVideo {
  final int id;
  final String validUrl;

  const DashVideo({required this.id, required this.validUrl});
}

/// Aggregates all video-load policy helpers as static methods.
class VideoLoadPolicy {
  VideoLoadPolicy._();

  /// Returns true when the request is an EXPLICIT selection of a premium
  /// tier (HDR 125, Dolby Vision 126, 8K 127).
  ///
  /// These strict tiers must be honored exactly by the backend
  /// response; otherwise the UI would report a successful switch while a
  /// lower tier was silently returned.
  static bool isStrictPremiumQualityRequest(
    PlayUrlRequestKind requestKind,
    int targetQn,
  ) {
    return requestKind == PlayUrlRequestKind.explicit &&
        targetQn >= 125 &&
        targetQn <= 127;
  }

  /// Resolves the lookup input ([VideoInfoLookupInput]) from a raw BV/AV
  /// identifier plus an optional aid.
  ///
  /// Rules (order matters):
  /// 1. A BV-prefixed string wins: lookup by bvid, aid=0.
  /// 2. Otherwise, a non-zero aid wins: lookup by aid, bvid="".
  /// 3. Otherwise, try to parse the string as an `av<digits>` id.
  /// 4. If nothing matches, return null.
  static VideoInfoLookupInput? resolveVideoInfoLookupInput(
    String rawBvid,
    int aid,
  ) {
    final normalizedBvid = rawBvid.trim();
    if (normalizedBvid.toUpperCase().startsWith('BV')) {
      return VideoInfoLookupInput(bvid: normalizedBvid, aid: 0);
    }

    if (aid > 0) {
      return VideoInfoLookupInput(bvid: '', aid: aid);
    }

    final normalizedAv = normalizedBvid.toLowerCase();
    if (normalizedAv.startsWith('av')) {
      final parsedAid = int.tryParse(normalizedAv.substring(2));
      if (parsedAid != null && parsedAid > 0) {
        return VideoInfoLookupInput(bvid: '', aid: parsedAid);
      }
    }

    return null;
  }

  /// Picks the actual cid for a playurl request given the requested cid,
  /// the cid advertised by the video info, and the list of pages.
  ///
  /// If the request cid is valid (non-zero) it is preferred — but only
  /// when it exists in the page list, or the page list is empty.
  /// Otherwise the info cid is used; otherwise the request cid;
  /// otherwise 0.
  static int resolveRequestedVideoCid(
    int requestCid,
    int infoCid,
    List<Page> pages,
  ) {
    final normalizedRequestCid = requestCid > 0 ? requestCid : null;
    final normalizedInfoCid = infoCid > 0 ? infoCid : null;

    if (normalizedRequestCid != null) {
      if (pages.isEmpty || pages.any((p) => p.cid == normalizedRequestCid)) {
        return normalizedRequestCid;
      }
    }

    return normalizedInfoCid ?? normalizedRequestCid ?? 0;
  }

  /// Decides the first playurl request quality for a new playback
  /// session.
  ///
  /// [preferFastStartOnMobile] requests a slightly lower first hop on
  /// cellular so the first frame arrives sooner; Wi-Fi keeps the
  /// premium first request.
  static int resolveInitialStartQuality({
    required int? targetQuality,
    required bool isAutoHighestQuality,
    required bool isLogin,
    required bool isVip,
    required bool auto1080pEnabled,
    bool preferFastStartOnMobile = false,
  }) {
    if (isAutoHighestQuality && isVip && preferFastStartOnMobile) return 112;
    if (isAutoHighestQuality && isVip) return 125;
    if (isAutoHighestQuality && isLogin && preferFastStartOnMobile) return 64;
    if (isAutoHighestQuality && isLogin) return 80;
    if (isAutoHighestQuality) return 64;
    if (targetQuality != null) return targetQuality;
    if (isVip) return 116;
    if (isLogin && auto1080pEnabled) return 80;
    if (isLogin) return 64;
    return 32;
  }

  /// Returns true when the session cookie alone authorizes playback.
  ///
  /// The access_token is not required for the web/WBI playurl path; the
  /// session cookie (SESSDATA) is the single source of truth here.
  static bool resolveVideoPlaybackAuthState(
    bool hasSessionCookie,
    bool hasAccessToken,
  ) {
    return hasSessionCookie;
  }

  /// Returns true when the cached playurl entry must be skipped.
  ///
  /// Language-specific streams must never reuse the default-language
  /// cache entry, so any non-null [audioLang] forces a fresh fetch.
  static bool shouldSkipPlayUrlCache(
    bool isAutoHighestQuality,
    bool isVip,
    String? audioLang,
  ) {
    return audioLang != null;
  }

  /// VIP auto-highest can reuse a cached playurl when it already contains
  /// a premium track (id >= [minPremiumQuality]). Thin/low-quality cache
  /// entries are ignored so we still re-negotiate high quality.
  static bool shouldAcceptCachedPlayUrlForAutoHighest(
    bool isAutoHighestQuality,
    bool isVip,
    List<int> cachedDashVideoIds, {
    int minPremiumQuality = 112,
  }) {
    if (!isAutoHighestQuality || !isVip) return true;
    return cachedDashVideoIds.any((q) => q >= minPremiumQuality);
  }

  /// Builds the DASH playurl attempt chain for [targetQn].
  ///
  /// The requested quality itself leads the list. Premium tiers such as
  /// 8K (127), Dolby Vision (126), and HDR (125) are not always bundled
  /// into a lower-qn response (e.g. qn=120), so omitting the target
  /// causes QUALITY_SWITCH_FAILURE / missing HDR tracks. The chain
  /// therefore walks down through every premium quality below the
  /// target and finally falls back to 1080P (80).
  ///
  /// For standard qualities (<= 80) only the target itself is requested.
  static List<int> buildDashAttemptQualities(int targetQn) {
    if (targetQn <= 80) return [targetQn];

    const premiumQualities = [127, 126, 125, 120, 116, 112];
    final lowerFallbacks = premiumQualities.where((q) => q < targetQn).toList();

    return <int>{
      targetQn,
      ...lowerFallbacks,
      80,
    }.toList();
  }

  /// Retry delays (ms) for a DASH attempt at [targetQn].
  ///
  /// Standard qualities (80/64 etc.) occasionally return empty streams;
  /// a short retry window avoids a false downgrade to guest 720P.
  /// Premium tiers do not retry.
  static List<int> resolveDashRetryDelays(int targetQn) {
    return targetQn <= 80 ? [0, 450] : [0];
  }

  /// Returns true when a DASH recovery retry should be attempted.
  ///
  /// Conditions:
  /// - [targetQn] is a standard tier (1..80).
  /// - the returned quality did not meet the target.
  /// - [targetQn] is among [acceptQualities].
  /// - [targetQn] is absent from [dashVideoIds].
  static bool shouldRetryDashTrackRecovery(
    int targetQn,
    int returnedQuality,
    List<int> acceptQualities,
    List<int> dashVideoIds,
  ) {
    if (targetQn <= 0 || targetQn > 80) return false;
    if (returnedQuality >= targetQn) return false;
    if (!acceptQualities.contains(targetQn)) return false;
    return !dashVideoIds.contains(targetQn);
  }

  /// Diagnostic summary string for the resolved start quality.
  static String buildStartQualityDecisionSummary({
    required String bvid,
    required int cid,
    required int? userSettingQuality,
    required int startQuality,
    required bool isAutoHighestQuality,
    required bool isLoggedIn,
    required bool isVip,
    required bool auto1080pEnabled,
    required String? audioLang,
  }) {
    return 'PLAY_DIAG start_quality bvid=$bvid cid=$cid '
        'userSetting=${userSettingQuality ?? 'null'} '
        'start=$startQuality autoHighest=$isAutoHighestQuality '
        'isLoggedIn=$isLoggedIn isVip=$isVip '
        'auto1080p=$auto1080pEnabled '
        'audioLang=${audioLang ?? 'default'}';
  }

  /// Diagnostic summary string for a playurl fetch result.
  static String buildPlayUrlFetchSummary({
    required String bvid,
    required int cid,
    required PlayUrlSource source,
    required int requestedQuality,
    required int returnedQuality,
    required List<int> acceptQualities,
    required List<int> dashVideoIds,
    required bool hasDurl,
    required bool isLoggedIn,
    required bool isVip,
    required String? audioLang,
  }) {
    return 'PLAY_DIAG fetch_result bvid=$bvid cid=$cid source=$source '
        'requested=$requestedQuality returned=$returnedQuality '
        'accept=$acceptQualities dash=$dashVideoIds '
        'hasDurl=$hasDurl isLoggedIn=$isLoggedIn isVip=$isVip '
        'audioLang=${audioLang ?? 'default'}';
  }

  /// Returns true when an access_token API call may proceed past its
  /// cooldown window.
  static bool shouldCallAccessTokenApi(
    int nowMs,
    int cooldownUntilMs,
    bool hasAccessToken,
  ) {
    return hasAccessToken && nowMs >= cooldownUntilMs;
  }

  /// Returns false unconditionally.
  ///
  /// PiliPlus parity: playback stays on the Web/WBI playurl path instead
  /// of prioritizing the APP access_token endpoint for 1080P and premium
  /// tiers.
  static bool shouldTryAppApiForTargetQuality(
    int targetQn, {
    bool hasSessionCookie = true,
    bool directedTrafficMode = false,
  }) {
    return false;
  }

  /// Directed-traffic mode is active only when the user opted in AND is
  /// on mobile data.
  static bool shouldEnableDirectedTrafficMode(
    bool directedTrafficEnabled,
    bool isOnMobileData,
  ) {
    return directedTrafficEnabled && isOnMobileData;
  }

  /// WBI parameter overrides injected when directed-traffic mode is
  /// active.
  ///
  /// Returns an empty map when directed-traffic mode is disabled.
  static Map<String, String> buildDirectedTrafficWbiOverrides(
    bool directedTrafficEnabled,
    bool isOnMobileData,
  ) {
    if (!shouldEnableDirectedTrafficMode(directedTrafficEnabled, isOnMobileData)) {
      return {};
    }
    return {
      'platform': 'android',
      'mobi_app': 'android',
      'device': 'android',
      'build': '8130300',
    };
  }

  /// Builds the base WBI parameter map for a playurl request.
  ///
  /// Always includes fnval=4048, fnver=0, fourk=1, voice_balance=1,
  /// gaia_source='pre-load', isGaiaAvoided=true and a fixed
  /// web_location. When [tryLook] is set, `try_look=1` is appended to
  /// negotiate a guest-accessible higher tier. When [audioLang] is set,
  /// `cur_language` is populated.
  static Map<String, dynamic> buildPlayUrlWbiBaseParams(
    String bvid,
    int cid,
    int qn, {
    String? audioLang,
    bool tryLook = false,
  }) {
    final params = <String, dynamic>{
      'bvid': bvid,
      'cid': cid.toString(),
      'qn': qn.toString(),
      'fnval': '4048',
      'fnver': '0',
      'fourk': '1',
      'voice_balance': '1',
      'gaia_source': 'pre-load',
      'isGaiaAvoided': 'true',
      'web_location': '1315873',
    };
    if (tryLook) {
      params['try_look'] = '1';
    }
    if (audioLang != null && audioLang.isNotEmpty) {
      params['cur_language'] = audioLang;
    }
    return params;
  }

  /// `try_look=1` is only useful for guests who want auto-1080P.
  static bool shouldRequestPlayUrlTryLook(
    bool isLoggedIn,
    bool auto1080pEnabled,
  ) {
    return !isLoggedIn && auto1080pEnabled;
  }

  /// Fallback source order for logged-in users.
  static List<PlayUrlSource> buildLoggedInPlaybackFallbackOrder() {
    return [
      PlayUrlSource.dash,
      PlayUrlSource.app,
      PlayUrlSource.legacy,
      PlayUrlSource.guest,
    ];
  }

  /// Fallback source order for guests (no APP path — guests have no
  /// token).
  static List<PlayUrlSource> buildGuestPlaybackFallbackOrder() {
    return [PlayUrlSource.dash, PlayUrlSource.legacy];
  }

  /// Returns true when the APP-API result is acceptable for [targetQn].
  ///
  /// INITIAL requests accept any playable payload to avoid a hard
  /// failure page when the service temporarily downgrades or omits the
  /// requested track. EXPLICIT premium requests (125..127) require the
  /// exact target id in [dashVideoIds]. Other explicit requests: any
  /// quality below 80 is accepted; otherwise the target must appear in
  /// the dash video ids or the returned quality must be >= target.
  static bool shouldAcceptAppApiResultForTargetQuality(
    PlayUrlRequestKind requestKind,
    int targetQn,
    int returnedQuality,
    List<int> dashVideoIds,
  ) {
    if (requestKind == PlayUrlRequestKind.initial) {
      return returnedQuality > 0 || dashVideoIds.isNotEmpty;
    }

    if (isStrictPremiumQualityRequest(requestKind, targetQn)) {
      return dashVideoIds.contains(targetQn);
    }

    if (targetQn < 80) return true;
    if (dashVideoIds.toSet().contains(targetQn)) return true;
    return returnedQuality >= targetQn && returnedQuality > 0;
  }

  /// Qualities tried in order when falling back to guest mode.
  static List<int> buildGuestFallbackQualities() {
    return [80, 64, 32];
  }

  /// Returns true when the returned playurl payload is worth caching.
  ///
  /// Language-specific streams and GUEST responses are never cached.
  /// For requests >= 80 the returned quality must actually satisfy the
  /// request (see [isRequestedQualitySatisfied]).
  static bool shouldCachePlayUrlResult(
    PlayUrlSource source,
    String? audioLang, {
    int requestedQuality = 0,
    int returnedQuality = 0,
    List<int> dashVideoIds = const [],
  }) {
    if (audioLang != null) return false;
    if (source == PlayUrlSource.guest) return false;
    if (requestedQuality >= 80 &&
        !isRequestedQualitySatisfied(
          requestedQuality: requestedQuality,
          returnedQuality: returnedQuality,
          dashVideoIds: dashVideoIds,
        )) {
      return false;
    }
    return true;
  }

  /// Returns true when [returnedQuality] / [dashVideoIds] satisfy the
  /// [requestedQuality].
  ///
  /// Qualities below 80 are always considered satisfied. For 80+ the
  /// target must appear in the dash video ids, or the returned quality
  /// must be >= target (and positive).
  static bool isRequestedQualitySatisfied({
    required int requestedQuality,
    required int returnedQuality,
    required List<int> dashVideoIds,
  }) {
    if (requestedQuality < 80) return true;
    if (dashVideoIds.contains(requestedQuality)) return true;
    return returnedQuality >= requestedQuality && returnedQuality > 0;
  }

  /// Returns true when the DASH manifest contains a playable exact track
  /// the user requested.
  ///
  /// Premium qualities (125 HDR, 126 Dolby Vision, 127 8K) must not be
  /// considered satisfied by a lower-tier response or by an exact-ID
  /// track without a URL.
  static bool hasExactPlayableRequestedTrack(
    int requestedTargetQn,
    List<DashVideo> dashVideos,
  ) {
    return dashVideos.any(
      (v) => v.id == requestedTargetQn && v.validUrl.isNotEmpty,
    );
  }

  static bool isExactRequestedQualitySelected(
    int requestedTargetQn,
    int actualQuality,
  ) {
    return actualQuality == requestedTargetQn;
  }

  /// Returns true when a non-blocking HDR auto-upgrade should be
  /// scheduled after an INITIAL SDR fast-start playback.
  ///
  /// All conditions must be met:
  /// 1. INITIAL (first-load) request.
  /// 2. User has auto-highest quality enabled.
  /// 3. User is VIP.
  /// 4. Not on mobile data (Wi-Fi only).
  /// 5. Valid access_token available.
  /// 6. Current DASH does not already include HDR track 125.
  /// 7. User hasn't made an explicit quality selection.
  /// 8. Upgrade hasn't already been attempted for this session.
  static bool shouldScheduleHdrAutoUpgrade({
    required bool isInitialRequest,
    required bool isAutoHighestQuality,
    required bool isVip,
    required bool isMobileData,
    required bool hasAccessToken,
    required List<int> currentPlayableDashVideoIds,
    required bool userHasExplicitQualitySelection,
    required bool upgradeAlreadyAttempted,
  }) {
    return isInitialRequest &&
        isAutoHighestQuality &&
        isVip &&
        !isMobileData &&
        hasAccessToken &&
        !currentPlayableDashVideoIds.contains(125) &&
        !userHasExplicitQualitySelection &&
        !upgradeAlreadyAttempted;
  }

  static bool shouldFetchCommentEmoteMapOnVideoLoad() => false;

  static bool shouldRefreshVipStatusOnVideoLoad() => false;

  static bool shouldFetchInteractionStatusOnVideoLoad() => false;
}
