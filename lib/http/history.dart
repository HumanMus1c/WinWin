import 'package:dio/dio.dart';

import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/http/api.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/models/history/history_models.dart';

/// 历史记录 HTTP（移植自 PiliPlus `lib/http/user.dart` 的 history 部分）。
abstract final class HistoryHttp {
  /// 拉取历史列表（游标分页）。
  ///
  /// [type] 分类：'all' / 'archive' / 'live' / 'article'。
  /// [max] / [viewAt] 为上一页末尾项的 oid / view_at，首页传 null。
  static Future<LoadingState<HistoryData>> historyList({
    String type = 'all',
    int? max,
    int? viewAt,
  }) async {
    try {
      final res = await Request().get<dynamic>(
        Api.historyList,
        queryParameters: {
          'type': type,
          'ps': 20,
          'max': max ?? 0,
          'view_at': viewAt ?? 0,
        },
      );
      final data = res.data as Map<String, dynamic>;
      if (data['code'] == 0) {
        return Success(HistoryData.fromJson(data['data'] as Map<String, dynamic>));
      }
      return Error(data['message']?.toString() ?? '获取历史失败');
    } catch (e) {
      return Error('获取历史失败：$e');
    }
  }

  /// 删除单条/批量历史（[kid] 格式 `business_kid`，多条逗号拼接）。
  static Future<LoadingState<void>> delHistory(String kid) async {
    try {
      final res = await Request().post<dynamic>(
        Api.delHistory,
        data: {
          'kid': kid,
          'jsonp': 'jsonp',
          'csrf': Accounts.history.csrf,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final data = res.data as Map<String, dynamic>;
      if (data['code'] == 0) return const Success(null);
      return Error(data['message']?.toString() ?? '删除失败');
    } catch (e) {
      return Error('删除失败：$e');
    }
  }

  /// 清空历史。
  static Future<LoadingState<void>> clearHistory() async {
    try {
      final res = await Request().post<dynamic>(
        Api.clearHistory,
        data: {'jsonp': 'jsonp', 'csrf': Accounts.history.csrf},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final data = res.data as Map<String, dynamic>;
      if (data['code'] == 0) return const Success(null);
      return Error(data['message']?.toString() ?? '清空失败');
    } catch (e) {
      return Error('清空失败：$e');
    }
  }

  /// 暂停/恢复历史记录（[switchStatus] true=暂停）。
  static Future<LoadingState<void>> pauseHistory(bool switchStatus) async {
    try {
      final res = await Request().post<dynamic>(
        Api.pauseHistory,
        data: {
          'switch': switchStatus,
          'jsonp': 'jsonp',
          'csrf': Accounts.history.csrf,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final data = res.data as Map<String, dynamic>;
      if (data['code'] == 0) return const Success(null);
      return Error(data['message']?.toString() ?? '操作失败');
    } catch (e) {
      return Error('操作失败：$e');
    }
  }

  /// 上报视频播放进度（heartbeat）。
  ///
  /// [progress] 单位秒，-1 表示看完。
  static Future<void> heartBeat({
    int? aid,
    String? bvid,
    required int cid,
    required int progress,
    int? epid,
    int? seasonId,
  }) async {
    try {
      await Request().post<dynamic>(
        Api.heartBeat,
        data: {
          if (aid != null) 'aid': aid,
          if (bvid != null) 'bvid': bvid,
          'cid': cid,
          if (epid != null) 'epid': epid,
          if (seasonId != null) 'sid': seasonId,
          'type': 3,
          'played_time': progress,
          'csrf': Accounts.heartbeat.csrf,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
    } catch (_) {
      // 心跳失败静默，不阻断播放。
    }
  }
}
