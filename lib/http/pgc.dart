import 'package:dio/dio.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/http/api.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/http/loading_state.dart';

/// 番剧 HTTP（移植自 PiliPlus `lib/http/pgc.dart`）。
///
/// 包含：索引结果、索引条件、时间线、长评/短评列表、点赞/踩/发布/修改/删除、季状态。
/// 返回原始 JSON，不引入 PiliPlus 的 PgcIndexResult/PgcReviewData 等模型。
abstract final class PgcHttp {
  /// 番剧索引结果（分页）。
  static Future<LoadingState<Map<String, dynamic>>> pgcIndexResult({
    required int page,
    required Map<String, dynamic> params,
    Object? seasonType,
    Object? type,
    Object? indexType,
  }) async {
    final res = await Request().get(
      Api.pgcIndexResult,
      queryParameters: {
        ...params,
        if (seasonType != null) 'season_type': seasonType,
        if (type != null) 'type': type,
        if (indexType != null) 'index_type': indexType,
        'page': page,
        'pagesize': 21,
      },
    );
    if (res.data['code'] == 0) {
      return Success(
        (res.data['data'] as Map?)?.cast<String, dynamic>() ?? {},
      );
    } else {
      return Error(res.data['message']?.toString() ?? '');
    }
  }

  /// 番剧索引筛选条件。
  static Future<LoadingState<Map<String, dynamic>>> pgcIndexCondition({
    Object? seasonType,
    required Object type,
    Object? indexType,
  }) async {
    final res = await Request().get(
      Api.pgcIndexCondition,
      queryParameters: {
        if (seasonType != null) 'season_type': seasonType,
        'type': type,
        if (indexType != null) 'index_type': indexType,
      },
    );
    if (res.data['code'] == 0) {
      return Success(
        (res.data['data'] as Map?)?.cast<String, dynamic>() ?? {},
      );
    } else {
      return Error(res.data['message']?.toString() ?? '');
    }
  }

  /// 番剧索引（快捷查询，固定参数）。
  static Future<LoadingState<List<Map<String, dynamic>>?>> pgcIndex({
    int? page,
    int? indexType,
  }) async {
    final res = await Request().get(
      Api.pgcIndexResult,
      queryParameters: {
        'st': 1,
        'order': 3,
        'season_version': -1,
        'spoken_language_type': -1,
        'area': -1,
        'is_finish': -1,
        'copyright': -1,
        'season_status': -1,
        'season_month': -1,
        'year': -1,
        'style_id': -1,
        'sort': 0,
        'season_type': 1,
        'pagesize': 20,
        'type': 1,
        'page': page,
        if (indexType != null) 'index_type': indexType,
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

  /// 番剧时间线。
  ///
  /// [types]: 1=番剧，3=电影，4=国创。
  static Future<LoadingState<List<Map<String, dynamic>>?>> pgcTimeline({
    int types = 1,
    required int before,
    required int after,
  }) async {
    final res = await Request().get(
      Api.pgcTimeline,
      queryParameters: {
        'types': types,
        'before': before,
        'after': after,
      },
    );
    if (res.data['code'] == 0) {
      final result = res.data['result'];
      return Success(
        result is List
            ? result
                .map((i) => i is Map ? i.cast<String, dynamic>() : <String, dynamic>{})
                .toList()
            : null,
      );
    } else {
      return Error(res.data['message']?.toString() ?? '');
    }
  }

  /// 番剧评论（长评/短评列表）。
  ///
  /// [typeApi]: Api.pgcReviewL（长评）或 Api.pgcReviewS（短评）。
  static Future<LoadingState<Map<String, dynamic>>> pgcReview({
    required String typeApi,
    required Object mediaId,
    int sort = 0,
    String? next,
  }) async {
    final res = await Request().get(
      typeApi,
      queryParameters: {
        'media_id': mediaId,
        'ps': 20,
        'sort': sort,
        if (next != null) 'cursor': next,
        'web_location': 666.19,
      },
    );
    if (res.data['code'] == 0) {
      return Success(
        (res.data['data'] as Map?)?.cast<String, dynamic>() ?? {},
      );
    } else {
      return Error(res.data['message']?.toString() ?? '');
    }
  }

  /// 点赞番剧评论。
  static Future<LoadingState<void>> pgcReviewLike({
    required Object mediaId,
    required Object reviewId,
  }) async {
    final res = await Request().post(
      Api.pgcReviewLike,
      data: {
        'media_id': mediaId,
        'review_type': 2,
        'review_id': reviewId,
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

  /// 踩番剧评论。
  static Future<LoadingState<void>> pgcReviewDislike({
    required Object mediaId,
    required Object reviewId,
  }) async {
    final res = await Request().post(
      Api.pgcReviewDislike,
      data: {
        'media_id': mediaId,
        'review_type': 2,
        'review_id': reviewId,
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

  /// 发布番剧短评。
  static Future<LoadingState<void>> pgcReviewPost({
    required Object mediaId,
    required int score,
    required String content,
    bool shareFeed = false,
  }) async {
    final res = await Request().post(
      Api.pgcReviewPost,
      data: {
        'media_id': mediaId,
        'score': score,
        'content': content,
        if (shareFeed) 'share_feed': 1,
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

  /// 修改番剧短评。
  static Future<LoadingState<void>> pgcReviewMod({
    required Object mediaId,
    required int score,
    required String content,
    required Object reviewId,
  }) async {
    final res = await Request().post(
      Api.pgcReviewMod,
      data: {
        'media_id': mediaId,
        'score': score,
        'content': content,
        'review_id': reviewId,
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

  /// 删除番剧短评。
  static Future<LoadingState<void>> pgcReviewDel({
    required Object mediaId,
    required Object reviewId,
  }) async {
    final res = await Request().post(
      Api.pgcReviewDel,
      data: {
        'media_id': mediaId,
        'review_id': reviewId,
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

  /// 季状态（追番/投币/收藏状态）。
  static Future<LoadingState<Map<String, dynamic>>> seasonStatus(
    Object seasonId,
  ) async {
    final res = await Request().get(
      Api.seasonStatus,
      queryParameters: {'season_id': seasonId},
    );
    if (res.data['code'] == 0) {
      return Success(
        (res.data['result'] as Map?)?.cast<String, dynamic>() ?? {},
      );
    } else {
      return Error(res.data['message']?.toString() ?? '');
    }
  }
}
