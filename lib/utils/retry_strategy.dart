/// 重试策略 — 从 BiliPai RetryStrategy.kt 移植。
///
/// 标准指数退避：initialDelay → ×multiplier → 上限 maxDelay。
/// sealed RetryResult 区分成功/失败（含尝试次数）。
class RetryConfig {
  final int maxAttempts;
  final int initialDelayMs;
  final int maxDelayMs;
  final double multiplier;

  const RetryConfig({
    this.maxAttempts = 4,
    this.initialDelayMs = 500,
    this.maxDelayMs = 5000,
    this.multiplier = 2.0,
  });
}

sealed class RetryResult<T> {
  const RetryResult();
}

class RetrySuccess<T> extends RetryResult<T> {
  final T data;
  const RetrySuccess(this.data);
}

class RetryFailure<T> extends RetryResult<T> {
  final Object error;
  final int attemptsMade;
  const RetryFailure(this.error, this.attemptsMade);
}

class RetryStrategy {
  RetryStrategy._();

  /// 执行 [block]，失败时按指数退避重试。
  ///
  /// - [config] 重试参数。
  /// - [onAttempt] 每次尝试前回调（attempt 从 1 开始）。
  /// - [shouldRetry] 异常判定，默认全部重试。
  /// - [block] 返回 null 视为失败。
  static Future<RetryResult<T>> executeWithRetry<T>({
    RetryConfig config = const RetryConfig(),
    void Function(int attempt, int maxAttempts)? onAttempt,
    bool Function(Object error)? shouldRetry,
    required Future<T?> Function() block,
  }) async {
    int currentDelay = config.initialDelayMs;
    Object? lastError;

    for (int attempt = 0; attempt < config.maxAttempts; attempt++) {
      onAttempt?.call(attempt + 1, config.maxAttempts);
      try {
        final result = await block();
        if (result != null) {
          return RetrySuccess(result);
        }
        lastError = 'Result was null';
      } catch (e) {
        lastError = e;
        if (shouldRetry != null && !shouldRetry(e)) {
          return RetryFailure(e, attempt + 1);
        }
      }
      // 最后一次不再 delay
      if (attempt < config.maxAttempts - 1) {
        await Future.delayed(Duration(milliseconds: currentDelay));
        currentDelay = (currentDelay * config.multiplier)
            .clamp(0, config.maxDelayMs)
            .toInt();
      }
    }
    return RetryFailure(lastError ?? 'Unknown error', config.maxAttempts);
  }

  /// 执行 [block]，失败时重试，最终失败时抛异常。
  static Future<T> retryOrThrow<T>({
    RetryConfig config = const RetryConfig(),
    void Function(int attempt, int maxAttempts)? onAttempt,
    bool Function(Object error)? shouldRetry,
    required Future<T?> Function() block,
  }) async {
    final result = await executeWithRetry<T>(
      config: config,
      onAttempt: onAttempt,
      shouldRetry: shouldRetry,
      block: block,
    );
    switch (result) {
      case RetrySuccess(:final data):
        return data;
      case RetryFailure(:final error):
        throw Exception('重试 $config.maxAttempts 次后仍失败: $error');
    }
  }
}
