import 'dart:math';

import 'package:winwin/http/history.dart';
import 'package:winwin/http/loading_state.dart';

/// 演示模式：播放器预设值。
///
/// 演示播放器的时间轴时长以“正常模式观看历史的最小时长 – 最大时长”为范围
/// 随机生成（用户指定的行为）；历史不可用（未登录 / 网络失败）时回退默认
/// 范围（1–45 分钟）。范围仅在本次运行内获取一次（best-effort）。
abstract final class DemoPlayerPresets {
  static List<Duration>? _range;
  static bool _fetching = false;

  static const List<Duration> _fallback = [
    Duration(minutes: 1),
    Duration(minutes: 45),
  ];

  /// 一次性拉取观看历史时长范围（仅供演示时长推导，不展示任何历史内容）。
  static Future<void> ensureFetched() async {
    if (_range != null || _fetching) return;
    _fetching = true;
    try {
      final res = await HistoryHttp.historyList();
      if (res case Success(:final response)) {
        final durations = <int>[];
        for (final item in response.list ?? const []) {
          final d = item.duration ?? 0;
          if (d > 0) durations.add(d);
        }
        if (durations.isNotEmpty) {
          durations.sort();
          _range = [
            Duration(seconds: durations.first.clamp(30, 86400)),
            Duration(seconds: durations.last.clamp(30, 86400)),
          ];
        }
      }
    } catch (_) {}
    _fetching = false;
  }

  /// 生成随机演示时长（秒）：优先历史 min–max 范围，其次回退范围。
  static int durationSeconds(int seed) {
    final range = _range ?? _fallback;
    final min = range.first.inSeconds;
    final max = range.last.inSeconds;
    if (max <= min) return min;
    return min + Random(seed ^ (min * 31 + max)).nextInt(max - min + 1);
  }
}
