import 'package:dio/dio.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/http/api.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/http/loading_state.dart';

/// 评论 HTTP（移植自 PiliPlus `lib/http/reply.dart`）。
///
/// 补全 WinWin `video.dart` 中缺失的评论接口：
/// - 评论踩/取消踩（hateReply）
/// - 评论置顶/取消置顶（replyTop）
/// - 评论举报（report）
/// - 评论互动状态（replyInteraction）
/// - 评论主体操作（replySubjectModify）
/// - 表情包列表（getEmoteList）
///
/// 评论列表/楼中楼/点赞/发表评论已在 `VideoHttp` 中实现，此处不重复。
abstract final class ReplyHttp {
  /// 评论踩/取消踩。
  ///
  /// [action]: 0=取消踩，1=踩。
  static Future<LoadingState<void>> hateReply({
    required int type,
    required int action,
    required int oid,
    required int rpid,
  }) async {
    final res = await Request().post(
      Api.hateReply,
      data: {
        'type': type,
        'oid': oid,
        'rpid': rpid,
        'action': action,
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

  /// 评论置顶/取消置顶。
  ///
  /// [isUpTop]: true=取消置顶，false=置顶（UP 主操作）。
  static Future<LoadingState<void>> replyTop({
    required Object oid,
    required Object type,
    required Object rpid,
    required bool isUpTop,
  }) async {
    final res = await Request().post(
      Api.replyTop,
      data: {
        'oid': oid,
        'type': type,
        'rpid': rpid,
        'action': isUpTop ? 0 : 1,
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

  /// 举报评论。
  ///
  /// [reasonType]: 0=自定义（需填 [reasonDesc]），其他为预设原因。
  /// [banUid]: 是否同时拉黑用户。
  static Future<LoadingState<void>> report({
    required Object rpid,
    required Object oid,
    required int reasonType,
    bool banUid = true,
    String? reasonDesc,
  }) async {
    final res = await Request().post(
      Api.replyReport,
      data: {
        'add_blacklist': banUid,
        'csrf': Accounts.main.csrf,
        'gaia_source': 'main_h5',
        'oid': oid,
        'platform': 'android',
        'reason': reasonType,
        'rpid': rpid,
        'scene': 'main',
        'type': 1,
        if (reasonType == 0) 'content': reasonDesc!,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']?.toString() ?? '');
    }
  }

  /// 评论互动状态（点赞数/回复数/分享数等）。
  static Future<LoadingState<Map<String, dynamic>>> replyInteraction({
    required Object oid,
    required Object type,
  }) async {
    final res = await Request().get(
      Api.replyInteraction,
      queryParameters: {
        'oid': oid,
        'type': type,
        'web_location': 333.1369,
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

  /// 评论主体操作（关注/取关评论区等）。
  ///
  /// [action]: 1=关注，0=取消关注。
  static Future<LoadingState<void>> replySubjectModify({
    required int oid,
    required int type,
    required int action,
  }) async {
    final res = await Request().post(
      Api.replySubjectModify,
      data: {
        'oid': oid,
        'type': type,
        'action': action,
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

  /// 获取表情包列表。
  ///
  /// [business]: 'reply'（回复）或 'dynamic'（动态）。
  static Future<LoadingState<List<Map<String, dynamic>>?>> getEmoteList({
    String? business,
  }) async {
    final res = await Request().get(
      Api.myEmote,
      queryParameters: {
        'business': business ?? 'reply',
        'web_location': '333.1245',
      },
    );
    if (res.data['code'] == 0) {
      final packages = res.data['data']?['packages'];
      return Success(
        packages is List
            ? packages
                .map((e) => e is Map ? e.cast<String, dynamic>() : <String, dynamic>{})
                .toList()
            : null,
      );
    } else {
      return Error(res.data['message']?.toString() ?? '');
    }
  }
}
