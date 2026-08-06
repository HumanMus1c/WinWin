import 'package:dio/dio.dart';

import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/grpc/bilibili/community/service/dm/v1.pb.dart';
import 'package:winwin/http/api.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/http/loading_state.dart';

/// 弹幕 HTTP 接口（移植自 PiliPlus `lib/http/danmaku.dart` + `lib/grpc/dm.dart`）。
///
/// WinWin 不引入 gRPC 栈，改用 B 站 HTTP protobuf 端点
/// `/x/v2/dm/web/seg.so` 拉取分段弹幕，返回 [DmSegMobileReply] 的原始 bytes，
/// 本地 `fromBuffer` 解析。这等价于 PiliPlus 的 `DmGrpc.dmSegMobile`。
abstract final class DanmakuHttp {
  /// 拉取分段弹幕。
  ///
  /// - [cid]：视频 cid。
  /// - [segmentIndex]：1-based 段号（每段 6 分钟，调用方需 +1 转换）。
  /// - [type]：1=视频弹幕。
  ///
  /// 成功返回 [DmSegMobileReply]（含 `elems` 列表与 `state`，state==1 表示
  /// UP 关闭了该视频弹幕）。
  static Future<LoadingState<DmSegMobileReply>> getDanmakuSegment({
    required int cid,
    required int segmentIndex,
    int type = 1,
  }) async {
    try {
      final res = await Request().get<List<int>>(
        Api.webDanmaku,
        queryParameters: {
          'type': type,
          'oid': cid,
          'segment_index': segmentIndex,
        },
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = res.data;
      if (bytes == null || bytes.isEmpty) {
        return const Error('弹幕数据为空');
      }
      final reply = DmSegMobileReply.fromBuffer(bytes);
      return Success(reply);
    } on DioException catch (e) {
      // 304 / 403 等也走这里；弹幕分段失败不应阻断播放，交给上层降级。
      return Error('弹幕拉取失败：${e.message ?? e.type.name}');
    } catch (e) {
      return Error('弹幕拉取失败：$e');
    }
  }

  /// 发送弹幕（POST `/x/v2/dm/post`）。
  ///
  /// - [oid]：视频 cid。
  /// - [msg]：弹幕文本（≤100 字）。
  /// - [mode]：1=滚动 / 4=底部 / 5=顶部 / 7=高级。
  /// - [progress]：发送时刻（毫秒）。
  /// - [color]：RGB 24 位十进制（默认 16777215=白）。
  /// - [fontSize]：默认 25。
  /// - [colorful]：true 时发送会员专属渐变彩（color=60001）。
  /// - [bvid]：可选，便于服务端统计。
  ///
  /// 成功返回弹幕 id（dmid）。
  static Future<LoadingState<int>> shootDanmaku({
    int type = 1,
    required int oid,
    required String msg,
    int mode = 1,
    String? bvid,
    required int progress,
    int color = 0xFFFFFF,
    int fontSize = 25,
    bool colorful = false,
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
        // colorful 时强制 color=60001（VipGradualColor），否则传 RGB。
        'color': colorful ? 60001 : (color & 0xFFFFFF),
        'fontsize': fontSize,
        // microsecondsSinceEpoch 用于突破 90s 冷却到 5s（PiliPlus 约定）。
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
