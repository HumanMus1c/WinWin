// Ported from BiliPai (Kotlin) -> WinWin (Dart)
// Original: com/android/purebilibili/data/repository/CommentFraudDetectionPolicy.kt
//
// 评论影射检测策略（双探针）。
//
// B 站存在「评论影射」现象：某些评论对登录用户可见，但对未登录访客不可见
// （UP 主或平台对评论做了影射/限流处理）。这类评论实际无法被其他用户看到，
// 但评论者本人不知情。
//
// 检测原理（双探针）：
//   1. 以游客身份（不带 Cookie/Token）请求同一视频的评论列表 → guest 探针。
//   2. 以登录身份请求同一视频的评论列表 → auth 探针。
//   3. 对比：auth 中存在但 guest 中不存在的 rpid = 被影射的评论。
//
// 本策略是纯函数：仅做对比判断，不发起网络请求。调用方（如评论控制器）
// 负责分别拉取两份列表后调用本策略。

import 'package:winwin/models/video/reply_item.dart';

/// 评论影射检测结果。
class CommentFraudResult {
  /// 被影射的评论（auth 可见、guest 不可见）。
  final List<ReplyItemModel> shadowed;

  /// auth 列表中的评论总数。
  final int authCount;

  /// guest 列表中的评论总数。
  final int guestCount;

  const CommentFraudResult({
    required this.shadowed,
    required this.authCount,
    required this.guestCount,
  });

  /// 是否检测到影射评论。
  bool get hasFraud => shadowed.isNotEmpty;

  /// 影射比例（被影射数 / auth 总数）。authCount 为 0 时返回 0。
  double get fraudRatio =>
      authCount > 0 ? shadowed.length / authCount : 0.0;
}

/// 评论影射检测策略。
class CommentFraudPolicy {
  CommentFraudPolicy._();

  /// 对比 auth 与 guest 两份评论列表，返回被影射的评论。
  ///
  /// 判定规则：评论的 [ReplyItemModel.rpid] 在 [authReplies] 中存在、
  /// 但在 [guestReplies] 中不存在 → 该评论被影射。
  ///
  /// 注意：guest 探针通常只能看到前 N 条评论（无分页权限），
  /// 因此 auth 列表应只取与 guest 同一页的条目做对比，避免误报。
  static CommentFraudResult detect({
    required List<ReplyItemModel> authReplies,
    required List<ReplyItemModel> guestReplies,
  }) {
    final guestRpids = <int>{};
    for (final reply in guestReplies) {
      final rpid = reply.rpid;
      if (rpid != null && rpid > 0) guestRpids.add(rpid);
    }

    final shadowed = <ReplyItemModel>[];
    for (final reply in authReplies) {
      final rpid = reply.rpid;
      if (rpid == null || rpid <= 0) continue;
      if (!guestRpids.contains(rpid)) {
        shadowed.add(reply);
      }
    }

    return CommentFraudResult(
      shadowed: shadowed,
      authCount: authReplies.length,
      guestCount: guestReplies.length,
    );
  }

  /// 判断是否值得运行双探针检测。
  ///
  /// 条件：auth 列表与 guest 列表均非空，且 auth 列表条目数 > 0。
  /// 若 guest 探针为空（访客完全看不到评论），可能是视频关闭了评论
  /// 或网络失败，此时无法判定影射。
  static bool shouldRunDetection({
    required List<ReplyItemModel> authReplies,
    required List<ReplyItemModel> guestReplies,
  }) {
    return authReplies.isNotEmpty && guestReplies.isNotEmpty;
  }

  /// 判断单条评论是否被影射。
  ///
  /// 便捷方法：判断 [reply] 的 rpid 是否在 [guestRpids] 集合中。
  static bool isShadowed(ReplyItemModel reply, Set<int> guestRpids) {
    final rpid = reply.rpid;
    if (rpid == null || rpid <= 0) return false;
    return !guestRpids.contains(rpid);
  }
}
