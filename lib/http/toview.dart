import 'package:dio/dio.dart';

import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/http/api.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/models/toview/toview_models.dart';
import 'package:winwin/utils/wbi_sign.dart';

/// 稍后再看 HTTP（移植自 PiliPlus `lib/http/user.dart` 的 toview 部分）。
abstract final class ToviewHttp {
  /// 拉取稍后再看列表（需 Wbi 签名）。
  ///
  /// [viewed] 0=全部，2=未看完。 [asc] false=最近添加，true=最早添加。
  static Future<LoadingState<LaterData>> toviewList({
    int page = 1,
    int viewed = 0,
    String keyword = '',
    bool asc = false,
  }) async {
    try {
      final res = await Request().get<dynamic>(
        Api.seeYouLater,
        queryParameters: await WbiSign.makSign({
          'pn': page,
          'ps': 20,
          'viewed': viewed,
          'key': keyword,
          'asc': asc,
          'need_split': true,
          'web_location': '333.881',
        }),
      );
      final data = res.data as Map<String, dynamic>;
      if (data['code'] == 0) {
        return Success(LaterData.fromJson(data['data'] as Map<String, dynamic>));
      }
      return Error(data['message']?.toString() ?? '获取稍后再看失败');
    } catch (e) {
      return Error('获取稍后再看失败：$e');
    }
  }

  /// 添加稍后再看。
  static Future<LoadingState<void>> addToview({int? aid, String? bvid}) async {
    assert(aid != null || bvid != null);
    try {
      final res = await Request().post<dynamic>(
        Api.toViewLater,
        data: {
          if (aid != null) 'aid': aid,
          if (bvid != null) 'bvid': bvid,
          'csrf': Accounts.main.csrf,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final data = res.data as Map<String, dynamic>;
      if (data['code'] == 0) return const Success(null);
      return Error(data['message']?.toString() ?? '添加失败');
    } catch (e) {
      return Error('添加失败：$e');
    }
  }

  /// 移除稍后再看（[aids] 逗号分隔的 aid）。
  static Future<LoadingState<void>> delToview(String aids) async {
    try {
      final res = await Request().post<dynamic>(
        Api.toViewDel,
        data: {'csrf': Accounts.main.csrf, 'resources': aids},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final data = res.data as Map<String, dynamic>;
      if (data['code'] == 0) return const Success(null);
      return Error(data['message']?.toString() ?? '移除失败');
    } catch (e) {
      return Error('移除失败：$e');
    }
  }

  /// 清空稍后再看（[cleanType] null=全部，1=失效，2=已看）。
  static Future<LoadingState<void>> clearToview([int? cleanType]) async {
    try {
      final res = await Request().post<dynamic>(
        Api.toViewClear,
        data: {
          if (cleanType != null) 'clean_type': cleanType,
          'csrf': Accounts.main.csrf,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final data = res.data as Map<String, dynamic>;
      if (data['code'] == 0) return const Success(null);
      return Error(data['message']?.toString() ?? '清空失败');
    } catch (e) {
      return Error('清空失败：$e');
    }
  }
}
