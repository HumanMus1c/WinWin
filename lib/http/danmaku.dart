import 'package:dio/dio.dart';

import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/http/api.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/http/loading_state.dart';

/// 弹幕发送 HTTP 接口。
///
/// ⚠️ 占位实现（由播放器 agent 按契约补建，并行 agent 交付后应覆盖此文件）。
/// 契约：`shootDanmaku` → POST /x/v2/dm/post，返回 `LoadingState<int>`（弹幕 id）。
abstract final class DanmakuHttp {
  static Future<LoadingState<int>> shootDanmaku({
    int type = 1,
    required int oid,
    required String msg,
    int mode = 1,
    String? bvid,
    required int progress,
    int color = 0xFFFFFF,
    int fontSize = 25,
  }) async {
    final account = Accounts.main;
    if (!account.isLogin) {
      return const Error('请先登录');
    }
    try {
      final data = <String, dynamic>{
        'type': type,
        'oid': oid,
        'msg': msg,
        'mode': mode,
        if (bvid != null && bvid.isNotEmpty) 'bvid': bvid,
        'progress': progress,
        'color': color,
        'fontsize': fontSize,
        'rnd': DateTime.now().microsecondsSinceEpoch,
        'csrf': account.csrf,
      };
      final res = await Request().post<dynamic>(
        Api.shootDanmaku,
        data: data,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: account.headers,
        ),
      );
      final resData = res.data;
      if (resData is Map && resData['code'] == 0) {
        final d = resData['data'];
        final id = d is Map ? (d['id'] is int ? d['id'] as int : 0) : 0;
        return Success(id);
      }
      return Error(
        resData is Map ? (resData['message'] ?? '弹幕发送失败') : '弹幕发送失败',
        code: resData is Map ? resData['code'] as int? : null,
      );
    } catch (e) {
      return Error('弹幕发送失败：$e');
    }
  }
}
