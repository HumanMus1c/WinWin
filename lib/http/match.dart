import 'package:winwin/http/api.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/http/loading_state.dart';

/// 赛事信息 HTTP（移植自 PiliPlus `lib/http/match.dart`）。
///
/// 返回原始 JSON Map（contest 节点），由调用方按需提取字段。
abstract final class MatchHttp {
  static Future<LoadingState<Map<String, dynamic>?>> matchInfo(
    Object cid,
  ) async {
    final res = await Request().get(
      Api.matchInfo,
      queryParameters: {
        'cid': cid,
        'platform': 2,
      },
    );
    if (res.data['code'] == 0) {
      final data = res.data['data'];
      final contest = data is Map ? data['contest'] : null;
      return Success(
        contest is Map ? contest.cast<String, dynamic>() : null,
      );
    } else {
      return Error(res.data['message']?.toString() ?? '');
    }
  }
}
