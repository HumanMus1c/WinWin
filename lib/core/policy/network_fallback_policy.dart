// Ported from BiliPai (Kotlin) -> WinWin (Dart)
// Original: com/android/purebilibili/core/network/policy/NetworkFallbackPolicy.kt
//
// Network fallback policy: hardcoded DNS fallback table and
// certificate-trust toggle for bilibili hosts.

/// A single hardcoded DNS fallback entry.
class HardcodedDnsFallback {
  /// Canonical hostname, e.g. `api.bilibili.com`.
  final String hostname;

  /// Pre-resolved IPv4 address.
  final String ipAddress;

  /// Human-readable description of what the host serves.
  final String description;

  const HardcodedDnsFallback({
    required this.hostname,
    required this.ipAddress,
    required this.description,
  });
}

/// Hardcoded DNS fallback table for bilibili hosts.
///
/// These IPs are used as a last-resort resolution when system DNS is
/// poisoned, hijacked, or timing out. The mapping is keyed by the
/// lowercased hostname.
const Map<String, HardcodedDnsFallback> _supportedDnsFallbacks = {
  'api.bilibili.com': HardcodedDnsFallback(
    hostname: 'api.bilibili.com',
    ipAddress: '47.103.24.173',
    description: 'Bilibili API',
  ),
  'passport.bilibili.com': HardcodedDnsFallback(
    hostname: 'passport.bilibili.com',
    ipAddress: '47.103.24.175',
    description: 'Bilibili Passport',
  ),
  'i0.hdslb.com': HardcodedDnsFallback(
    hostname: 'i0.hdslb.com',
    ipAddress: '116.63.10.36',
    description: 'Bilibili Image CDN',
  ),
};

/// Aggregates network fallback policy helpers as static methods.
class NetworkFallbackPolicy {
  NetworkFallbackPolicy._();

  /// Returns true when all TLS certificates should be trusted.
  ///
  /// In production this must be false; debug builds may opt in to
  /// bypass self-signed / pinned-cert failures while developing.
  static bool shouldEnableTrustAllCertificates(bool isDebugBuild) {
    return isDebugBuild;
  }

  /// Looks up a hardcoded DNS fallback entry for [hostname].
  ///
  /// Returns null when either:
  /// - [allowHardcodedIpFallback] is false (feature disabled), or
  /// - no entry exists for the (trimmed, lowercased) hostname.
  static HardcodedDnsFallback? resolveHardcodedDnsFallback(
    String hostname,
    bool allowHardcodedIpFallback,
  ) {
    if (!allowHardcodedIpFallback) return null;
    return _supportedDnsFallbacks[hostname.trim().toLowerCase()];
  }
}
