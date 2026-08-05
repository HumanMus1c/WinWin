// TODO: Phase 2 — implement with protobuf metadata
//       (Device, Network, Locale, FawkesReq, Metadata).

/// Minimal stub for gRPC request headers.
/// Returns an empty header map so the app-sign / cookie interceptor
/// can compile and run without the full protobuf stack.
abstract final class GrpcHeaders {
  static Map<String, String> build([String? accessKey]) {
    return <String, String>{
      if (accessKey != null) 'authorization': 'identify_v1 $accessKey',
    };
  }
}
