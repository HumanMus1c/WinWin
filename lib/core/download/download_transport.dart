// Phase 5 下载系统 · 批次2：下载传输层抽象（可注入，便于离线单测）。
//
// 生产实现见 `dio_download_transport.dart`；测试用假实现（内存 / 分片字节），
// 使引擎编排逻辑（续传 / 分片 / 进度 / 取消）可在无网络条件下完整验证。

import 'package:winwin/core/download/download_policy.dart';

/// 传输层取消信号：取消是预期行为，不视为下载错误。
class DownloadCancelledException implements Exception {
  const DownloadCancelledException();

  @override
  String toString() => 'DownloadCancelledException';
}

/// 下载传输抽象：探测远端规模 + 拉取指定字节区间。
///
/// 接口刻意保持最小（probe / fetchRange / close），生产与测试各自实现，
/// 从而把「网络 IO」与「引擎编排」分离（单一职责）。
abstract interface class DownloadTransport {
  /// 探测资源总字节数与是否支持 Range 分段。
  ///
  /// 返回的 [DownloadRangeProbe.totalBytes] 为 0 表示服务器未提供长度（未知）。
  Future<DownloadRangeProbe> probe({
    required Uri url,
    required Map<String, String> headers,
  });

  /// 拉取 [startBytes, endBytesInclusive]（闭区间）的内容。
  ///
  /// - [startBytes] 为 null 表示从 0 开始；
  /// - [endBytesInclusive] 为 null 表示读到资源结尾；
  /// - 每个数据块经 [onChunk] 回调，并携带该块在资源中的**绝对**偏移，
  ///   以便引擎按位置写入（支持并行分片）；
  /// - [isCancelled] 返回 true 时，实现应尽快抛出 [DownloadCancelledException]。
  Future<void> fetchRange({
    required Uri url,
    required Map<String, String> headers,
    int? startBytes,
    int? endBytesInclusive,
    required Future<void> Function(List<int> data, int absoluteOffset) onChunk,
    bool Function()? isCancelled,
  });

  /// 释放底层资源（连接池等）。引擎不负责调用生命周期，由持有方管理。
  void close();
}