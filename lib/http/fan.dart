import 'package:winwin/http/api.dart';
import 'package:winwin/http/error_msg.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/http/loading_state.dart';

/// 粉丝列表 HTTP（移植自 PiliPlus `lib/http/fan.dart`）。
///
/// 返回原始 JSON Map，包含 `list`（每项含 mid/name/face/sign 等）和 `total`。
abstract final class FanHttp {
  static Future<LoadingState<Map<String, dynamic>>> fans({
    int? vmid,
    int? pn,
    int ps = 20,
    String? orderType,
  }) async {
    final res = await Request().get(
      Api.fans,
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
}
