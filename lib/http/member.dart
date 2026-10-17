import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import 'package:winwin/theme/app_colors.dart';
import 'package:winwin/common/constants.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/core/log/app_logger.dart';
import 'package:winwin/http/api.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/utils/duration_utils.dart';

/// 投稿视频排序类型。
enum ArchiveOrderType {
  pubdate('最新发布'),
  click('最多播放');

  final String label;
  const ArchiveOrderType(this.label);
}

/// 用户空间相关 HTTP（移植与对齐 PiliPlus `lib/http/member.dart` 与 BiliPai）。
abstract final class MemberHttp {
  /// 安全解析响应体为 JSON Map。
  ///
  /// B站接口在风控 / 限流 / 接口异常时可能返回**非 JSON** 响应体（HTML 错误页、空体、
  /// `text/plain` 字符串）；此时裸 `res.data as Map<String, dynamic>` 会抛
  /// `type 'String' is not a subtype of type 'Map<String, dynamic>' in type cast`
  /// （2026-10-16/17 `MemberSpace: topPhoto` 实测）。本方法统一降级：
  /// - `Map` → 直接返回；
  /// - `String` → 尝试 `jsonDecode`（兼容 content-type 未标 JSON 的 JSON 文本）；
  /// - 其余（含解析失败）→ 返回**空 Map**，交由各调用点既有的 `code != 0` 分支
  ///   给出友好错误，避免裸 cast 崩溃。
  @visibleForTesting
  static Map<String, dynamic> asJsonMap(dynamic body) {
    if (body is Map<String, dynamic>) return body;
    if (body is Map) return Map<String, dynamic>.from(body);
    if (body is String && body.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        // 非 JSON 文本（如风控 HTML），走下方降级。
      }
    }
    AppLogger.w(
      'MemberHttp',
      '响应体非 JSON Map（runtimeType=${body.runtimeType}），按接口失败处理',
    );
    return const <String, dynamic>{};
  }

  /// 用户空间信息（APP 端 `/x/v2/space` 与 Web 端 `/x/web-interface/card` 双通道容灾）。
  ///
  /// 返回 [MemberSpaceData]，包含用户完整卡片（头像/名字/签名/粉丝牌/关注TA的人/等级/背景等）。
  static Future<LoadingState<MemberSpaceData>> space({required int mid}) async {
    // 1. 优先尝试 APP 端空间接口
    final params = {
      'build': 8430300,
      'version': '8.43.0',
      'c_locale': 'zh_CN',
      'channel': 'master',
      'mobi_app': 'android',
      'platform': 'android',
      's_locale': 'zh_CN',
      'statistics': Constants.statisticsApp,
      'vmid': mid,
    };
    try {
      final res = await Request().get<dynamic>(
        Api.space,
        queryParameters: params,
        options: Options(
          headers: {
            'bili-http-engine': 'cronet',
            'user-agent': Constants.userAgentApp,
          },
          sendTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
        ),
      );
      final data = asJsonMap(res.data);
      if (data['code'] == 0 && data['data'] is Map<String, dynamic>) {
        return Success(
          MemberSpaceData.fromJson(data['data'] as Map<String, dynamic>),
        );
      }
      AppLogger.w(
        'MemberHttp.space',
        'APP /x/v2/space 未成功 mid=$mid code=${data['code']} '
        'msg=${data['message']}',
      );
    } catch (e) {
      // APP 端超时或异常时无缝降级到 Web 端卡片接口
      AppLogger.w('MemberHttp.space', 'APP /x/v2/space 异常 mid=$mid: $e');
    }

    // 2. Web 端卡片接口兜底（高可用、极速）
    try {
      final res = await Request().get<dynamic>(
        Api.memberCardInfo,
        queryParameters: {'mid': mid, 'photo': true},
        options: Options(
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      final data = asJsonMap(res.data);
      if (data['code'] == 0 && data['data'] is Map<String, dynamic>) {
        return Success(
          MemberSpaceData.fromWebCard(data['data'] as Map<String, dynamic>),
        );
      } else {
        AppLogger.w(
          'MemberHttp.space',
          'Web /x/web-interface/card 未成功 mid=$mid code=${data['code']} '
          'msg=${data['message']}',
        );
        return Error(data['message']?.toString() ?? '获取空间信息失败');
      }
    } on DioException catch (e) {
      AppLogger.w(
        'MemberHttp.space',
        'Web /x/web-interface/card 网络异常 mid=$mid '
        'type=${e.type.name} msg=${e.message}',
      );
      return Error('网络请求异常：${e.message ?? e.type.name}');
    } catch (e) {
      AppLogger.w(
        'MemberHttp.space',
        'Web /x/web-interface/card 异常 mid=$mid: $e',
      );
      return Error('获取空间信息失败：$e');
    }
  }

  /// 用户投稿视频列表（APP 游标与 Web 端搜索双通道）。
  ///
  /// 支持 [order] 排序（pubdate 最新发布 / click 最多播放热门）。
  static Future<LoadingState<MemberArchiveData>> spaceArchive({
    required int mid,
    String? cursor,
    int pageNum = 1,
    ArchiveOrderType order = ArchiveOrderType.pubdate,
    int? seasonId,
    int? seriesId,
  }) async {
    // 1. 尝试 APP 游标接口
    final params = {
      'vmid': mid,
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      'order': order.name,
      'season_id': ?seasonId,
      'series_id': ?seriesId,
      'build': 8430300,
      'c_locale': 'zh_CN',
      'channel': 'master',
      'mobi_app': 'android',
      'platform': 'android',
      's_locale': 'zh_CN',
      'statistics': Constants.statisticsApp,
    };
    try {
      final res = await Request().get<dynamic>(
        Api.spaceArchive,
        queryParameters: params,
        options: Options(
          headers: {
            'bili-http-engine': 'cronet',
            'user-agent': Constants.userAgentApp,
          },
          sendTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
        ),
      );
      final data = asJsonMap(res.data);
      if (data['code'] == 0 && data['data'] is Map<String, dynamic>) {
        return Success(
          MemberArchiveData.fromJson(data['data'] as Map<String, dynamic>),
        );
      }
    } catch (_) {
      // APP 接口异常降级到 Web 搜索接口
    }

    // 2. Web 端投稿检索接口兜底
    try {
      final orderParam = switch (order) {
        ArchiveOrderType.pubdate => 'pubdate',
        ArchiveOrderType.click => 'click',
      };
      final res = await Request().get<dynamic>(
        '/x/space/arc/search',
        queryParameters: {
          'mid': mid,
          'ps': 30,
          'pn': pageNum,
          'order': orderParam,
        },
        options: Options(
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      final data = asJsonMap(res.data);
      if (data['code'] == 0 && data['data'] is Map<String, dynamic>) {
        final d = data['data'] as Map<String, dynamic>;
        final vlist = (d['list'] as Map?)?['vlist'] as List? ?? [];
        final page = d['page'] as Map<String, dynamic>? ?? {};
        final total = _asInt(page['count']) ?? vlist.length;
        final list = vlist.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          return MemberVideoItem(
            aid: _asInt(m['aid']),
            bvid: m['bvid']?.toString(),
            title: m['title']?.toString(),
            pic: m['pic']?.toString(),
            play: _asInt(m['play']),
            danmaku: _asInt(m['video_review']),
            duration: DurationUtils.parseDuration(m['length']?.toString() ?? ''),
            pubdate: _asInt(m['created']),
          );
        }).toList();
        final isEnd = (pageNum * 30) >= total;
        return Success(MemberArchiveData(list: list, isEnd: isEnd));
      } else {
        return Error(data['message']?.toString() ?? '获取投稿列表失败');
      }
    } on DioException catch (e) {
      return Error('网络请求异常：${e.message ?? e.type.name}');
    } catch (e) {
      return Error('获取投稿列表失败：$e');
    }
  }

  /// 获取 UP 主创建的合集与系列列表（Web 端 `/x/polymer/web-space/seasons_series_list`）。
  static Future<LoadingState<SpaceSsData>> seasonSeriesList({
    required int mid,
    required int pn,
    int ps = 20,
  }) async {
    try {
      final res = await Request().get<dynamic>(
        Api.seasonSeries,
        queryParameters: {
          'mid': mid,
          'page_num': pn,
          'page_size': ps,
        },
      );
      final data = asJsonMap(res.data);
      if (data['code'] == 0) {
        final itemsLists = data['data']?['items_lists'] as Map<String, dynamic>? ?? {};
        return Success(SpaceSsData.fromJson(itemsLists));
      } else {
        return Error(data['message']?.toString() ?? '获取合集与系列失败');
      }
    } on DioException catch (e) {
      return Error('网络请求异常：${e.message ?? e.type.name}');
    } catch (e) {
      return Error('获取合集与系列失败：$e');
    }
  }

  /// 获取指定合集下的视频列表（Web 端 `/x/polymer/web-space/seasons_archives_list`）。
  static Future<LoadingState<MemberArchiveData>> seasonArchives({
    required int mid,
    required int seasonId,
    required int pageNum,
    int pageSize = 30,
  }) async {
    try {
      final res = await Request().get<dynamic>(
        Api.seasonArchives,
        queryParameters: {
          'mid': mid,
          'season_id': seasonId,
          'page_num': pageNum,
          'page_size': pageSize,
        },
      );
      final data = asJsonMap(res.data);
      if (data['code'] == 0) {
        final archives = data['data']?['archives'] as List? ?? [];
        final page = data['data']?['page'] as Map<String, dynamic>? ?? {};
        final total = _asInt(page['total']) ?? 0;
        final list = archives
            .map((e) => MemberVideoItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        final isEnd = (pageNum * pageSize) >= total;
        return Success(MemberArchiveData(list: list, isEnd: isEnd));
      } else {
        return Error(data['message']?.toString() ?? '获取合集视频失败');
      }
    } on DioException catch (e) {
      return Error('网络请求异常：${e.message ?? e.type.name}');
    } catch (e) {
      return Error('获取合集视频失败：$e');
    }
  }

  /// 获取指定系列下的视频列表（Web 端 `/x/series/archives`）。
  static Future<LoadingState<MemberArchiveData>> seriesArchives({
    required int mid,
    required int seriesId,
    required int pn,
    int ps = 30,
  }) async {
    try {
      final res = await Request().get<dynamic>(
        '/x/series/archives',
        queryParameters: {
          'mid': mid,
          'series_id': seriesId,
          'pn': pn,
          'ps': ps,
        },
      );
      final data = asJsonMap(res.data);
      if (data['code'] == 0) {
        final archives = data['data']?['archives'] as List? ?? [];
        final page = data['data']?['page'] as Map<String, dynamic>? ?? {};
        final total = _asInt(page['total']) ?? 0;
        final list = archives
            .map((e) => MemberVideoItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        final isEnd = (pn * ps) >= total;
        return Success(MemberArchiveData(list: list, isEnd: isEnd));
      } else {
        return Error(data['message']?.toString() ?? '获取系列视频失败');
      }
    } on DioException catch (e) {
      return Error('网络请求异常：${e.message ?? e.type.name}');
    } catch (e) {
      return Error('获取系列视频失败：$e');
    }
  }

  /// 获取用户详细卡片信息（Web 端 `/x/web-interface/card`），包含详细经验值。
  static Future<LoadingState<MemberCardInfoData>> memberCardInfo({
    required int mid,
  }) async {
    try {
      final res = await Request().get<dynamic>(
        Api.memberCardInfo,
        queryParameters: {
          'mid': mid,
          'photo': true,
        },
      );
      final data = asJsonMap(res.data);
      if (data['code'] == 0) {
        return Success(
          MemberCardInfoData.fromJson(data['data'] as Map<String, dynamic>? ?? {}),
        );
      } else {
        return Error(data['message']?.toString() ?? '获取用户详细卡片失败');
      }
    } on DioException catch (e) {
      return Error('网络请求异常：${e.message ?? e.type.name}');
    } catch (e) {
      return Error('获取用户详细卡片失败：$e');
    }
  }

  /// 获取用户空间顶部背景图（Web 端 `/x/space/top/photo`）。
  static Future<LoadingState<MemberImages>> topPhoto({required int mid}) async {
    try {
      final res = await Request().get<dynamic>(
        '/x/space/top/photo',
        queryParameters: {'mid': mid},
      );
      final data = asJsonMap(res.data);
      if (data['code'] == 0 && data['data'] is Map<String, dynamic>) {
        return Success(MemberImages.fromJson(data['data'] as Map<String, dynamic>));
      } else {
        return Error(data['message']?.toString() ?? '获取背景图失败');
      }
    } on DioException catch (e) {
      return Error('网络请求异常：${e.message ?? e.type.name}');
    } catch (e) {
      return Error('获取背景图失败：$e');
    }
  }

  /// 获取用户空间导航数量与公开板块统计（Web 端 `/x/space/navnum`）。
  static Future<LoadingState<SpaceNavNumData>> spaceNavNum({required int mid}) async {
    try {
      final res = await Request().get<dynamic>(
        '/x/space/navnum',
        queryParameters: {'mid': mid},
      );
      final data = asJsonMap(res.data);
      if (data['code'] == 0 && data['data'] is Map<String, dynamic>) {
        return Success(SpaceNavNumData.fromJson(data['data'] as Map<String, dynamic>));
      } else {
        return Error(data['message']?.toString() ?? '获取空间导航统计失败');
      }
    } on DioException catch (e) {
      return Error('网络请求异常：${e.message ?? e.type.name}');
    } catch (e) {
      return Error('获取空间导航统计失败：$e');
    }
  }

  /// 用户最近点赞视频列表（Web 端 `/x/space/like/video`）。
  ///
  /// 若用户隐私设置未公开，API 将返回 code 53004。
  static Future<LoadingState<List<MemberVideoItem>>> likedVideos({
    required int mid,
  }) async {
    try {
      final res = await Request().get<dynamic>(
        Api.getRecentLikeVideoApi,
        queryParameters: {'vmid': mid},
      );
      final data = asJsonMap(res.data);
      final code = data['code'];
      if (code == 0) {
        final list = (data['data']?['list'] as List?) ?? [];
        final items = list
            .map((e) => MemberVideoItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        return Success(items);
      } else if (code == 53004 || code == 53000 || code == -400) {
        return Error(data['message']?.toString() ?? '用户隐私设置未公开');
      } else {
        return Error(data['message']?.toString() ?? '获取点赞视频失败');
      }
    } on DioException catch (e) {
      return Error('网络请求异常：${e.message ?? e.type.name}');
    } catch (e) {
      return Error('获取点赞视频失败：$e');
    }
  }

  /// 用户追番 / 追剧列表（Web 端 `/x/space/bangumi/follow/list`）。
  ///
  /// - [type]: 1=追番（Anime），2=追剧（Cinema / 影视）
  static Future<LoadingState<SpaceBangumiData>> spaceBangumi({
    required int mid,
    int type = 1,
    int pn = 1,
    int ps = 30,
  }) async {
    try {
      final res = await Request().get<dynamic>(
        Api.favPgc,
        queryParameters: {
          'vmid': mid,
          'type': type,
          'pn': pn,
          'ps': ps,
        },
      );
      final data = asJsonMap(res.data);
      final code = data['code'];
      if (code == 0) {
        final d = data['data'] as Map<String, dynamic>? ?? {};
        return Success(SpaceBangumiData.fromJson(d));
      } else if (code == 53004 || code == 53000) {
        return Error(data['message']?.toString() ?? '用户隐私设置未公开');
      } else {
        return Error(data['message']?.toString() ?? '获取追番列表失败');
      }
    } on DioException catch (e) {
      return Error('网络请求异常：${e.message ?? e.type.name}');
    } catch (e) {
      return Error('获取追番列表失败：$e');
    }
  }

  /// 关系操作（关注 / 取消关注 / 特别关注 / 移除黑名单）。
  ///
  /// - [act]: 1=关注, 2=取关, 3=悄悄关注, 4=取消悄关, 5=拉黑, 6=移出黑名单
  /// - [reSrc]: 来源，默认 11 (空间)
  static Future<LoadingState<void>> relationMod({
    required int mid,
    required int act,
    int reSrc = 11,
  }) async {
    try {
      final res = await Request().post<dynamic>(
        Api.relationMod,
        data: {
          'fid': mid,
          'act': act,
          're_src': reSrc,
          'csrf': Accounts.main.csrf,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final data = asJsonMap(res.data);
      if (data['code'] == 0) {
        return const Success(null);
      } else {
        return Error(data['message']?.toString() ?? '操作失败');
      }
    } on DioException catch (e) {
      return Error('网络请求异常：${e.message ?? e.type.name}');
    } catch (e) {
      return Error('操作失败：$e');
    }
  }
}

/// 用户空间数据（`/x/v2/space` 响应 或 `/x/web-interface/card` 映射）。
class MemberSpaceData {
  final MemberCard? card;
  final MemberArchiveData? archives;
  final MemberImages? images;
  final int? silence;

  MemberSpaceData({
    this.card,
    this.archives,
    this.images,
    this.silence,
  });

  factory MemberSpaceData.fromJson(Map<String, dynamic> json) {
    final imagesJson = json['images'] is Map<String, dynamic>
        ? json['images'] as Map<String, dynamic>
        : json['space'] is Map<String, dynamic>
            ? json['space'] as Map<String, dynamic>
            : (json['card'] is Map && (json['card'] as Map)['space'] is Map<String, dynamic>)
                ? (json['card'] as Map)['space'] as Map<String, dynamic>
                : null;

    final topPhotoDirect = json['top_photo'] ??
        json['topPhoto'] ??
        (json['card'] is Map
            ? (json['card'] as Map)['top_photo'] ?? (json['card'] as Map)['space_photo']
            : null);

    return MemberSpaceData(
      card: json['card'] is Map<String, dynamic>
          ? MemberCard.fromJson(json['card'] as Map<String, dynamic>)
          : null,
      archives: json['archives'] is Map<String, dynamic>
          ? MemberArchiveData.fromJson(json['archives'] as Map<String, dynamic>)
          : null,
      images: imagesJson != null
          ? MemberImages.fromJson(imagesJson)
          : (topPhotoDirect != null
              ? MemberImages(topPhoto: topPhotoDirect.toString(), imgUrl: topPhotoDirect.toString())
              : null),
      silence: _asInt(json['silence']),
    );
  }

  /// 从 Web 端 `/x/web-interface/card` 构建 [MemberSpaceData]。
  factory MemberSpaceData.fromWebCard(Map<String, dynamic> json) {
    final cardMap = json['card'] as Map<String, dynamic>? ?? {};
    final spaceMap = json['space'] as Map<String, dynamic>? ??
        (cardMap['space'] as Map<String, dynamic>?);
    final likesMap = json['like_num'] != null ? {'like_num': json['like_num']} : null;

    return MemberSpaceData(
      card: MemberCard(
        mid: _asInt(cardMap['mid']),
        name: cardMap['name']?.toString(),
        face: cardMap['face']?.toString(),
        sign: cardMap['sign']?.toString(),
        level: _asInt((cardMap['level_info'] as Map?)?['current_level'] ?? cardMap['level']),
        fans: _asInt(cardMap['fans'] ?? json['follower']),
        following: _asInt(cardMap['attention'] ?? cardMap['following']),
        vip: cardMap['vip'] is Map<String, dynamic>
            ? MemberVip.fromJson(cardMap['vip'] as Map<String, dynamic>)
            : null,
        officialVerify: cardMap['official_verify'] is Map<String, dynamic>
            ? MemberOfficial.fromJson(cardMap['official_verify'] as Map<String, dynamic>)
            : null,
        levelInfo: cardMap['level_info'] is Map<String, dynamic>
            ? MemberLevelInfo.fromJson(cardMap['level_info'] as Map<String, dynamic>)
            : null,
        pendant: cardMap['pendant'] is Map<String, dynamic>
            ? MemberPendant.fromJson(cardMap['pendant'] as Map<String, dynamic>)
            : null,
        likes: likesMap != null ? MemberLikes.fromJson(likesMap) : null,
        relation: _asInt((cardMap['relation'] as Map?)?['status'] ?? cardMap['relation']),
        silence: _asInt(cardMap['silence']),
      ),
      archives: null,
      images: spaceMap != null ? MemberImages.fromJson(spaceMap) : null,
      silence: _asInt(cardMap['silence']),
    );
  }
}

/// 空间各板块统计数据（`/x/space/navnum` 响应）。
class SpaceNavNumData {
  final int video;
  final int bangumi;
  final int cinema;
  final int favourite;
  final int like;
  final int channel;

  SpaceNavNumData({
    this.video = 0,
    this.bangumi = 0,
    this.cinema = 0,
    this.favourite = 0,
    this.like = 0,
    this.channel = 0,
  });

  factory SpaceNavNumData.fromJson(Map<String, dynamic> json) {
    final fav = json['favourite'];
    int favCount = 0;
    if (fav is Map) {
      favCount = _asInt(fav['master']) ?? 0;
    } else if (fav is int) {
      favCount = fav;
    }
    return SpaceNavNumData(
      video: _asInt(json['video']) ?? 0,
      bangumi: _asInt(json['bangumi']) ?? 0,
      cinema: _asInt(json['cinema']) ?? 0,
      favourite: favCount,
      like: _asInt(json['like']) ?? 0,
      channel: _asInt((json['channel'] as Map?)?['master']) ?? _asInt(json['channel']) ?? 0,
    );
  }
}

/// 用户追番/追剧列表数据。
class SpaceBangumiData {
  final List<SpaceBangumiItem> list;
  final int total;
  final int pn;
  final int ps;

  SpaceBangumiData({
    this.list = const [],
    this.total = 0,
    this.pn = 1,
    this.ps = 30,
  });

  bool get isEnd => (pn * ps) >= total;

  factory SpaceBangumiData.fromJson(Map<String, dynamic> json) {
    final rawList = json['list'] as List? ?? [];
    final list = rawList
        .map((e) => SpaceBangumiItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return SpaceBangumiData(
      list: list,
      total: _asInt(json['total']) ?? list.length,
      pn: _asInt(json['pn']) ?? 1,
      ps: _asInt(json['ps']) ?? 30,
    );
  }
}

/// 追番 / 追剧单个卡片模型。
class SpaceBangumiItem {
  final int? seasonId;
  final int? mediaId;
  final String? title;
  final String? cover;
  final String? badge;
  final String? progress;
  final String? indexShow;
  final int? totalCount;
  final int? follow;
  final int? view;

  SpaceBangumiItem({
    this.seasonId,
    this.mediaId,
    this.title,
    this.cover,
    this.badge,
    this.progress,
    this.indexShow,
    this.totalCount,
    this.follow,
    this.view,
  });

  factory SpaceBangumiItem.fromJson(Map<String, dynamic> json) {
    final newEp = json['new_ep'] as Map<String, dynamic>?;
    final stat = json['stat'] as Map<String, dynamic>?;
    return SpaceBangumiItem(
      seasonId: _asInt(json['season_id']),
      mediaId: _asInt(json['media_id']),
      title: json['title']?.toString(),
      cover: json['cover']?.toString(),
      badge: json['badge']?.toString(),
      progress: json['progress']?.toString(),
      indexShow: newEp?['index_show']?.toString(),
      totalCount: _asInt(json['total_count']),
      follow: _asInt(stat?['follow']),
      view: _asInt(stat?['view']),
    );
  }
}

/// 空间背景图片。
class MemberImages {
  final String? imgUrl;
  final String? nightImgurl;
  final String? topPhoto;

  MemberImages({this.imgUrl, this.nightImgurl, this.topPhoto});

  factory MemberImages.fromJson(Map<String, dynamic> json) {
    final imgUrl = (json['imgUrl'] ??
            json['img_url'] ??
            json['l_img'] ??
            json['s_img'] ??
            json['top_photo'] ??
            json['topPhoto'])
        ?.toString();
    final nightImgurl = (json['nightImgurl'] ??
            json['night_imgurl'] ??
            json['night_img_url'])
        ?.toString();
    final topPhoto = (json['top_photo'] ??
            json['topPhoto'] ??
            json['top_photo_arc'] ??
            json['l_img'] ??
            json['s_img'] ??
            json['imgUrl'] ??
            json['img_url'])
        ?.toString();
    return MemberImages(
      imgUrl: imgUrl,
      nightImgurl: nightImgurl,
      topPhoto: topPhoto,
    );
  }
}

/// 用户卡片信息。
class MemberCard {
  final int? mid;
  final String? name;
  final String? face;
  final String? sign;
  final int? level;
  final int? fans;
  final int? following;
  final MemberVip? vip;
  final MemberOfficial? officialVerify;
  final MemberLevelInfo? levelInfo;
  final MemberLiveFansWearing? liveFansWearing;
  final MemberFollowingsFollowedUpper? followingsFollowedUpper;
  final List<MemberSpaceTag> spaceTags;
  final MemberPendant? pendant;
  final MemberLikes? likes;
  final MemberPrInfo? prInfo;
  final int? relation;
  final int? silence;

  MemberCard({
    this.mid,
    this.name,
    this.face,
    this.sign,
    this.level,
    this.fans,
    this.following,
    this.vip,
    this.officialVerify,
    this.levelInfo,
    this.liveFansWearing,
    this.followingsFollowedUpper,
    this.spaceTags = const [],
    this.pendant,
    this.likes,
    this.prInfo,
    this.relation,
    this.silence,
  });

  factory MemberCard.fromJson(Map<String, dynamic> json) {
    final rawTags = json['space_tag'] as List?;
    final tagList = <MemberSpaceTag>[];
    if (rawTags != null) {
      for (final t in rawTags) {
        if (t is Map) {
          tagList.add(MemberSpaceTag.fromJson(Map<String, dynamic>.from(t)));
        }
      }
    }

    return MemberCard(
      mid: _asInt(json['mid']),
      name: json['name'] as String?,
      face: json['face'] as String?,
      sign: json['sign'] as String?,
      level: _asInt(json['level']),
      fans: _asInt(json['fans']),
      following: _asInt(json['attention'] ?? json['following']),
      vip: json['vip'] is Map<String, dynamic>
          ? MemberVip.fromJson(json['vip'] as Map<String, dynamic>)
          : null,
      officialVerify: json['official_verify'] is Map<String, dynamic>
          ? MemberOfficial.fromJson(json['official_verify'] as Map<String, dynamic>)
          : null,
      levelInfo: json['level_info'] is Map<String, dynamic>
          ? MemberLevelInfo.fromJson(json['level_info'] as Map<String, dynamic>)
          : null,
      liveFansWearing: json['live_fans_wearing'] is Map<String, dynamic>
          ? MemberLiveFansWearing.fromJson(json['live_fans_wearing'] as Map<String, dynamic>)
          : null,
      followingsFollowedUpper: json['followings_followed_upper'] is Map<String, dynamic>
          ? MemberFollowingsFollowedUpper.fromJson(
              json['followings_followed_upper'] as Map<String, dynamic>,
            )
          : null,
      spaceTags: tagList,
      pendant: json['pendant'] is Map<String, dynamic>
          ? MemberPendant.fromJson(json['pendant'] as Map<String, dynamic>)
          : null,
      likes: json['likes'] is Map<String, dynamic>
          ? MemberLikes.fromJson(json['likes'] as Map<String, dynamic>)
          : null,
      prInfo: json['pr_info'] is Map<String, dynamic>
          ? MemberPrInfo.fromJson(json['pr_info'] as Map<String, dynamic>)
          : null,
      relation: _asInt((json['relation'] as Map?)?['status'] ?? json['relation']),
      silence: _asInt(json['silence']),
    );
  }
}

/// 会员信息。
class MemberVip {
  final int? type;
  final int? status;
  final String? labelText;

  MemberVip({this.type, this.status, this.labelText});

  factory MemberVip.fromJson(Map<String, dynamic> json) {
    final label = json['label'] as Map<String, dynamic>?;
    return MemberVip(
      type: _asInt(json['type']),
      status: _asInt(json['status']),
      labelText: label?['text']?.toString() ??
          ((_asInt(json['status']) ?? 0) > 0
              ? (_asInt(json['type']) == 2 ? '年度大会员' : '大会员')
              : null),
    );
  }

  bool get isVip => status != null && status! > 0;
  bool get isAnnualVip => isVip && type == 2;
}

/// 官方认证。
class MemberOfficial {
  /// -1=无认证，0=个人认证(黄V)，1=机构认证(蓝V)。
  final int? type;
  final String? desc;
  final String? spliceTitle;

  MemberOfficial({this.type, this.desc, this.spliceTitle});

  factory MemberOfficial.fromJson(Map<String, dynamic> json) {
    return MemberOfficial(
      type: _asInt(json['type']),
      desc: json['desc'] as String?,
      spliceTitle: json['splice_title'] as String? ?? json['title'] as String?,
    );
  }

  bool get isOfficial => type != null && type! >= 0;
}

/// 等级信息。
class MemberLevelInfo {
  final int? currentLevel;
  final int? identity; // 2 = 硬核会员 / 资深会员

  MemberLevelInfo({this.currentLevel, this.identity});

  factory MemberLevelInfo.fromJson(Map<String, dynamic> json) {
    return MemberLevelInfo(
      currentLevel: _asInt(json['current_level'] ?? json['level']),
      identity: _asInt(json['identity']),
    );
  }

  bool get isSeniorMember => identity == 2;
}

/// 佩戴的粉丝牌。
class MemberLiveFansWearing {
  final MemberFansMedalDetail? detailV2;

  MemberLiveFansWearing({this.detailV2});

  factory MemberLiveFansWearing.fromJson(Map<String, dynamic> json) {
    return MemberLiveFansWearing(
      detailV2: json['detail_v2'] is Map<String, dynamic>
          ? MemberFansMedalDetail.fromJson(json['detail_v2'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// 粉丝勋章详情。
class MemberFansMedalDetail {
  final int? uid;
  final int? level;
  final String? medalName;
  final int? medalId;
  final String? medalColor;
  final String? medalColorName;

  MemberFansMedalDetail({
    this.uid,
    this.level,
    this.medalName,
    this.medalId,
    this.medalColor,
    this.medalColorName,
  });

  factory MemberFansMedalDetail.fromJson(Map<String, dynamic> json) {
    return MemberFansMedalDetail(
      uid: _asInt(json['uid']),
      level: _asInt(json['level']),
      medalName: json['medal_name'] as String?,
      medalId: _asInt(json['medal_id']),
      medalColor: json['medal_color'] as String?,
      medalColorName: json['medal_color_name'] as String?,
    );
  }

  Color get parsedBackgroundColor => ColorUtils.parseHex(medalColor, fallback: const Color(0xFFFA7298));
  Color get parsedTextColor => ColorUtils.parseHex(medalColorName, fallback: AppColors.white);
}

/// “我关注的人也在关注”。
class MemberFollowingsFollowedUpper {
  final List<MemberFollowedUpperItem> items;
  final String? jumpUrl;

  MemberFollowingsFollowedUpper({this.items = const [], this.jumpUrl});

  factory MemberFollowingsFollowedUpper.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List?;
    final list = <MemberFollowedUpperItem>[];
    if (rawItems != null) {
      for (final e in rawItems) {
        if (e is Map) {
          list.add(MemberFollowedUpperItem.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return MemberFollowingsFollowedUpper(
      items: list,
      jumpUrl: json['jump_url'] as String?,
    );
  }
}

/// 我关注的人也在关注项。
class MemberFollowedUpperItem {
  final int? mid;
  final String? name;
  final String? face;

  MemberFollowedUpperItem({this.mid, this.name, this.face});

  factory MemberFollowedUpperItem.fromJson(Map<String, dynamic> json) {
    return MemberFollowedUpperItem(
      mid: _asInt(json['mid']),
      name: json['name'] as String?,
      face: json['face'] as String?,
    );
  }
}

/// 空间标签（IP 属地、实名认证等）。
class MemberSpaceTag {
  final String? title;
  final String? uri;
  final String? type;

  MemberSpaceTag({this.title, this.uri, this.type});

  factory MemberSpaceTag.fromJson(Map<String, dynamic> json) {
    return MemberSpaceTag(
      title: json['title'] as String?,
      uri: json['uri'] as String?,
      type: json['type'] as String?,
    );
  }
}

/// 头像框挂件。
class MemberPendant {
  final String? image;

  MemberPendant({this.image});

  factory MemberPendant.fromJson(Map<String, dynamic> json) {
    return MemberPendant(image: json['image'] as String?);
  }
}

/// 获赞数据。
class MemberLikes {
  final int? likeNum;

  MemberLikes({this.likeNum});

  factory MemberLikes.fromJson(Map<String, dynamic> json) {
    return MemberLikes(likeNum: _asInt(json['like_num'] ?? json['likes']));
  }
}

/// 宣传公示信息。
class MemberPrInfo {
  final String? content;
  final String? textColor;
  final String? bgColor;
  final String? url;
  final String? icon;

  MemberPrInfo({
    this.content,
    this.textColor,
    this.bgColor,
    this.url,
    this.icon,
  });

  factory MemberPrInfo.fromJson(Map<String, dynamic> json) {
    return MemberPrInfo(
      content: json['content'] as String?,
      textColor: json['text_color'] as String?,
      bgColor: json['bg_color'] as String?,
      url: json['url'] as String?,
      icon: json['icon'] as String?,
    );
  }
}

/// 用户卡片详细数据（`/x/web-interface/card` 响应，含经验值与空间背景）。
class MemberCardInfoData {
  final int? currentLevel;
  final int? currentMin;
  final int? currentExp;
  final int? nextExp;
  final int? archiveCount;
  final int? articleCount;
  final int? follower;
  final int? likeNum;
  final String? spaceLImg;
  final String? spaceSImg;

  MemberCardInfoData({
    this.currentLevel,
    this.currentMin,
    this.currentExp,
    this.nextExp,
    this.archiveCount,
    this.articleCount,
    this.follower,
    this.likeNum,
    this.spaceLImg,
    this.spaceSImg,
  });

  factory MemberCardInfoData.fromJson(Map<String, dynamic> json) {
    final card = json['card'] as Map<String, dynamic>?;
    final levelInfo = card?['level_info'] as Map<String, dynamic>?;
    final currentLevel = _asInt(levelInfo?['current_level']);
    final isLevel6 = currentLevel == 6;

    final space = json['space'] as Map<String, dynamic>?;
    final cardSpace = (card?['space'] is Map)
        ? (card?['space'] as Map<String, dynamic>)
        : null;
    final spaceLImg = (space?['l_img'] ??
            cardSpace?['l_img'] ??
            space?['s_img'] ??
            cardSpace?['s_img'])
        ?.toString();
    final spaceSImg = (space?['s_img'] ?? cardSpace?['s_img'])?.toString();

    return MemberCardInfoData(
      currentLevel: currentLevel,
      currentMin: _asInt(levelInfo?['current_min']),
      currentExp: _asInt(levelInfo?['current_exp']),
      nextExp: isLevel6 ? _asInt(levelInfo?['current_exp']) : _asInt(levelInfo?['next_exp']),
      archiveCount: _asInt(json['archive_count']),
      articleCount: _asInt(json['article_count']),
      follower: _asInt(json['follower']),
      likeNum: _asInt(json['like_num']),
      spaceLImg: spaceLImg,
      spaceSImg: spaceSImg,
    );
  }
}

/// 投稿视频列表数据（游标分页）。
class MemberArchiveData {
  final List<MemberVideoItem> list;
  final bool? isEnd;

  MemberArchiveData({this.list = const [], this.isEnd});

  factory MemberArchiveData.fromJson(Map<String, dynamic> json) {
    final itemJson = json['item'] as List?;
    return MemberArchiveData(
      list: itemJson
              ?.map((e) => MemberVideoItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          <MemberVideoItem>[],
      isEnd: json['is_end'] as bool?,
    );
  }
}

/// 投稿视频条目。
class MemberVideoItem {
  final int? aid;
  final String? bvid;
  final String? title;
  final String? pic;
  final int? play;
  final int? danmaku;
  final int? duration;
  final int? pubdate;
  final String? upName;

  MemberVideoItem({
    this.aid,
    this.bvid,
    this.title,
    this.pic,
    this.play,
    this.danmaku,
    this.duration,
    this.pubdate,
    this.upName,
  });

  factory MemberVideoItem.fromJson(Map<String, dynamic> json) {
    return MemberVideoItem(
      aid: _asInt(json['aid']),
      bvid: json['bvid'] as String?,
      title: json['title'] as String?,
      pic: json['cover'] as String? ?? json['pic'] as String?,
      play: _asInt(json['play']),
      danmaku: _asInt(json['danmaku']),
      duration: _asInt(json['duration']),
      pubdate: _asInt(json['pubdate']),
      upName: json['owner']?['name'] as String? ?? json['author'] as String?,
    );
  }
}

/// 合集与系列数据响应。
class SpaceSsData {
  final SpaceSsPage? page;
  final List<SpaceSsModel> seasonsList;
  final List<SpaceSsModel> seriesList;

  SpaceSsData({
    this.page,
    this.seasonsList = const [],
    this.seriesList = const [],
  });

  factory SpaceSsData.fromJson(Map<String, dynamic> json) {
    final seasons = json['seasons_list'] as List?;
    final series = json['series_list'] as List?;
    return SpaceSsData(
      page: json['page'] is Map<String, dynamic>
          ? SpaceSsPage.fromJson(json['page'] as Map<String, dynamic>)
          : null,
      seasonsList: seasons
              ?.map((e) => SpaceSsModel.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
      seriesList: series
              ?.map((e) => SpaceSsModel.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
    );
  }

  List<SpaceSsModel> get allItems => [...seasonsList, ...seriesList];
}

/// 合集/系列分页信息。
class SpaceSsPage {
  final int? pageNum;
  final int? pageSize;
  final int? total;

  SpaceSsPage({this.pageNum, this.pageSize, this.total});

  factory SpaceSsPage.fromJson(Map<String, dynamic> json) {
    return SpaceSsPage(
      pageNum: _asInt(json['page_num']),
      pageSize: _asInt(json['page_size']),
      total: _asInt(json['total']),
    );
  }
}

/// 合集/系列单项模型。
class SpaceSsModel {
  final SpaceSsMeta? meta;

  SpaceSsModel({this.meta});

  factory SpaceSsModel.fromJson(Map<String, dynamic> json) {
    return SpaceSsModel(
      meta: json['meta'] is Map<String, dynamic>
          ? SpaceSsMeta.fromJson(json['meta'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// 合集/系列元数据。
class SpaceSsMeta {
  final String? cover;
  final String? name;
  final String? description;
  final int? ptime;
  final int? total;
  final int? seasonId;
  final int? seriesId;

  SpaceSsMeta({
    this.cover,
    this.name,
    this.description,
    this.ptime,
    this.total,
    this.seasonId,
    this.seriesId,
  });

  bool get isSeason => seasonId != null && seasonId! > 0;
  bool get isSeries => seriesId != null && seriesId! > 0;

  factory SpaceSsMeta.fromJson(Map<String, dynamic> json) {
    return SpaceSsMeta(
      cover: json['cover']?.toString(),
      name: json['name']?.toString(),
      description: json['description']?.toString(),
      ptime: _asInt(json['ptime']),
      total: _asInt(json['total']),
      seasonId: _asInt(json['season_id']),
      seriesId: _asInt(json['series_id']),
    );
  }
}

/// 颜色解析工具。
abstract final class ColorUtils {
  static Color parseHex(dynamic value, {Color fallback = const Color(0xFFFA7298)}) {
    if (value == null) return fallback;
    if (value is Color) return value;
    if (value is int) {
      if (value <= 0xFFFFFF) return Color(0xFF000000 | value);
      return Color(value);
    }
    final str = value.toString().trim();
    if (str.isEmpty) return fallback;
    try {
      // 优先处理 B 站常用的 24 位无前缀十进制数字颜色（如 16740608、65535 等）
      if (!str.startsWith('#') && !str.toLowerCase().startsWith('0x')) {
        final directDecimal = int.tryParse(str);
        if (directDecimal != null) {
          if (directDecimal <= 0xFFFFFF) {
            return Color(0xFF000000 | directDecimal);
          }
          return Color(directDecimal);
        }
      }

      var hex = str.replaceAll('#', '');
      if (hex.startsWith('0x') || hex.startsWith('0X')) {
        hex = hex.substring(2);
      }
      if (hex.length == 6) {
        return Color(0xFF000000 | int.parse(hex, radix: 16));
      } else if (hex.length == 8) {
        return Color(int.parse(hex, radix: 16));
      } else if (hex.length == 3) {
        final r = hex[0];
        final g = hex[1];
        final b = hex[2];
        return Color(0xFF000000 | int.parse('$r$r$g$g$b$b', radix: 16));
      }
      final parsedInt = int.tryParse(hex);
      if (parsedInt != null) {
        return Color(0xFF000000 | (parsedInt & 0xFFFFFF));
      }
    } catch (_) {}
    return fallback;
  }
}

int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}
