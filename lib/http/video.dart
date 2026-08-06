import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:winwin/common/constants.dart';
import 'package:winwin/http/api.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/login.dart';
import 'package:winwin/models/video/play_url.dart';
import 'package:winwin/models/video/rec_video_item.dart';
import 'package:winwin/models/video/related_video.dart';
import 'package:winwin/models/video/reply_item.dart';
import 'package:winwin/models/video/video_detail.dart';
import 'package:winwin/utils/global_data.dart';
import 'package:winwin/utils/id_utils.dart';
import 'package:winwin/utils/wbi_sign.dart';

abstract final class VideoHttp {
  // 首页推荐视频 APP端
  static Future<LoadingState<List<RcmdVideoItemAppModel>>> rcmdVideoListApp({
    required int freshIdx,
  }) async {
    final params = {
      'build': 2001100,
      'c_locale': 'zh_CN',
      'channel': 'master',
      'column': 4,
      'device': 'pad',
      'device_name': 'android',
      'device_type': 0,
      'disable_rcmd': 0,
      'flush': 5,
      'fnval': 976,
      'fnver': 0,
      'force_host': 2, //使用https
      'fourk': 1,
      'guidance': 0,
      'https_url_req': 0,
      'idx': freshIdx,
      'mobi_app': 'android_hd',
      'network': 'wifi',
      'platform': 'android',
      'player_net': 1,
      'pull': freshIdx == 0 ? 'true' : 'false',
      'qn': 32,
      'recsys_mode': 0,
      's_locale': 'zh_CN',
      'splash_id': '',
      'statistics': Constants.statistics,
      'voice_balance': 0,
    };
    final res = await Request().get(
      Api.recommendListApp,
      queryParameters: params,
      options: Options(
        headers: {
          'buvid': LoginHttp.buvid,
          'fp_local':
              '1111111111111111111111111111111111111111111111111111111111111111',
          'fp_remote':
              '1111111111111111111111111111111111111111111111111111111111111111',
          'session_id': '11111111',
          'env': 'prod',
          'app-key': 'android_hd',
          'User-Agent': Constants.userAgent,
          'x-bili-trace-id': Constants.traceId,
          'x-bili-aurora-eid': '',
          'x-bili-aurora-zone': '',
          'bili-http-engine': 'cronet',
        },
      ),
    );
    if (res.data['code'] == 0) {
      List<RcmdVideoItemAppModel> list = <RcmdVideoItemAppModel>[];
      for (final i in res.data['data']['items']) {
        // 屏蔽推广和拉黑用户
        if (!const {'ad_av', 'ad_web_s'}.contains(i['card_goto']) &&
            i['ad_info'] == null &&
            (i['args'] != null &&
                !GlobalData().blackMids.contains(i['args']['up_id']))) {
          list.add(RcmdVideoItemAppModel.fromJson(i));
        }
      }
      return Success(list);
    } else {
      return Error(res.data['message']);
    }
  }

  // 首页推荐视频 WEB端
  static Future<LoadingState<List<RcmdVideoItemModel>>> rcmdVideoList({
    required int ps,
    required int freshIdx,
  }) async {
    final res = await Request().get(
      Api.recommendListWeb,
      queryParameters: await WbiSign.makSign({
        'version': 1,
        'feed_version': 'V8',
        'homepage_ver': 1,
        'ps': ps,
        'fresh_idx': freshIdx,
        'brush': freshIdx,
        'fresh_type': 4,
      }),
    );
    if (res.data['code'] == 0) {
      List<RcmdVideoItemModel> list = <RcmdVideoItemModel>[];
      for (final i in res.data['data']['item']) {
        //过滤掉live与ad，以及拉黑用户
        if (i['goto'] == 'av' &&
            (i['owner'] != null &&
                !GlobalData().blackMids.contains(i['owner']['mid']))) {
          list.add(RcmdVideoItemModel.fromJson(i));
        }
      }
      return Success(list);
    } else {
      return Error(res.data['message']);
    }
  }

  // 视频详情 标题、简介、分P等
  static Future<LoadingState<VideoDetailData>> videoIntro({
    required String bvid,
  }) async {
    final res = await Request().get(
      Api.videoIntro,
      queryParameters: {'bvid': bvid},
    );
    final data = VideoDetailResponse.fromJson(res.data);
    if (data.code == 0 && data.data != null) {
      return Success(data.data!);
    } else {
      return Error(data.message);
    }
  }

  // 视频详情页 相关视频
  static Future<LoadingState<List<RelatedVideoItem>>> relatedVideoList({
    required String bvid,
  }) async {
    final res = await Request().get(
      Api.relatedList,
      queryParameters: {'aid': IdUtils.bv2av(bvid), 'bvid': bvid},
    );
    if (res.data['code'] == 0) {
      final list = (res.data['data'] as List?)
              ?.map((i) => RelatedVideoItem.fromJson(i))
              .toList() ??
          <RelatedVideoItem>[];
      return Success(list);
    } else {
      return Error(res.data['message']);
    }
  }

  // 视频流（播放地址）
  static Future<LoadingState<PlayUrlModel>> videoUrl({
    String? bvid,
    int? avid,
    required int cid,
    int qn = 80,
  }) async {
    final params = await WbiSign.makSign({
      'avid': ?avid,
      'bvid': ?bvid,
      'cid': cid,
      'qn': qn,
      // 获取所有格式的视频（DASH）
      'fnval': 4048,
      'fourk': 1,
      'fnver': 0,
      'voice_balance': 0,
      'web_location': 1315873,
    });
    final res = await Request().get(
      Api.playUrl,
      queryParameters: params,
    );
    if (res.data['code'] == 0) {
      return Success(PlayUrlModel.fromJson(res.data['data']));
    } else {
      return Error(res.data['message']);
    }
  }

  // 评论列表 web端（pagination_str 无需 wbi 签名）
  static Future<LoadingState<ReplyMainData>> replyMain({
    required int oid,
    String? nextOffset,
  }) async {
    final res = await Request().get(
      Api.replyMain,
      queryParameters: {
        'mode': 3,
        'type': 1,
        'oid': oid,
        'ps': 20,
        'pagination_str': jsonEncode({'offset': nextOffset ?? ''}),
        'web_location': '1315873',
      },
    );
    if (res.data['code'] == 0) {
      return Success(
        ReplyMainData.fromJson(res.data['data'] ?? <String, dynamic>{}),
      );
    } else {
      return Error(res.data['message']);
    }
  }
}
