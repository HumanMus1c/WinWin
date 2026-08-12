import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:winwin/common/constants.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/http/api.dart';
import 'package:winwin/http/browser_ua.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/login.dart';
import 'package:winwin/models/video/play_info.dart';
import 'package:winwin/models/video/play_url.dart';
import 'package:winwin/models/video/rec_video_item.dart';
import 'package:winwin/models/video/related_video.dart';
import 'package:winwin/models/video/reply_item.dart';
import 'package:winwin/models/video/video_detail.dart';
import 'package:winwin/models/video/video_tag.dart';
import 'package:winwin/utils/global_data.dart';
import 'package:winwin/utils/id_utils.dart';
import 'package:winwin/utils/utils.dart';
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

  // 热门视频（移植自 PiliPlus `VideoHttp.hotVideoList`）
  // /x/web-interface/popular，页码制分页（pn/ps），返回 web 格式稿件。
  static Future<LoadingState<List<RcmdVideoItemModel>>> hotVideoList({
    required int pn,
    required int ps,
  }) async {
    final res = await Request().get(
      Api.hotList,
      queryParameters: {'pn': pn, 'ps': ps},
    );
    if (res.data['code'] == 0) {
      List<RcmdVideoItemModel> list = <RcmdVideoItemModel>[];
      for (final i in res.data['data']['list']) {
        // 屏蔽拉黑用户
        if (i['owner'] != null &&
            !GlobalData().blackMids.contains(i['owner']['mid'])) {
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
      // 透传错误码：62002 稿件不可见 / 62004 审核中 / 62012 仅UP主可见等，
      // 详情页据此在播放区域展示针对性错误（参照 BiliPai VideoLoadError.fromApiCode）。
      return Error(data.message, code: data.code);
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
    // 风控规避参数（对齐 PiliPlus）：缺少 dm_img_* / gaia 参数时，
    // playurl 会被风控拦截或降级，表现为无法切换到 480P 以上画质。
    final dmImgStr = Utils.base64EncodeRandomString(16, 64);
    final dmCoverImgStr = Utils.base64EncodeRandomString(32, 128);
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
      'gaia_source': 'pre-load',
      'isGaiaAvoided': true,
      'web_location': 1315873,
      'dm_img_list': '[]',
      'dm_img_str': dmImgStr,
      'dm_cover_img_str': dmCoverImgStr,
      'dm_img_inter': '{"ds":[],"wh":[0,0,0],"of":[0,0,0]}',
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

  /// 播放器信息（`/x/player/wbi/v2`）。
  ///
  /// 一次返回多项数据，服务多个 Phase：
  ///  - last_play_time / last_play_cid：Phase 4.2 历史进度恢复
  ///  - subtitle.subtitles：Phase 4.4 字幕列表
  ///  - view_points：Phase 4.5 章节标记
  ///
  /// [bvid] / [cid] 必填，用于定位视频。未登录也能调用（无历史进度）。
  static Future<LoadingState<PlayInfoModel>> playInfo({
    required String bvid,
    required int cid,
  }) async {
    final params = await WbiSign.makSign({
      'bvid': bvid,
      'cid': cid,
      'web_location': '1315873',
    });
    final res = await Request().get(
      Api.playInfo,
      queryParameters: params,
    );
    if (res.data['code'] == 0) {
      return Success(PlayInfoModel.fromJson(res.data['data'] ?? {}));
    } else {
      return Error(res.data['message']);
    }
  }

  /// 稿件标签列表（`/x/tag/archive/tags`，对标 BiliPai getVideoTags）。
  ///
  /// 仅需 [bvid]，无需 WBI 签名。失败返回 Error，由调用方静默降级。
  static Future<LoadingState<List<VideoTag>>> videoTags({
    required String bvid,
  }) async {
    final res = await Request().get(
      Api.videoTags,
      queryParameters: {'bvid': bvid},
    );
    if (res.data['code'] == 0) {
      final list = (res.data['data'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(VideoTag.fromJson)
          .toList();
      return Success(list);
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

  /// 楼中楼回复列表（`/x/v2/reply/reply`）。
  ///
  /// [root] 为根评论 rpid，[nextOffset] 为分页偏移。
  static Future<LoadingState<ReplyMainData>> replyReplyList({
    required int oid,
    required int root,
    String? nextOffset,
  }) async {
    final res = await Request().get(
      Api.replyReplyList,
      queryParameters: {
        'type': 1,
        'oid': oid,
        'root': root,
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

  /// 评论点赞/取消点赞（`/x/v2/reply/action`）。
  ///
  /// [action]: 1=点赞，0=取消点赞。
  /// 需要登录态（csrf）。
  static Future<LoadingState> likeReply({
    required int oid,
    required int rpid,
    required int action,
  }) async {
    final res = await Request().post(
      Api.likeReply,
      data: {
        'type': 1,
        'oid': oid,
        'rpid': rpid,
        'action': action,
        'csrf': Accounts.main.csrf,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        extra: {'account': Accounts.main},
      ),
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']);
    }
  }

  /// 发表评论（`/x/v2/reply/add`）。
  ///
  /// [root]/[parent] 为 0 或 null 时发表一级评论，否则发表二级回复。
  /// 需要登录态（csrf）。
  static Future<LoadingState<ReplyItemModel>> replyAdd({
    required int oid,
    required String message,
    int? root,
    int? parent,
  }) async {
    final data = {
      'type': 1,
      'oid': oid,
      if (root != null && root != 0) 'root': root,
      if (parent != null && parent != 0) 'parent': parent,
      'message': message,
      'csrf': Accounts.main.csrf,
    };
    final res = await Request().post(
      Api.replyAdd,
      data: data,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        extra: {'account': Accounts.main},
      ),
    );
    if (res.data['code'] == 0) {
      return Success(
        ReplyItemModel.fromJson(
          res.data['data']?['reply'] as Map<String, dynamic>? ?? {},
        ),
      );
    } else {
      return Error(res.data['message']);
    }
  }

  /// 播放心跳上报（`/x/click-interface/web/heartbeat`）。
  ///
  /// 用于向 B 站上报播放进度，支持多端历史记录同步。
  /// [aid] 稿件 avid，[cid] 分 P cid，[playType] 播放类型：
  ///   0=开始播放/心跳，1=暂停，2=继续，3=结束
  /// [progressSec] 当前播放位置（秒），经 `played_time`/`real_time`
  /// 字段下发（参照 PiliPlus heartBeat，服务端仅识别 played_time）。
  /// 未登录时不调用。
  static Future<LoadingState> heartBeat({
    required int aid,
    required int cid,
    int playType = 0,
    int? progressSec,
  }) async {
    final account = Accounts.main;
    if (!account.isLogin) return const Error('未登录');
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final res = await Request().post(
      Api.heartBeat,
      data: {
        'aid': aid,
        'cid': cid,
        'part': 1,
        'did': LoginHttp.buvid,
        's_locale': 'zh-CN',
        'csrf': account.csrf,
        if (progressSec != null) ...{
          'played_time': progressSec,
          'real_time': progressSec,
        },
        'start_ts': now,
        'play_type': playType,
        'type': 3,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        extra: {'account': account},
      ),
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']);
    }
  }

  /// 历史进度上报（`/x/v2/history/report`）。
  ///
  /// 用于在退出/切换视频时上报最终观看进度。
  /// [aid] 稿件 avid，[cid] 分 P cid，[progressSec] 当前进度（秒）。
  static Future<LoadingState> reportHistory({
    required int aid,
    required int cid,
    int? progressSec,
  }) async {
    final account = Accounts.main;
    if (!account.isLogin) return const Error('未登录');
    final res = await Request().post(
      Api.historyReport,
      data: {
        'aid': aid,
        'cid': cid,
        'progress': progressSec ?? 0,
        'csrf': account.csrf,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        extra: {'account': account},
      ),
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']);
    }
  }

  // ─────────────────── 稿件互动（对标 BiliPai VideoInteractionUseCase）───

  /// （取消）点赞（APP 端 `/x/v2/view/like`，移植自 PiliPlus）。
  ///
  /// [type] 为当前是否已点赞：已赞→传 0 取消，未赞→传 1 点赞。
  /// 返回服务端 toast 文案（可能为 null）。
  static Future<LoadingState<String?>> likeVideo({
    required int aid,
    required bool type,
  }) async {
    final account = Accounts.main;
    if (!account.isLogin) return const Error('请先登录');
    final res = await Request().post(
      Api.likeVideo,
      data: {'aid': aid.toString(), 'like': type ? '0' : '1'},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        extra: {'account': account},
      ),
    );
    if (res.data['code'] == 0) {
      return Success(res.data['data']?['toast'] as String?);
    } else {
      return Error(res.data['message']);
    }
  }

  /// （取消）点踩（APP 端 `/x/v2/view/dislike`，移植自 PiliPlus）。
  ///
  /// 仅 APP 接口支持，需要 accessKey；[type] 为当前是否已点踩。
  static Future<LoadingState<void>> dislikeVideo({
    required int aid,
    required bool type,
  }) async {
    final account = Accounts.main;
    if (!account.isLogin) return const Error('请先登录');
    if ((account.accessKey ?? '').isEmpty) {
      return const Error('请退出账号后重新登录');
    }
    final res = await Request().post(
      Api.dislikeVideo,
      data: {'aid': aid.toString(), 'dislike': type ? '0' : '1'},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        extra: {'account': account},
      ),
    );
    if (res.data is! String && res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data is String ? res.data : res.data['message']);
    }
  }

  /// 投币（APP 端 `/x/v2/view/coin/add`，移植自 PiliPlus）。
  ///
  /// [multiply] 投币数量（上限 2），[selectLike] 1=投币同时点赞。
  static Future<LoadingState<void>> coinVideo({
    required int aid,
    required int multiply,
    int selectLike = 0,
  }) async {
    final account = Accounts.main;
    if (!account.isLogin) return const Error('请先登录');
    final res = await Request().post(
      Api.coinVideo,
      data: {
        'aid': aid.toString(),
        'multiply': multiply.toString(),
        'select_like': selectLike.toString(),
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        extra: {'account': account},
      ),
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']);
    }
  }

  /// 一键三连（Web 端 `/x/web-interface/archive/like/triple`，
  /// 移植自 PiliPlus）：点赞 + 投币×2 + 收藏默认收藏夹。
  static Future<LoadingState<UgcTriple>> ugcTriple({
    required String bvid,
    required int aid,
  }) async {
    final account = Accounts.main;
    if (!account.isLogin) return const Error('请先登录');
    final res = await Request().post(
      Api.ugcTriple,
      data: {
        'aid': aid,
        'eab_x': 2,
        'ramval': 0,
        'source': 'web_normal',
        'ga': 1,
        'csrf': account.csrf,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {
          'origin': 'https://www.bilibili.com',
          'referer': 'https://www.bilibili.com/video/$bvid',
          'user-agent': BrowserUa.pc,
        },
        extra: {'account': account},
      ),
    );
    if (res.data['code'] == 0) {
      return Success(
        UgcTriple.fromJson(
          (res.data['data'] as Map?)?.cast<String, dynamic>() ?? {},
        ),
      );
    } else {
      return Error(res.data['message']);
    }
  }

  /// 分享上报（Web 端 `/x/web-interface/share/add`）。
  ///
  /// 桌面端分享 = 复制链接到剪贴板 + 向服务端上报分享计数（尽力而为）。
  static Future<LoadingState<void>> shareVideo({required int aid}) async {
    final account = Accounts.main;
    if (!account.isLogin) return const Error('未登录');
    final res = await Request().post(
      Api.shareVideo,
      data: {'aid': aid, 'csrf': account.csrf, 'web_location': '333.788'},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {
          'origin': 'https://www.bilibili.com',
          'referer': 'https://www.bilibili.com',
          'user-agent': BrowserUa.pc,
        },
        extra: {'account': account},
      ),
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']);
    }
  }
}
