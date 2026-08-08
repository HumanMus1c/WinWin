import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/http/api.dart';
import 'package:winwin/http/constants.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/utils/wbi_sign.dart';

/// 消息中心 HTTP（移植自 PiliPlus `lib/http/msg.dart`）。
///
/// 覆盖：回复我/艾特我/点赞我/系统通知/未读数/上传图片/上传BFS/
/// 发动态/删动态/删消息/置顶会话/标记已读/消息免打扰/私信用户信息/会话设置/举报。
///
/// 返回原始 JSON，不引入 PiliPlus 的 MsgReplyData/MsgAtData 等模型。
abstract final class MsgHttp {
  /// 回复我的消息。
  static Future<LoadingState<Map<String, dynamic>>> msgFeedReplyMe({
    int? cursor,
    int? cursorTime,
  }) async {
    final res = await Request().get(
      Api.msgFeedReply,
      queryParameters: {
        if (cursor != null) 'id': cursor,
        if (cursorTime != null) 'reply_time': cursorTime,
        'platform': 'web',
        'mobi_app': 'web',
        'build': 0,
        'web_location': 333.40164,
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

  /// 艾特我的消息。
  static Future<LoadingState<Map<String, dynamic>>> msgFeedAtMe({
    int? cursor,
    int? cursorTime,
  }) async {
    final res = await Request().get(
      Api.msgFeedAt,
      queryParameters: {
        if (cursor != null) 'id': cursor,
        if (cursorTime != null) 'at_time': cursorTime,
        'platform': 'web',
        'mobi_app': 'web',
        'build': 0,
        'web_location': 333.40164,
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

  /// 点赞我的消息。
  static Future<LoadingState<Map<String, dynamic>>> msgFeedLikeMe({
    int? cursor,
    int? cursorTime,
  }) async {
    final res = await Request().get(
      Api.msgFeedLike,
      queryParameters: {
        if (cursor != null) 'id': cursor,
        if (cursorTime != null) 'like_time': cursorTime,
        'platform': 'web',
        'mobi_app': 'web',
        'build': 0,
        'web_location': 333.40164,
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

  /// 点赞详情（单条点赞卡片内的用户列表）。
  static Future<LoadingState<Map<String, dynamic>>> msgLikeDetail({
    required Object cardId,
    required int pn,
    Object lastMid = 0,
  }) async {
    final res = await Request().get(
      Api.msgLikeDetail,
      queryParameters: {
        'card_id': cardId,
        'pn': pn,
        'last_mid': lastMid,
        'platform': 'web',
        'build': 0,
        'mobi_app': 'web',
        'web_location': 333.40164,
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

  /// 系统通知列表。
  static Future<LoadingState<List<Map<String, dynamic>>?>> msgFeedNotify({
    int? cursor,
    int pageSize = 20,
  }) async {
    final res = await Request().get(
      Api.msgSysNotify,
      queryParameters: {
        if (cursor != null) 'cursor': cursor,
        'page_size': pageSize,
        'mobi_app': 'web',
        'build': 0,
        'web_location': 333.40164,
      },
    );
    if (res.data['code'] == 0) {
      final data = res.data['data'];
      return Success(
        data is List
            ? data
                .map((e) => e is Map ? e.cast<String, dynamic>() : <String, dynamic>{})
                .toList()
            : null,
      );
    } else {
      return Error(res.data['message']?.toString() ?? '');
    }
  }

  /// 系统消息光标更新（标记已读）。
  static Future<LoadingState<void>> msgSysUpdateCursor(int cursor) async {
    final res = await Request().get(
      Api.msgSysUpdateCursor,
      queryParameters: {
        'csrf': Accounts.main.csrf,
        'cursor': cursor,
      },
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']?.toString() ?? '');
    }
  }

  /// 上传图片（消息/动态附图）。
  static Future<LoadingState<Map<String, dynamic>>> uploadImage({
    required dynamic path,
    required String bucket,
    required String dir,
  }) async {
    final res = await Request().post(
      Api.uploadImage,
      data: FormData.fromMap({
        'bucket': bucket,
        'file': await MultipartFile.fromFile(path),
        'dir': dir,
        'csrf': Accounts.main.csrf,
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

  /// 上传图片到 BFS（动态专用）。
  static Future<LoadingState<Map<String, dynamic>>> uploadBfs({
    required String path,
    String? category,
    String? biz,
    CancelToken? cancelToken,
  }) async {
    final res = await Request().post(
      Api.uploadBfs,
      data: FormData.fromMap({
        'file_up': await MultipartFile.fromFile(path),
        if (category != null) 'category': category,
        if (biz != null) 'biz': biz,
        'csrf': Accounts.main.csrf,
      }),
      cancelToken: cancelToken,
    );
    if (res.data['code'] == 0) {
      return Success(
        (res.data['data'] as Map?)?.cast<String, dynamic>() ?? {},
      );
    } else {
      return Error(res.data['message']?.toString() ?? '');
    }
  }

  /// 发布纯文本动态。
  static Future<LoadingState<void>> createTextDynamic(Object content) async {
    final csrf = Accounts.main.csrf;
    final data = await WbiSign.makSign({
      'dynamic_id': 0,
      'type': 4,
      'rid': 0,
      'content': content,
      'csrf_token': csrf,
      'csrf': csrf,
    });
    final res = await Request().post(
      '${HttpString.tUrl}${Api.createTextDynamic}',
      data: data,
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']?.toString() ?? '');
    }
  }

  /// 删除动态。
  static Future<LoadingState<void>> removeDynamic({
    required Object dynIdStr,
    Object? dynType,
    Object? ridStr,
  }) async {
    final res = await Request().post(
      Api.removeDynamic,
      queryParameters: {
        'platform': 'web',
        'csrf': Accounts.main.csrf,
      },
      data: {
        'dyn_id_str': dynIdStr,
        if (dynType != null) 'dyn_type': dynType,
        if (ridStr != null) 'rid_str': ridStr,
      },
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']?.toString() ?? '');
    }
  }

  /// 删除私信会话。
  static Future<LoadingState<void>> removeMsg(Object talkerId) async {
    final csrf = Accounts.main.csrf;
    final data = await WbiSign.makSign({
      'talker_id': talkerId,
      'session_type': 1,
      'build': 0,
      'mobi_app': 'web',
      'csrf_token': csrf,
      'csrf': csrf,
    });
    final res = await Request().post(
      '${HttpString.tUrl}${Api.removeMsg}',
      data: data,
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']?.toString() ?? '');
    }
  }

  /// 删除消息流项（回复/艾特/点赞）。
  static Future<LoadingState<void>> delMsgfeed(int tp, dynamic id) async {
    final csrf = Accounts.main.csrf;
    final res = await Request().post(
      Api.delMsgfeed,
      data: {
        'tp': tp,
        'id': id,
        'build': 0,
        'mobi_app': 'web',
        'csrf_token': csrf,
        'csrf': csrf,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']?.toString() ?? '');
    }
  }

  /// 删除系统消息。
  static Future<LoadingState<void>> delSysMsg(Object id) async {
    final csrf = Accounts.main.csrf;
    final res = await Request().post(
      '${HttpString.messageBaseUrl}${Api.delSysMsg}',
      queryParameters: {
        'mobi_app': 'android',
        'csrf': csrf,
      },
      data: {
        'csrf': csrf,
        'ids': [id],
        'station_ids': [],
        'type': 4,
        'mobi_app': 'android',
      },
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']?.toString() ?? '');
    }
  }

  /// 置顶/取消置顶会话。
  static Future<LoadingState<void>> setTop({
    required Object talkerId,
    required int opType,
  }) async {
    final csrf = Accounts.main.csrf;
    final data = await WbiSign.makSign({
      'talker_id': talkerId,
      'session_type': 1,
      'op_type': opType,
      'build': 0,
      'mobi_app': 'web',
      'csrf_token': csrf,
      'csrf': csrf,
    });
    final res = await Request().post(
      '${HttpString.tUrl}${Api.setTop}',
      data: data,
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']?.toString() ?? '');
    }
  }

  /// 标记会话消息已读。
  static Future<LoadingState<void>> ackSessionMsg({
    required int talkerId,
    required int ackSeqno,
  }) async {
    final csrf = Accounts.main.csrf;
    final params = await WbiSign.makSign({
      'talker_id': talkerId,
      'session_type': 1,
      'ack_seqno': ackSeqno,
      'build': 0,
      'mobi_app': 'web',
      'csrf_token': csrf,
      'csrf': csrf,
    });
    final res = await Request().get(Api.ackSessionMsg, queryParameters: params);
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(
        'message: ${res.data['message']},'
        ' msg: ${res.data['msg']},'
        ' code: ${res.data['code']}',
      );
    }
  }

  /// 设置消息通知状态。
  static Future<LoadingState<void>> msgSetNotice({
    required Object id,
    required int noticeState,
  }) async {
    final csrf = Accounts.main.csrf;
    final res = await Request().post(
      Api.msgSetNotice,
      data: {
        'mobi_app': 'web',
        'platform': 'web',
        'tp': 0,
        'id': id,
        'notice_state': noticeState,
        'build': 0,
        'csrf_token': csrf,
        'csrf': csrf,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']?.toString() ?? '');
    }
  }

  /// 设置消息免打扰。
  static Future<LoadingState<void>> setMsgDnd({
    required Object uid,
    required int setting,
    required Object dndUid,
  }) async {
    final csrf = Accounts.main.csrf;
    final res = await Request().post(
      Api.setMsgDnd,
      data: {
        'uid': uid,
        'setting': setting,
        'dnd_uid': dndUid,
        'build': 0,
        'mobi_app': 'web',
        'csrf_token': csrf,
        'csrf': csrf,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']?.toString() ?? '');
    }
  }

  /// 设置推送会话。
  static Future<LoadingState<void>> setPushSs({
    required int setting,
    required Object talkerUid,
  }) async {
    final csrf = Accounts.main.csrf;
    final res = await Request().post(
      Api.setPushSs,
      data: {
        'setting': setting,
        'talker_uid': talkerUid,
        'build': 0,
        'mobi_app': 'web',
        'csrf_token': csrf,
        'csrf': csrf,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']?.toString() ?? '');
    }
  }

  /// 私信用户信息。
  static Future<LoadingState<List<Map<String, dynamic>>?>> imUserInfos({
    required String uids,
  }) async {
    final csrf = Accounts.main.csrf;
    final res = await Request().get(
      Api.imUserInfos,
      queryParameters: {
        'uids': uids,
        'build': 0,
        'mobi_app': 'web',
        'csrf_token': csrf,
        'csrf': csrf,
      },
    );
    if (res.data['code'] == 0) {
      final data = res.data['data'];
      return Success(
        data is List
            ? data
                .map((e) => e is Map ? e.cast<String, dynamic>() : <String, dynamic>{})
                .toList()
            : null,
      );
    } else {
      return Error(res.data['message']?.toString() ?? '');
    }
  }

  /// 获取会话设置。
  static Future<LoadingState<Map<String, dynamic>>> getSessionSs({
    required Object talkerUid,
  }) async {
    final csrf = Accounts.main.csrf;
    final res = await Request().get(
      Api.getSessionSs,
      queryParameters: {
        'talker_uid': talkerUid,
        'build': 0,
        'mobi_app': 'web',
        'csrf_token': csrf,
        'csrf': csrf,
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

  /// 获取消息免打扰列表。
  static Future<LoadingState<List<Map<String, dynamic>>?>> getMsgDnd({
    required Object uidsStr,
  }) async {
    final csrf = Accounts.main.csrf;
    final res = await Request().get(
      Api.getMsgDnd,
      queryParameters: {
        'own_uid': Accounts.main.mid,
        'uids_str': uidsStr,
        'build': 0,
        'mobi_app': 'web',
        'csrf_token': csrf,
        'csrf': csrf,
      },
    );
    if (res.data['code'] == 0) {
      final data = res.data['data']?['uid_settings'];
      return Success(
        data is List
            ? data
                .map((e) => e is Map ? e.cast<String, dynamic>() : <String, dynamic>{})
                .toList()
            : null,
      );
    } else {
      return Error(res.data['message']?.toString() ?? '');
    }
  }

  /// 未读消息数（私信）。
  static Future<LoadingState<Map<String, dynamic>>> msgUnread() async {
    final res = await Request().get(
      Api.msgUnread,
      queryParameters: {
        'build': 0,
        'mobi_app': 'web',
        'unread_type': 0,
        'web_location': 333.1365,
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

  /// 消息中心未读信息。
  static Future<LoadingState<Map<String, dynamic>>> msgFeedUnread() async {
    final res = await Request().get(
      Api.msgFeedUnread,
      queryParameters: {
        'build': 0,
        'mobi_app': 'web',
        'web_location': 333.1365,
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

  /// 举报私信。
  static Future<LoadingState<void>> imMsgReport({
    required int accusedUid,
    required int reasonType,
    required String reasonDesc,
    required Map comment,
    required Map extra,
  }) async {
    final res = await Request().post(
      Api.imMsgReport,
      data: {
        'biz_code': 4,
        'accused_uid': accusedUid,
        'object_id': accusedUid,
        'reason_type': reasonType,
        'reason_desc': reasonDesc,
        'module': 604,
        'comment': jsonEncode(comment),
        'extra': jsonEncode(extra),
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
}
