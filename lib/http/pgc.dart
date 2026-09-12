import 'package:dio/dio.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/http/api.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/models/bangumi/bangumi_detail.dart';
import 'package:winwin/models/video/play_url.dart';
import 'package:winwin/utils/utils.dart';
import 'package:winwin/utils/wbi_sign.dart';

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
        'season_type': ?seasonType,
        'type': ?type,
        'index_type': ?indexType,
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
        'season_type': ?seasonType,
        'type': type,
        'index_type': ?indexType,
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
        'index_type': ?indexType,
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
        'cursor': ?next,
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

  /// 季状态（追番/投币/收藏状态，GET /pgc/view/web/season/user/status）。
  static Future<LoadingState<Map<String, dynamic>>> seasonStatus(
    Object seasonId,
  ) async {
    final res = await Request().get(
      Api.seasonStatus,
      queryParameters: {'season_id': seasonId},
      options: Options(extra: {'account': Accounts.main}),
    );
    if (res.data['code'] == 0 && res.data['result'] is Map) {
      return Success(
        Map<String, dynamic>.from(res.data['result'] as Map),
      );
    } else {
      return Error(res.data['message']?.toString() ?? '获取季状态失败');
    }
  }

  /// 获取番剧详情（/pgc/view/web/season）。
  ///
  /// 支持按 [seasonId]、[epId] 或 [mediaId] 查询，自动补充剧集分段。
  static Future<LoadingState<BangumiDetail>> pgcInfo({
    int? seasonId,
    int? epId,
    int? mediaId,
  }) async {
    try {
      int? resolvedSeasonId = seasonId;
      // 若仅传入 mediaId，先通过 pgcMediaInfo 换取 season_id
      if ((resolvedSeasonId == null || resolvedSeasonId <= 0) &&
          (epId == null || epId <= 0) &&
          mediaId != null &&
          mediaId > 0) {
        final mediaRes = await Request().get(
          Api.pgcMediaInfo,
          queryParameters: {'media_id': mediaId},
        );
        if (mediaRes.data['code'] == 0) {
          final rawSid = mediaRes.data['result']?['media']?['season_id'];
          if (rawSid is int) {
            resolvedSeasonId = rawSid;
          } else if (rawSid is num) {
            resolvedSeasonId = rawSid.toInt();
          } else if (rawSid is String) {
            resolvedSeasonId = int.tryParse(rawSid);
          }
        }
      }

      final queryParams = <String, dynamic>{};
      if (resolvedSeasonId != null && resolvedSeasonId > 0) {
        queryParams['season_id'] = resolvedSeasonId;
      }
      if (epId != null && epId > 0) {
        queryParams['ep_id'] = epId;
      }
      if (queryParams.isEmpty && mediaId != null && mediaId > 0) {
        queryParams['media_id'] = mediaId;
      }

      final res = await Request().get(
        Api.pgcInfo,
        queryParameters: queryParams,
        options: Options(extra: {'account': Accounts.main}),
      );

      if (res.data['code'] == 0 && res.data['result'] != null) {
        var detail = BangumiDetail.fromJson(
          Map<String, dynamic>.from(res.data['result'] as Map),
        );

        // 若主剧集为空，尝试通过 pgcSeasonSections 接口补充
        if (detail.episodes.isEmpty && detail.seasonId > 0) {
          final sectionRes = await pgcSeasonSections(detail.seasonId);
          if (sectionRes case Success(:final response)) {
            if (response.isNotEmpty) {
              final firstSec = response.first;
              detail = detail.copyWith(
                episodes: firstSec.episodes,
                sections: response.length > 1 ? response.sublist(1) : const [],
              );
            }
          }
        }

        // 若用户已登录，调用 seasonStatus 查询精准的追番及观看历史状态（解决 CDN 缓存缺失 user_status 问题）
        if (Accounts.main.isLogin && detail.seasonId > 0) {
          final statusRes = await seasonStatus(detail.seasonId);
          if (statusRes case Success(:final response)) {
            final follow = response['follow'] == 1 ||
                (response['follow_status'] is num && (response['follow_status'] as num) > 0);
            final followStatus = response['follow_status'] as int? ?? (follow ? 2 : 0);
            final progress = response['progress'] as Map?;
            detail = detail.copyWith(
              userStatus: BangumiUserStatus(
                follow: follow ? 1 : 0,
                followStatus: followStatus,
                pay: response['pay'] as int? ?? detail.userStatus?.pay ?? 0,
                progressLastEpId: progress?['last_ep_id'] as int?,
                progressLastTime: progress?['last_time'] as int?,
              ),
            );
          }
        }

        return Success(detail);
      } else {
        return Error(res.data['message']?.toString() ?? '获取番剧详情失败');
      }
    } catch (e, s) {
      return Error('$e\n\n$s');
    }
  }

  /// 获取剧集分段（/pgc/web/season/section）。
  static Future<LoadingState<List<BangumiSection>>> pgcSeasonSections(
    int seasonId,
  ) async {
    try {
      final res = await Request().get(
        Api.pgcSeasonSection,
        queryParameters: {'season_id': seasonId},
      );
      if (res.data['code'] == 0 && res.data['result'] != null) {
        final list = <BangumiSection>[];
        final result = res.data['result'];
        if (result is Map) {
          if (result['main_section'] is Map) {
            list.add(BangumiSection.fromJson(
              Map<String, dynamic>.from(result['main_section'] as Map),
            ));
          }
          if (result['section'] is List) {
            for (final s in result['section'] as List) {
              if (s is Map) {
                list.add(BangumiSection.fromJson(
                  Map<String, dynamic>.from(s),
                ));
              }
            }
          }
        }
        return Success(list);
      }
      return Error(res.data['message']?.toString() ?? '获取剧集分段失败');
    } catch (e, s) {
      return Error('$e\n\n$s');
    }
  }

  /// 获取番剧播放流（/pgc/player/web/v2/playurl）。
  static Future<LoadingState<PlayUrlModel>> pgcPlayUrl({
    required int cid,
    int? epId,
    int? seasonId,
    String? bvid,
    int qn = 80,
    bool? voiceBalance,
  }) async {
    final dmImgStr = Utils.base64EncodeRandomString(16, 64);
    final dmCoverImgStr = Utils.base64EncodeRandomString(32, 128);
    final isVoiceBalance = voiceBalance ?? Pref.enableAudioNormalize;
    final params = await WbiSign.makSign({
      'ep_id': ?epId,
      'season_id': ?seasonId,
      'bvid': ?bvid,
      'cid': cid,
      'qn': qn,
      'fnval': 4048,
      'fourk': 1,
      'fnver': 0,
      'voice_balance': isVoiceBalance ? 1 : 0,
      'gaia_source': 'pre-load',
      'isGaiaAvoided': true,
      'web_location': 1315873,
      'try_look': 1,
      'dm_img_list': '[]',
      'dm_img_str': dmImgStr,
      'dm_cover_img_str': dmCoverImgStr,
      'dm_img_inter': '{"ds":[],"wh":[0,0,0],"of":[0,0,0]}',
    });

    try {
      final res = await Request().get(
        Api.pgcUrl,
        queryParameters: params,
      );
      if (res.data['code'] == 0) {
        final result = res.data['result'];
        final videoInfo = result is Map ? (result['video_info'] ?? result) : null;
        if (videoInfo is Map) {
          final model = PlayUrlModel.fromJson(Map<String, dynamic>.from(videoInfo));
          return Success(model);
        }
      }
      return Error(res.data['message']?.toString() ?? '获取播放地址失败');
    } catch (e, s) {
      return Error('$e\n\n$s');
    }
  }

  /// 追番 (POST /pgc/web/follow/add)。
  static Future<LoadingState<void>> followBangumi({required int seasonId}) async {
    final res = await Request().post(
      Api.pgcAdd,
      data: {
        'season_id': seasonId,
        'csrf': Accounts.main.csrf,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']?.toString() ?? '追番失败');
    }
  }

  /// 取消追番 (POST /pgc/web/follow/del)。
  static Future<LoadingState<void>> unfollowBangumi({required int seasonId}) async {
    final res = await Request().post(
      Api.pgcDel,
      data: {
        'season_id': seasonId,
        'csrf': Accounts.main.csrf,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']?.toString() ?? '取消追番失败');
    }
  }

  /// 更新追番状态 (POST /pgc/web/follow/status/update)。
  /// [status]: 1=想看, 2=在看, 3=看过。
  static Future<LoadingState<void>> updateFollowStatus({
    required int seasonId,
    required int status,
  }) async {
    final res = await Request().post(
      Api.pgcUpdate,
      data: {
        'season_id': seasonId,
        'status': status,
        'csrf': Accounts.main.csrf,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']?.toString() ?? '更新追番状态失败');
    }
  }

  /// 查询单集社区互动状态（点赞/投币/收藏）。
  static Future<LoadingState<Map<String, dynamic>>> pgcLikeCoinFav({
    required int epId,
  }) async {
    final res = await Request().get(
      Api.pgcLikeCoinFav,
      queryParameters: {'ep_id': epId},
    );
    if (res.data['code'] == 0 && res.data['result'] is Map) {
      return Success(Map<String, dynamic>.from(res.data['result'] as Map));
    } else {
      return Error(res.data['message']?.toString() ?? '查询互动状态失败');
    }
  }

  /// 番剧一键三连 (POST /pgc/season/episode/like/triple)。
  static Future<LoadingState<void>> pgcTriple({required int epId}) async {
    final res = await Request().post(
      Api.pgcTriple,
      data: {
        'ep_id': epId,
        'csrf': Accounts.main.csrf,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']?.toString() ?? '一键三连失败');
    }
  }
}
