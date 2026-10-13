import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/core/event/event_bus.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/member.dart';
import 'package:winwin/http/toview.dart';
import 'package:winwin/http/video.dart';
import 'package:winwin/models/video/video_detail.dart';
import 'package:winwin/pages/fav/fav_page.dart';
import 'package:winwin/pages/video/coin_dialog.dart';

/// 视频稿件互动状态与操作 Mixin。
///
/// 借鉴 PiliPlus `TripleMixin` 的解耦思想与 WinWin 的严密互斥/回滚闭环：
/// 1. 集中维护当前稿件的点赞、投币、收藏、点踩、关注、稍后再看状态；
/// 2. 封装原子三连、赞踩互斥、乐观更新与网络失败回滚；
/// 3. 接入 [EventBus]，支持跨页面广播与被动响应 UP 主关注（[FollowEvent]）、
///    稍后再看（[WatchLaterEvent]）及稿件互动姿态（[VideoInteractionEvent]）。
mixin VideoInteractionMixin<T extends StatefulWidget> on State<T> {
  // ─────────────────────────── 状态字段 ───────────────────────────

  /// 当前用户是否已点赞。
  bool hasLike = false;

  /// 当前用户是否已点踩。
  bool hasDislike = false;

  /// 当前用户已投硬币数（0~2）。
  int coinNum = 0;

  /// 当前用户是否已收藏。
  bool hasFav = false;

  /// 是否在稍后再看列表（null=未知/未登录，按未添加展示）。
  bool? inWatchLater;

  /// 当前用户是否已关注稿件 UP 主。
  bool isFollowed = false;

  /// 关注操作是否在进行中（防重复点击）。
  bool isFollowUpdating = false;

  StreamSubscription<FollowEvent>? _followSubscription;
  StreamSubscription<WatchLaterEvent>? _watchLaterSubscription;
  StreamSubscription<VideoInteractionEvent>? _interactionSubscription;

  // ─────────────────────────── 宿主契约 ───────────────────────────

  /// 当前视频 AID。
  int? get interactionAid;

  /// 当前视频 BVID。
  String get interactionBvid;

  /// 当前视频 UP 主 MID。
  int? get interactionOwnerMid;

  /// 校验登录并在首次登录后同步状态。
  Future<bool> requireLoginAndSync();

  /// 调整稿件 stat 统计数字的 UI 计数。
  void adjustStat(void Function(VideoStat stat) fn);

  /// 轻提示展示。
  void showToast(String msg);

  // ─────────────────────────── 总线监听 ───────────────────────────

  /// 初始化全局事件总线订阅。
  void initInteractionEventBus() {
    _followSubscription = EventBus().on<FollowEvent>().listen((event) {
      if (!mounted) return;
      final mid = interactionOwnerMid;
      if (mid != null && mid == event.mid) {
        if (isFollowed != event.isFollowing) {
          setState(() => isFollowed = event.isFollowing);
        }
      }
    });

    _watchLaterSubscription = EventBus().on<WatchLaterEvent>().listen((event) {
      if (!mounted) return;
      final aid = interactionAid;
      if (aid != null && aid == event.aid) {
        if (inWatchLater != event.inWatchLater) {
          setState(() => inWatchLater = event.inWatchLater);
        }
      }
    });

    _interactionSubscription =
        EventBus().on<VideoInteractionEvent>().listen((event) {
      if (!mounted) return;
      final aid = interactionAid;
      if (aid != null && aid == event.aid) {
        setState(() {
          if (event.hasLike != null) hasLike = event.hasLike!;
          if (event.hasDislike != null) hasDislike = event.hasDislike!;
          if (event.coinNum != null) coinNum = event.coinNum!;
          if (event.hasFav != null) hasFav = event.hasFav!;
        });
      }
    });
  }

  /// 释放全局事件总线订阅。
  void disposeInteractionEventBus() {
    _followSubscription?.cancel();
    _followSubscription = null;
    _watchLaterSubscription?.cancel();
    _watchLaterSubscription = null;
    _interactionSubscription?.cancel();
    _interactionSubscription = null;
  }

  // ─────────────────────────── 云端同步 ───────────────────────────

  /// 云端同步稿件互动状态（点赞/投币/收藏/点踩/关注，/x/web-interface/archive/relation）。
  Future<void> syncVideoRelation({int? aid, String? bvid}) async {
    if (!Accounts.main.isLogin) return;
    final effectiveAid = aid ?? interactionAid;
    final effectiveBvid = bvid ?? interactionBvid;
    final res = await VideoHttp.videoRelation(
      bvid: effectiveBvid,
      aid: effectiveAid,
    );
    if (!mounted) return;
    if (res case Success(:final response)) {
      setState(() {
        hasLike = response.like;
        hasDislike = response.dislike;
        coinNum = response.coin;
        hasFav = response.favorite;
        isFollowed = response.attention;
      });
    }
  }

  /// 同步稍后再看状态。
  Future<void> loadWatchLaterStatus(int? aid) async {
    if (aid == null || !Accounts.main.isLogin) {
      if (mounted) setState(() => inWatchLater = null);
      return;
    }
    for (int pn = 1; pn <= 5; pn++) {
      final res = await ToviewHttp.toviewList(page: pn);
      if (!mounted) return;
      if (res case Success(:final response)) {
        final list = response.list ?? const [];
        if (list.any((item) => item.aid == aid)) {
          setState(() => inWatchLater = true);
          return;
        }
        if (list.length < 20) break; // 已到尾页
      } else {
        break;
      }
    }
    if (!mounted) return;
    setState(() => inWatchLater = false);
  }

  // ─────────────────────────── 交互行为 ───────────────────────────

  /// （取消）点赞；点赞与点踩互斥，点赞时自动清除点踩态。
  Future<void> actionLikeVideo() async {
    final aid = interactionAid;
    if (aid == null) return;
    if (!await requireLoginAndSync()) return;
    if (!mounted) return;

    final wasLiked = hasLike;
    adjustStat((s) {
      hasLike = !wasLiked;
      hasDislike = false;
      s.like = (s.like ?? 0) + (wasLiked ? -1 : 1);
    });

    final res = await VideoHttp.likeVideo(aid: aid, type: wasLiked);
    if (!mounted) return;
    switch (res) {
      case Success(:final response):
        if (response != null && response.isNotEmpty) showToast(response);
        EventBus().emit(VideoInteractionEvent(
          aid: aid,
          bvid: interactionBvid,
          hasLike: hasLike,
          hasDislike: hasDislike,
        ));
      case Error(:final errMsg):
        // 回滚乐观更新。
        adjustStat((s) {
          hasLike = wasLiked;
          s.like = (s.like ?? 0) + (wasLiked ? -1 : 1);
        });
        showToast(errMsg ?? '操作失败');
      case Loading():
        break;
    }
  }

  /// （取消）点踩；点踩时自动取消点赞（B 站语义二者互斥）。
  Future<void> actionDislikeVideo() async {
    final aid = interactionAid;
    if (aid == null) return;
    if (!await requireLoginAndSync()) return;
    if (!mounted) return;

    final wasDisliked = hasDislike;
    final cancelledLike = !wasDisliked && hasLike;
    adjustStat((s) {
      hasDislike = !wasDisliked;
      if (cancelledLike) {
        hasLike = false;
        s.like = (s.like ?? 0) - 1;
      }
    });

    final res = await VideoHttp.dislikeVideo(aid: aid, type: wasDisliked);
    if (!mounted) return;
    if (res case Error(:final errMsg)) {
      // 回滚乐观更新。
      adjustStat((s) {
        hasDislike = wasDisliked;
        if (cancelledLike) {
          hasLike = true;
          s.like = (s.like ?? 0) + 1;
        }
      });
      showToast(errMsg ?? '操作失败');
    } else {
      EventBus().emit(VideoInteractionEvent(
        aid: aid,
        bvid: interactionBvid,
        hasLike: hasLike,
        hasDislike: hasDislike,
      ));
    }
  }

  /// 长按点赞一键三连：点赞 + 投币×2 + 收藏默认收藏夹。
  Future<void> actionTripleVideo() async {
    final aid = interactionAid;
    if (aid == null) return;
    if (hasLike && coinNum >= 2 && hasFav) {
      showToast('已完成三连');
      return;
    }
    if (!await requireLoginAndSync()) return;
    if (!mounted) return;

    final res = await VideoHttp.ugcTriple(bvid: interactionBvid, aid: aid);
    if (!mounted) return;
    switch (res) {
      case Success(:final response):
        adjustStat((s) {
          if (response.like && !hasLike) s.like = (s.like ?? 0) + 1;
          if (response.coin) {
            final add =
                (response.multiply > 0 ? response.multiply : 2) - coinNum;
            if (add > 0) s.coin = (s.coin ?? 0) + add;
          }
          if (response.fav && !hasFav) s.favorite = (s.favorite ?? 0) + 1;
          hasLike = hasLike || response.like;
          if (response.coin) coinNum = 2;
          hasFav = hasFav || response.fav;
          hasDislike = false;
        });
        showToast(response.allSuccess ? '三连成功' : '三连部分成功');
        EventBus().emit(VideoInteractionEvent(
          aid: aid,
          bvid: interactionBvid,
          hasLike: hasLike,
          hasDislike: false,
          coinNum: coinNum,
          hasFav: hasFav,
        ));
      case Error(:final errMsg):
        showToast(errMsg ?? '三连失败');
      case Loading():
        break;
    }
  }

  /// 投币入口：弹对话框选择数量与是否同时点赞。
  Future<void> actionCoinVideo() async {
    final aid = interactionAid;
    if (aid == null) return;
    if (!await requireLoginAndSync()) return;
    if (!mounted) return;
    if (coinNum >= 2) {
      showToast('达到投币上限啦~');
      return;
    }
    showCoinDialog(
      context,
      onPay: (count, withLike) => doCoinVideo(aid, count, withLike),
    );
  }

  /// 执行投币网络请求。
  Future<void> doCoinVideo(int aid, int count, bool withLike) async {
    final remain = 2 - coinNum;
    final actual = count > remain ? remain : count;
    if (actual <= 0) {
      showToast('达到投币上限啦~');
      return;
    }
    final res = await VideoHttp.coinVideo(
      aid: aid,
      multiply: actual,
      selectLike: withLike ? 1 : 0,
    );
    if (!mounted) return;
    switch (res) {
      case Success():
        adjustStat((s) {
          s.coin = (s.coin ?? 0) + actual;
          coinNum += actual;
          if (withLike && !hasLike) {
            hasLike = true;
            s.like = (s.like ?? 0) + 1;
          }
        });
        showToast('投币成功');
        EventBus().emit(VideoInteractionEvent(
          aid: aid,
          bvid: interactionBvid,
          coinNum: coinNum,
          hasLike: hasLike,
        ));
      case Error(:final errMsg):
        showToast(errMsg ?? '投币失败');
      case Loading():
        break;
    }
  }

  /// 收藏：弹出收藏夹选择面板。
  Future<void> actionFavVideo() async {
    final aid = interactionAid;
    if (aid == null) return;
    if (!await requireLoginAndSync()) return;
    if (!mounted) return;
    showFavPanel(context, rid: aid, onSuccess: (isFav) {
      if (!mounted) return;
      adjustStat((s) {
        if (isFav != hasFav) {
          hasFav = isFav;
          s.favorite = (s.favorite ?? 0) + (isFav ? 1 : -1);
        }
      });
      EventBus().emit(VideoInteractionEvent(
        aid: aid,
        bvid: interactionBvid,
        hasFav: hasFav,
      ));
    });
  }

  /// 分享：复制视频链接到剪贴板 + 上报分享计数。
  Future<void> actionShareVideo() async {
    final aid = interactionAid;
    await Clipboard.setData(
      ClipboardData(text: 'https://www.bilibili.com/video/$interactionBvid'),
    );
    if (!mounted) return;
    showToast('视频链接已复制');
    if (aid != null && Accounts.main.isLogin) {
      VideoHttp.shareVideo(aid: aid);
    }
  }

  /// 切换稍后再看（添加/移除）。
  Future<void> actionWatchLaterVideo() async {
    final aid = interactionAid;
    if (aid == null) return;
    if (!await requireLoginAndSync()) return;
    if (!mounted) return;

    final inList = inWatchLater ?? false;
    final res = inList
        ? await ToviewHttp.delToview(aid.toString())
        : await ToviewHttp.addToview(aid: aid);
    if (!mounted) return;
    switch (res) {
      case Success():
        final newInList = !inList;
        setState(() => inWatchLater = newInList);
        showToast(inList ? '已从稍后再看移除' : 'yeah！稍后再看');
        // 全局广播稍后再看变更
        EventBus().emit(WatchLaterEvent(
          aid: aid,
          bvid: interactionBvid,
          inWatchLater: newInList,
        ));
      case Error(:final errMsg):
        showToast(errMsg ?? '操作失败');
      case Loading():
        break;
    }
  }

  /// 切换作者关注状态。
  Future<void> toggleFollowOwner() async {
    final ownerMid = interactionOwnerMid;
    if (ownerMid == null) return;
    if (!await requireLoginAndSync()) return;
    if (!mounted) return;
    if (isFollowUpdating) return;

    final isCurrentlyFollowed = isFollowed;
    final act = isCurrentlyFollowed ? 2 : 1; // 1: 关注, 2: 取消关注

    setState(() => isFollowUpdating = true);
    final res = await MemberHttp.relationMod(
      mid: ownerMid,
      act: act,
      reSrc: 14,
    );
    if (!mounted) return;
    setState(() => isFollowUpdating = false);

    switch (res) {
      case Success():
        final newFollowed = !isCurrentlyFollowed;
        setState(() => isFollowed = newFollowed);
        showToast(isCurrentlyFollowed ? '已取消关注' : '关注成功');
        // 全局广播关注状态变更
        EventBus().emit(FollowEvent(
          mid: ownerMid,
          isFollowing: newFollowed,
        ));
      case Error(:final errMsg):
        showToast(errMsg ?? (isCurrentlyFollowed ? '取消关注失败' : '关注失败'));
      case Loading():
        break;
    }
  }
}
