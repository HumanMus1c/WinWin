import 'package:dio/dio.dart';

import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/http/api.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/models/danmaku/danmaku_block.dart';
import 'package:winwin/models/danmaku/danmaku_rule.dart';
import 'package:winwin/utils/crc32.dart';

/// 弹幕屏蔽规则 HTTP 同步（移植自 PiliPlus `lib/http/danmaku_block.dart`）。
///
/// 三个端点：
/// - GET  `/x/dm/filter/user`      拉取云端规则。
/// - POST `/x/dm/filter/user/add`  添加规则（type: 0=关键词/1=正则/2=用户）。
/// - POST `/x/dm/filter/user/del`  删除规则（按 id）。
///
/// 注意：用户屏蔽（type=2）上传的 `filter` 是 mid 的 **midHash**（CRC32 hex），
/// 而非原始 uid——因为弹幕数据里只有 midHash。
abstract final class DanmakuFilterHttp {
  /// 拉取云端屏蔽规则。
  static Future<LoadingState<DanmakuBlockDataModel>> danmakuFilter() async {
    try {
      final res = await Request().get<dynamic>(Api.danmakuFilter);
      final data = res.data;
      if (data is Map && data['code'] == 0) {
        return Success(DanmakuBlockDataModel.fromJson(
          (data['data'] as Map?)?.cast<String, dynamic>() ?? const {},
        ));
      }
      return Error(data is Map ? (data['message'] ?? '拉取屏蔽规则失败') : '拉取屏蔽规则失败');
    } catch (e) {
      return Error('拉取屏蔽规则失败：$e');
    }
  }

  /// 添加屏蔽规则。
  ///
  /// [type] 0=关键词 / 1=正则 / 2=用户。用户类型需传入原始 uid，内部转 midHash。
  /// 成功返回服务端创建的 [SimpleRule]（含 id）。
  static Future<LoadingState<SimpleRule>> danmakuFilterAdd({
    required String filter,
    required int type,
  }) async {
    final account = Accounts.main;
    if (!account.isLogin) return const Error('请先登录');
    try {
      // 用户屏蔽：uid → midHash（CRC32 hex），与服务端字段格式对齐。
      final String uploadedFilter;
      if (type == DmBlockType.uid.serverType) {
        final mid = int.tryParse(filter);
        if (mid == null || mid <= 0) return const Error('用户 UID 不合法');
        uploadedFilter = Crc32.midHash(mid);
      } else if (type == DmBlockType.regex.serverType) {
        // 正则按约定用 /.../ 包裹上传。
        uploadedFilter =
            filter.startsWith('/') && filter.endsWith('/') ? filter : '/$filter/';
      } else {
        uploadedFilter = filter;
      }

      final res = await Request().post<dynamic>(
        Api.danmakuFilterAdd,
        data: {
          'type': type,
          'filter': uploadedFilter,
          'csrf': account.csrf,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: account.headers,
        ),
      );
      final data = res.data;
      if (data is Map && data['code'] == 0) {
        final d = data['data'];
        if (d is Map) {
          return Success(SimpleRule(
            id: d['id'] as int? ?? 0,
            type: type,
            // 本地保留用户可读形式：用户类型存原始 uid 字符串，正则存原始输入。
            filter: filter,
          ));
        }
      }
      return Error(data is Map ? (data['message'] ?? '添加屏蔽规则失败') : '添加屏蔽规则失败');
    } catch (e) {
      return Error('添加屏蔽规则失败：$e');
    }
  }

  /// 删除屏蔽规则（按 id）。
  static Future<LoadingState<void>> danmakuFilterDel({required int ids}) async {
    final account = Accounts.main;
    if (!account.isLogin) return const Error('请先登录');
    try {
      final res = await Request().post<dynamic>(
        Api.danmakuFilterDel,
        data: {
          'ids': ids,
          'csrf': account.csrf,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: account.headers,
        ),
      );
      final data = res.data;
      if (data is Map && data['code'] == 0) return const Success(null);
      return Error(data is Map ? (data['message'] ?? '删除屏蔽规则失败') : '删除屏蔽规则失败');
    } catch (e) {
      return Error('删除屏蔽规则失败：$e');
    }
  }
}
