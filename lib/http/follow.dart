import 'package:dio/dio.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/http/api.dart';
import 'package:winwin/http/error_msg.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/http/loading_state.dart';

/// 关注列表 HTTP（移植自 PiliPlus `lib/http/follow.dart`）。
abstract final class FollowHttp {
  /// 关注列表。
  ///
  /// [orderType] 为空表示最近关注，'attention' 表示最常访问。
  static Future<LoadingState<Map<String, dynamic>>> followings({
    int? vmid,
    int? pn,
    int ps = 20,
    String orderType = '',
  }) async {
    final res = await Request().get(
      Api.followings,
      queryParameters: {
        'vmid': vmid,
        'pn': pn,
        'ps': ps,
        'order': 'desc',
        'order_type': orderType,
      },
    );
    if (res.data['code'] == 0) {
      return Success(
        (res.data['data'] as Map?)?.cast<String, dynamic>() ?? {},
      );
    } else {
      return Error(
        errorMsg[res.data['code']] ?? res.data['message']?.toString() ?? '',
      );
    }
  }

  /// 查询与指定用户的关系（/x/relation）。
  ///
  /// data 本身即关系对象：attribute（0=未关注 2=已关注）、
  /// special（1=特别关注），会话列表用于展示“特别关注”标签。
  static Future<LoadingState<Map<String, dynamic>>> relation({
    required int fid,
  }) async {
    final res = await Request().get(
      Api.relation,
      queryParameters: {'fid': fid},
    );
    if (res.data['code'] == 0) {
      return Success(
        (res.data['data'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
    } else {
      return Error(res.data['message']?.toString() ?? '');
    }
  }

  /// 获取指定关注分组下的用户列表（/x/relation/tag）。
  ///
  /// [tagid] 为 -10 时即“特别关注”分组。返回 `{list, total}`：
  /// list 每项含 mid，total 为分组总人数（兼容 data 为裸数组的返回形态）。
  static Future<LoadingState<Map<String, dynamic>>> followGroupUsers({
    required int tagid,
    int pn = 1,
    int ps = 50,
  }) async {
    final res = await Request().get(
      Api.followUpGroup,
      queryParameters: {
        'tagid': tagid,
        'pn': pn,
        'ps': ps,
        'order': 'desc',
        'order_type': 'attention',
      },
    );
    if (res.data['code'] == 0) {
      final data = res.data['data'];
      if (data is Map) {
        return Success({
          'list': data['list'] is List ? data['list'] as List : const [],
          'total': (data['total'] as num?)?.toInt() ?? 0,
        });
      }
      if (data is List) {
        return Success({'list': data, 'total': data.length});
      }
      return Success(const {'list': [], 'total': 0});
    } else {
      return Error(res.data['message']?.toString() ?? '');
    }
  }

  /// 关注分组排序。
  static Future<LoadingState<void>> sortFollowTag({
    required String tagids,
  }) async {
    final res = await Request().post(
      Api.sortFollowTag,
      queryParameters: {
        'x-bili-device-req-json':
            '{"platform":"web","device":"pc","spmid":"333.1387"}',
      },
      data: {
        'tagids': tagids,
        'csrf': Accounts.main.csrf,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']?.toString() ?? '');
    }
  }
}
