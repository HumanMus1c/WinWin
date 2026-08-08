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
