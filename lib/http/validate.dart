import 'package:dio/dio.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/http/api.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/http/loading_state.dart';

/// 人机验证 HTTP（移植自 PiliPlus `lib/http/validate.dart`）。
///
/// 用于风控场景：发评论/发动态/登录等被风控拦截时，通过此接口完成验证。
abstract final class ValidateHttp {
  /// 注册验证（获取 v_voucher）。
  static Future<LoadingState<Map<String, dynamic>?>> gaiaVgateRegister(
    String vVoucher,
  ) async {
    final res = await Request().post(
      Api.gaiaVgateRegister,
      queryParameters: {
        if (Accounts.main.isLogin) 'csrf': Accounts.main.csrf,
      },
      data: {
        'v_voucher': vVoucher,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
      ),
    );
    if (res.data['code'] == 0) {
      final data = res.data['data'];
      return Success(
        data is Map ? data.cast<String, dynamic>() : null,
      );
    } else {
      return Error(res.data['message']?.toString() ?? '');
    }
  }

  /// 提交验证结果。
  static Future<LoadingState<Map<String, dynamic>?>> gaiaVgateValidate({
    required dynamic challenge,
    required dynamic seccode,
    required dynamic token,
    required dynamic validate,
  }) async {
    final res = await Request().post(
      Api.gaiaVgateValidate,
      queryParameters: {
        if (Accounts.main.isLogin) 'csrf': Accounts.main.csrf,
      },
      data: {
        'challenge': challenge,
        'seccode': seccode,
        'token': token,
        'validate': validate,
      },
    );
    if (res.data['code'] == 0) {
      final data = res.data['data'];
      return Success(
        data is Map ? data.cast<String, dynamic>() : null,
      );
    } else {
      return Error(res.data['message']?.toString() ?? '');
    }
  }
}
