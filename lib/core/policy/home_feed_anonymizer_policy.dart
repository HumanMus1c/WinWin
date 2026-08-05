// Ported from BiliPai (Kotlin) -> WinWin (Dart)
// Original: com/android/purebilibili/core/network/policy/HomeFeedAnonymizerPolicy.kt
//
// Home feed anonymizer policy: strips authentication cookies from home
// feed requests so that bilibili returns non-personalized recommendations
// instead of recommendations tuned to the logged-in account.

/// Host of bilibili's public web API.
const String BILIBILI_API_HOST = 'api.bilibili.com';

/// Path of the web home-feed (top feed recommend) endpoint.
const String WEB_HOME_FEED_PATH =
    '/x/web-interface/wbi/index/top/feed/rcmd';

/// Immutable snapshot of the anonymizer runtime's hit stats.
///
/// Ported from the Kotlin `HomeFeedAnonymizerStatsSnapshot` /
/// `HomeFeedAnonymizerDecision` data classes. In the Dart port a single
/// decision object carries both the decision ([shouldClear]) and the
/// stats snapshot at the moment the decision was made.
class HomeFeedAnonymizerDecision {
  /// Whether auth cookies should be cleared for this request.
  final bool shouldClear;

  /// Total number of feed-anonymizer hits since the last reset.
  final int totalHits;

  /// Epoch milliseconds of the most recent hit, or `null` if never hit.
  final int? lastHitTime;

  /// Host of the most recent hit, or `null` if never hit.
  final String? lastHitHost;

  /// Encoded path of the most recent hit, or `null` if never hit.
  final String? lastHitPath;

  const HomeFeedAnonymizerDecision({
    required this.shouldClear,
    required this.totalHits,
    this.lastHitTime,
    this.lastHitHost,
    this.lastHitPath,
  });

  @override
  String toString() {
    return 'HomeFeedAnonymizerDecision(shouldClear: $shouldClear, '
        'totalHits: $totalHits, lastHitTime: $lastHitTime, '
        'lastHitHost: $lastHitHost, lastHitPath: $lastHitPath)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HomeFeedAnonymizerDecision &&
        other.shouldClear == shouldClear &&
        other.totalHits == totalHits &&
        other.lastHitTime == lastHitTime &&
        other.lastHitHost == lastHitHost &&
        other.lastHitPath == lastHitPath;
  }

  @override
  int get hashCode => Object.hash(
        shouldClear,
        totalHits,
        lastHitTime,
        lastHitHost,
        lastHitPath,
      );
}

/// Thread-safe singleton runtime that records how many times the
/// anonymizer has actually stripped cookies from a home-feed request.
///
/// Dart runs on a single-threaded event loop per isolate, so synchronous
/// field reads and writes are atomic with respect to each other; there is
/// no need for a monitor lock for the trivial counter/string mutations
/// performed here (unlike the Kotlin original which used `synchronized`).
/// Cross-isolate safety is out of scope for this policy: it is consumed
/// from a single network layer isolate.
class HomeFeedAnonymizerRuntime {
  HomeFeedAnonymizerRuntime._();

  static final HomeFeedAnonymizerRuntime instance =
      HomeFeedAnonymizerRuntime._();

  int _totalHits = 0;
  int? _lastHitTime;
  String? _lastHitHost;
  String? _lastHitPath;

  /// Total hits since the last [resetStats].
  int get totalHits => _totalHits;

  /// Epoch milliseconds of the most recent hit, or `null`.
  int? get lastHitTime => _lastHitTime;

  /// Host of the most recent hit, or `null`.
  String? get lastHitHost => _lastHitHost;

  /// Encoded path of the most recent hit, or `null`.
  String? get lastHitPath => _lastHitPath;

  /// Records a hit for the given [host] / [path].
  ///
  /// [nowMs] defaults to the current epoch milliseconds; pass an explicit
  /// value to make the call deterministic in tests.
  void recordHit(String host, String path, {int? nowMs}) {
    final ts = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    _totalHits += 1;
    _lastHitTime = ts;
    _lastHitHost = host;
    _lastHitPath = path;
  }

  /// Resets all stats to their initial (never-hit) state.
  void resetStats() {
    _totalHits = 0;
    _lastHitTime = null;
    _lastHitHost = null;
    _lastHitPath = null;
  }
}

/// Aggregates home-feed cookie-anonymizer policy helpers as static methods.
///
/// The policy is intentionally pure and side-effect-free: the only stateful
/// component is [HomeFeedAnonymizerRuntime], which the decision resolver
/// touches when it actually decides to clear cookies.
class HomeFeedAnonymizerPolicy {
  HomeFeedAnonymizerPolicy._();

  /// Returns `true` when auth cookies must be stripped for the request
  /// identified by [host] and [path].
  ///
  /// That is the case only when the anonymizer is [enabled], the [host] is
  /// [BILIBILI_API_HOST], and [path] is [WEB_HOME_FEED_PATH].
  static bool shouldClearHomeFeedCookies(
    String host,
    String path,
    bool enabled,
  ) {
    return enabled &&
        host == BILIBILI_API_HOST &&
        path == WEB_HOME_FEED_PATH;
  }

  /// Returns the cookie header names that should survive the policy.
  ///
  /// When [shouldClear] is `true`, every name is dropped (an empty list is
  /// returned) so the request goes out with no auth cookies. When `false`,
  /// [originalNames] is returned unchanged.
  static List<String> filterHomeFeedCookieHeaderNames(
    List<String> originalNames,
    bool shouldClear,
  ) {
    return shouldClear ? const <String>[] : originalNames;
  }

  /// Resolves the anonymizer decision for a request, recording a hit on
  /// the runtime when it actually clears cookies.
  ///
  /// Returns a [HomeFeedAnonymizerDecision] carrying both the [shouldClear]
  /// verdict and a snapshot of the runtime stats taken after the (possible)
  /// hit was recorded.
  static HomeFeedAnonymizerDecision resolveHomeFeedCookieAnonymizerDecision(
    String host,
    String path,
    bool enabled, {
    int? nowMs,
  }) {
    final shouldClear = shouldClearHomeFeedCookies(host, path, enabled);
    if (shouldClear) {
      HomeFeedAnonymizerRuntime.instance.recordHit(
        host,
        path,
        nowMs: nowMs,
      );
    }
    final runtime = HomeFeedAnonymizerRuntime.instance;
    return HomeFeedAnonymizerDecision(
      shouldClear: shouldClear,
      totalHits: runtime.totalHits,
      lastHitTime: runtime.lastHitTime,
      lastHitHost: runtime.lastHitHost,
      lastHitPath: runtime.lastHitPath,
    );
  }
}
