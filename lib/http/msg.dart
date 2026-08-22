import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
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
        'id': ?cursor,
        'reply_time': ?cursorTime,
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
        'id': ?cursor,
        'at_time': ?cursorTime,
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
        'id': ?cursor,
        'like_time': ?cursorTime,
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
        'cursor': ?cursor,
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
        'category': ?category,
        'biz': ?biz,
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
        'dyn_type': ?dynType,
        'rid_str': ?ridStr,
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

  /// 私信会话列表（get_sessions）。
  ///
  /// session_type：1=用户与系统 2=未关注 3=粉丝团 4=全部 5=拦截
  /// 7=系统 8=陌生人 9=关注。用 [endTs] 游标分页（取上页返回的 last_ts），
  /// [pn] 为辅助页码。返回原始 data（含 session_list / has_more / last_ts）。
  static Future<LoadingState<Map<String, dynamic>>> sessionList({
    int sessionType = 4,
    int size = 20,
    int pn = 1,
    int? endTs,
  }) async {
    final res = await Request().get(
      Api.sessionList,
      queryParameters: {
        'session_type': sessionType,
        'group_fold': 1,
        'unfollow_fold': 0,
        'sort_rule': 2,
        'size': size,
        'pn': pn,
        if (endTs != null && endTs > 0) 'end_ts': endTs,
        'build': 0,
        'mobi_app': 'web',
        'web_location': 333.999,
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

  /// 私信消息记录（fetch_session_msgs，聊天历史）。
  ///
  /// [endSeqno] 向上翻更早的历史，[beginSeqno] 向下翻较新的消息。
  /// 返回原始 data（含 messages / min_seqno / max_seqno / has_more 等）。
  static Future<LoadingState<Map<String, dynamic>>> sessionMsg({
    required int talkerId,
    int sessionType = 1,
    int size = 20,
    int? beginSeqno,
    int? endSeqno,
  }) async {
    final res = await Request().get(
      Api.sessionMsg,
      queryParameters: {
        'talker_id': talkerId,
        'session_type': sessionType,
        'size': size,
        'sender_device_id': 1,
        if (beginSeqno != null && beginSeqno > 0) 'begin_seqno': beginSeqno,
        if (endSeqno != null && endSeqno > 0) 'end_seqno': endSeqno,
        'build': 0,
        'mobi_app': 'web',
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

  /// 批量获取私信用户卡片（account/v1/user/cards）。
  ///
  /// 会话列表接口（get_sessions）对普通用户会话通常不返回 account_info，
  /// 消息中心网页版用本接口按 uids 批量补齐昵称与头像。
  /// 返回原始 data 数组（每项含 mid / name / face）。
  static Future<LoadingState<List<Map<String, dynamic>>>> sessionAccountCards({
    required List<int> uids,
  }) async {
    if (uids.isEmpty) return Success(const []);
    final res = await Request().get(
      Api.sessionAccountList,
      queryParameters: {
        'uids': uids.join(','),
        'build': 0,
        'mobi_app': 'web',
      },
    );
    if (res.data['code'] == 0) {
      final data = res.data['data'];
      return Success(
        data is List
            ? data
                .whereType<Map>()
                .map((e) => e.cast<String, dynamic>())
                .toList()
            : const [],
      );
    } else {
      return Error(res.data['message']?.toString() ?? '');
    }
  }

  /// 单个用户名片（x/web-interface/card），批量接口未覆盖时逐个兜底。
  ///
  /// 返回 `{name, face}`，请求失败或用户不存在时返回 Error。
  static Future<LoadingState<Map<String, dynamic>>> userCard({
    required int mid,
  }) async {
    final res = await Request().get(
      Api.memberCardInfo,
      queryParameters: {'mid': mid, 'photo': true},
    );
    if (res.data['code'] == 0) {
      final card = res.data['data']?['card'];
      if (card is Map) {
        return Success({
          'name': card['name']?.toString() ?? '',
          'face': card['face']?.toString() ?? '',
        });
      }
      return Error('');
    } else {
      return Error(res.data['message']?.toString() ?? '');
    }
  }

  /// dev_id 缓存（发送私信用，UUID v4，进程内复用）。
  static String? _devIdCache;
  static String _getDevId() => _devIdCache ??= const Uuid().v4();

  /// 发送私信（web_im/send_msg）。
  ///
  /// [content] 须为与 [msgType] 对应的 JSON 字符串：文本消息用
  /// `{"content":"..."}`（见 [sendTextMsg]），撤回用 msg_key（见 [withdrawMsg]）。
  /// 与 removeMsg/setTop 同为 vc 域写操作，做 wbi 签名。
  static Future<LoadingState<Map<String, dynamic>>> sendMsg({
    required int receiverId,
    int receiverType = 1,
    int msgType = 1,
    required String content,
  }) async {
    final csrf = Accounts.main.csrf;
    final senderUid = Accounts.main.mid;
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final data = <String, Object>{
      'msg[sender_uid]': senderUid,
      'msg[receiver_id]': receiverId,
      'msg[receiver_type]': receiverType,
      'msg[msg_type]': msgType,
      'msg[msg_status]': 0,
      'msg[content]': content,
      'msg[timestamp]': ts,
      'msg[dev_id]': _getDevId(),
      'msg[new_face_version]': 1,
      'from_firework': 0,
      'build': 0,
      'mobi_app': 'web',
      'csrf_token': csrf,
      'csrf': csrf,
    };
    final signed = await WbiSign.makSign(data);
    final res = await Request().post(
      Api.sendMsg,
      queryParameters: {
        'w_rid': signed['w_rid'],
        'wts': signed['wts'],
      },
      data: data,
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final code = (res.data['code'] as num?)?.toInt() ?? -1;
    if (code == 0) {
      return Success(
        (res.data['data'] as Map?)?.cast<String, dynamic>() ?? {},
      );
    } else {
      return Error(_sendMsgErrorMsg(code, res.data['message']?.toString() ?? ''));
    }
  }

  /// 发送文本私信（自动包装为 `{"content":"..."}`）。
  static Future<LoadingState<Map<String, dynamic>>> sendTextMsg({
    required int receiverId,
    required String text,
    int receiverType = 1,
  }) {
    return sendMsg(
      receiverId: receiverId,
      receiverType: receiverType,
      msgType: 1,
      content: jsonEncode({'content': text}),
    );
  }

  /// 撤回私信（msg_type=5，content 为 msg_key）。
  static Future<LoadingState<Map<String, dynamic>>> withdrawMsg({
    required int receiverId,
    required Object msgKey,
    int receiverType = 1,
  }) {
    return sendMsg(
      receiverId: receiverId,
      receiverType: receiverType,
      msgType: 5,
      content: '$msgKey',
    );
  }

  /// 发送私信错误码 → 中文提示（移植自 BiliPai MessageRepository）。
  static String _sendMsgErrorMsg(int code, String message) {
    return switch (code) {
      -101 => '请先登录',
      -400 => '请求参数错误',
      21007 => '消息过长，无法发送',
      21015 => '需绑定手机号才能发送消息',
      21020 => '发送频率过快，请稍后再试',
      21026 => '不能给自己发消息',
      21046 => '发送过于频繁，请24小时后再试',
      21047 => '对方未关注你，最多发送1条消息',
      25003 => '对方隐私设置限制，无法发送',
      25005 => '已拉黑对方，请先解除拉黑',
      _ => message.isEmpty ? '发送失败 ($code)' : message,
    };
  }
}
