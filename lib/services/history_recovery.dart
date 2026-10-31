import 'dart:async';

import 'package:dio/dio.dart';

import 'package:winwin/core/log/app_logger.dart';
import 'package:winwin/http/api.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/http/response_map.dart';
import 'package:winwin/models/history/history_models.dart';

/// 失效历史稿件的档案信息。
class HistoryRecoveryInfo {
  const HistoryRecoveryInfo({
    this.reason,
    this.title,
    this.cover,
    this.description,
    this.accessible = false,
  });

  /// 失效原因（如「仅作者自己可见」「稿件已删除」）。
  final String? reason;

  /// 恢复出的标题（优先级低于接口原标题）。
  final String? title;

  /// 恢复出的封面。
  final String? cover;

  /// 恢复出的简介。
  final String? description;

  /// 稿件当前是否重新可访问（`/x/web-interface/view` 返回 code 0）。
  final bool accessible;

  bool get hasArchive =>
      (title?.isNotEmpty ?? false) || (cover?.isNotEmpty ?? false);
}

/// 历史记录失效稿件：状态识别 + BiliPlus 档案恢复。
///
/// 借鉴 `Mr-Po/bilibili-favorites-fix` 的恢复路径：
/// 1. `/x/web-interface/view` 的 code 区分「仅作者可见 / 下架 / 删除 / 审核中」；
/// 2. `https://www.biliplus.com/api/view?id=<aid>` 取存档标题 / 封面 / 简介。
/// 该请求使用独立 Dio，**不携带任何 B 站 Cookie**，只发送 aid；失败静默降级。
abstract final class HistoryRecoveryService {
  static final Map<int, HistoryRecoveryInfo> _cache = {};
  static final Map<int, Future<HistoryRecoveryInfo?>> _inFlight = {};

  /// 单页最多 2 个失效条目并发恢复，避免 BiliPlus 限流（-503）。
  static const int _maxConcurrent = 2;
  static int _active = 0;
  static final List<Completer<void>> _waiters = [];

  static HistoryRecoveryInfo? cached(int? aid) {
    if (aid == null || aid <= 0) return null;
    return _cache[aid];
  }

  /// 失效原因码映射（B 站 `/x/web-interface/view`）。
  static String reasonForCode(int code) => switch (code) {
        62012 => '仅作者自己可见',
        62002 => '稿件不可见（可能已下架）',
        62004 => '稿件正在审核中',
        -404 => '稿件已删除',
        -403 => '无权访问该稿件',
        _ => '稿件不可见',
      };

  /// 查询失效稿件信息；同一 aid 只请求一次并缓存。
  static Future<HistoryRecoveryInfo?> lookup(HistoryItem item) {
    final aid = _aidOf(item);
    if (aid == null || aid <= 0) return Future.value(null);
    final cachedInfo = _cache[aid];
    if (cachedInfo != null) return Future.value(cachedInfo);
    final inFlight = _inFlight[aid];
    if (inFlight != null) return inFlight;

    final completer = Completer<HistoryRecoveryInfo?>();
    final future = completer.future;
    _inFlight[aid] = future;

    () async {
      await _acquire();
      try {
        final info = await _fetch(item, aid);
        // 空结果也缓存：避免滚动回到该卡时重复打接口。
        _cache[aid] = info ?? const HistoryRecoveryInfo();
        completer.complete(info);
      } catch (e) {
        AppLogger.w('HistoryRecovery', 'aid=$aid lookup failed: $e');
        _cache[aid] = const HistoryRecoveryInfo();
        completer.complete(null);
      } finally {
        _inFlight.remove(aid);
        _release();
      }
    }();

    return future;
  }

  static int? _aidOf(HistoryItem item) {
    final oid = item.history.oid;
    if (oid != null && oid > 0) return oid;
    return null;
  }

  static Future<void> _acquire() async {
    if (_active < _maxConcurrent) {
      _active++;
      return;
    }
    final waiter = Completer<void>();
    _waiters.add(waiter);
    await waiter.future;
  }

  static void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
      return;
    }
    if (_active > 0) _active--;
  }

  static Future<HistoryRecoveryInfo?> _fetch(HistoryItem item, int aid) async {
    String? reason;
    bool accessible = false;

    // 1) B 站视图接口：判断失效原因；若已恢复可访问则直接用其元数据。
    try {
      final bvid = item.history.bvid;
      final res = await Request.dio.get<dynamic>(
        Api.videoIntro,
        queryParameters: bvid != null && bvid.isNotEmpty
            ? {'bvid': bvid}
            : {'aid': aid},
      );
      final map = asJsonMap(res.data);
      final code = (map['code'] as num?)?.toInt() ?? -1;
      if (code == 0) {
        accessible = true;
        final data = map['data'];
        if (data is Map) {
          final title = data['title']?.toString();
          final pic = data['pic']?.toString();
          final desc = data['desc']?.toString();
          if (title != null && title.isNotEmpty) {
            return HistoryRecoveryInfo(
              title: title,
              cover: pic,
              description: desc,
              accessible: true,
            );
          }
        }
      } else {
        reason = reasonForCode(code);
      }
    } catch (e) {
      AppLogger.w('HistoryRecovery', 'view aid=$aid failed: $e');
    }

    // 2) BiliPlus 档案：独立 Dio，不带 Cookie；-503 表示限流，直接降级。
    String? title;
    String? cover;
    String? description;
    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
          validateStatus: (_) => true,
          headers: const {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'},
        ),
      );
      final res = await dio.get<dynamic>(
        'https://www.biliplus.com/api/view',
        queryParameters: {'id': aid},
      );
      final map = asJsonMap(res.data);
      final code = (map['code'] as num?)?.toInt();
      if (code != -503) {
        title = map['title']?.toString();
        cover = map['pic']?.toString();
        description = map['description']?.toString();
      }
    } catch (e) {
      AppLogger.w('HistoryRecovery', 'biliplus aid=$aid failed: $e');
    }

    return HistoryRecoveryInfo(
      reason: reason ?? (accessible ? null : '稿件不可见'),
      title: title != null && title.isNotEmpty ? title : null,
      cover: cover != null && cover.isNotEmpty ? cover : null,
      description: description != null && description.isNotEmpty
          ? description
          : null,
      accessible: accessible,
    );
  }
}
