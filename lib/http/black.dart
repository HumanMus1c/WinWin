import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/http/api.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/http/loading_state.dart';

/// 黑名单 HTTP（移植自 PiliPlus `lib/http/black.dart`）。
///
/// 返回原始 JSON Map，不引入 PiliPlus 的 BlackListData 模型。
/// 调用方按需提取 `data.list` 和 `data.total` 字段。
abstract final class BlackHttp {
  static Future<LoadingState<Map<String, dynamic>>> blackList({
    required int pn,
    int ps = 50,
  }) async {
    final res = await Request().get(
      Api.blackLst,
      queryParameters: {
        'pn': pn,
        'ps': ps,
        're_version': 0,
        'jsonp': 'jsonp',
        'csrf': Accounts.main.csrf,
      },
    );
    if (res.data['code'] == 0) {
      return Success(
        (res.data['data'] as Map?)?.cast<String, dynamic>() ?? {},
      );
    } else {
      return Error(res.data['message']);
    }
  }
}
