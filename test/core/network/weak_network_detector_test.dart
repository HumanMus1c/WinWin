import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/core/network/weak_network_detector.dart';

void main() {
  late DateTime now;
  late List<String> prompts;
  late WeakNetworkDetector detector;

  setUp(() {
    now = DateTime(2026, 11, 13, 12);
    prompts = <String>[];
    detector = WeakNetworkDetector(
      slowRequestThreshold: const Duration(seconds: 3),
      healthyWindow: const Duration(seconds: 10),
      promptCooldown: const Duration(seconds: 60),
      clock: () => now,
      onPrompt: prompts.add,
    );
  });

  test('慢请求/超时/播放弱网只提示一次', () {
    detector.reportRequestLatency(const Duration(seconds: 4));
    expect(prompts, hasLength(1));

    detector.reportTimeout();
    detector.reportPlaybackWeak();
    expect(prompts, hasLength(1));
  });

  test('连续健康 10 秒后重置回合，并遵守 60 秒冷却', () {
    detector.reportTimeout();
    expect(prompts, hasLength(1));

    now = now.add(const Duration(seconds: 12));
    detector.reportPlaybackHealthy();
    now = now.add(const Duration(seconds: 10));
    detector.reportPlaybackHealthy();

    now = now.add(const Duration(seconds: 20));
    detector.reportTimeout();
    expect(prompts, hasLength(1), reason: '距离上次提示仍不足 60 秒');

    now = now.add(const Duration(seconds: 20));
    detector.reportTimeout();
    expect(prompts, hasLength(2));
  });

  test('快速响应累计健康可重置回合', () {
    detector.reportTimeout();

    now = now.add(const Duration(seconds: 11));
    detector.reportRequestLatency(const Duration(milliseconds: 200));
    now = now.add(const Duration(seconds: 10));
    detector.reportRequestLatency(const Duration(milliseconds: 200));

    now = now.add(const Duration(seconds: 40));
    detector.reportTimeout();
    expect(prompts, hasLength(2));
  });

  test('慢请求未达阈值不算弱网', () {
    detector.reportRequestLatency(const Duration(milliseconds: 2500));
    expect(prompts, isEmpty);
  });

  test('reset 清空回合与冷却', () {
    detector.reportTimeout();
    detector.reset();
    detector.reportTimeout();
    expect(prompts, hasLength(2));
  });
}
