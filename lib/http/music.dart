import 'package:dio/dio.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/http/api.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/utils/wbi_sign.dart';

/// 音乐/BGM HTTP（移植自 PiliPlus `lib/http/music.dart`）。
///
/// 返回原始 JSON Map/List，不引入 PiliPlus 的 MusicDetail/BgmRecommend 模型。
abstract final class MusicHttp {
  /// BGM 详情。
  static Future<LoadingState<Map<String, dynamic>>> bgmDetail(
    String musicId,
  ) async {
    final res = await Request().get(
      Api.bgmDetail,
      queryParameters: await WbiSign.makSign({
        'music_id': musicId,
        'relation_from': 'bgm_page',
      }),
    );
    if (res.data['code'] == 0) {
      return Success(
        (res.data['data'] as Map?)?.cast<String, dynamic>() ?? {},
      );
    } else {
      return Error(res.data['message']?.toString() ?? '');
    }
  }

  /// 点赞/取消点赞 BGM。
  static Future<LoadingState<void>> wishUpdate(
    String musicId,
    bool hasLike,
  ) async {
    final res = await Request().post(
      Api.wishUpdate,
      data: {
        'music_id': musicId,
        'state': hasLike ? 2 : 1,
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

  /// BGM 推荐。
  static Future<LoadingState<List<Map<String, dynamic>>?>> bgmRecommend(
    String musicId,
  ) async {
    final res = await Request().get(
      Api.bgmRecommend,
      queryParameters: {
        'music_id': musicId,
      },
    );
    if (res.data['code'] == 0) {
      final list = res.data['data']?['list'];
      return Success(
        list is List
            ? list
                .map((i) => i is Map ? i.cast<String, dynamic>() : <String, dynamic>{})
                .toList()
            : null,
      );
    } else {
      return Error(res.data['message']?.toString() ?? '');
    }
  }
}
