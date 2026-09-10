import 'dart:async';

/// 全局事件总线，提供轻量、类型安全、低开销的跨组件/跨页面广播能力。
///
/// 借鉴 BiliPai 的 `_followStateChanges` 与 `WatchLaterRefreshBus` 设计思想，
/// 使用 Dart 标准库 `StreamController.broadcast()` 实现，零引入三方依赖。
class EventBus {
  static final EventBus _instance = EventBus._internal();
  factory EventBus() => _instance;
  EventBus._internal();

  final StreamController<dynamic> _controller =
      StreamController<dynamic>.broadcast();

  /// 监听类型为 [T] 的事件流。
  Stream<T> on<T>() {
    if (T == dynamic) {
      return _controller.stream.cast<T>();
    }
    return _controller.stream.where((event) => event is T).cast<T>();
  }

  /// 广播事件 [event]。
  void emit(dynamic event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  /// 释放总线流控制器。
  void destroy() {
    _controller.close();
  }
}

/// UP 主关注状态变更事件。
///
/// 当在视频详情页、UP主个人空间、关注流、或个人关系列表中对 [mid] 的关注状态
/// 发生变更时广播，携带最新的关注姿态 [isFollowing]。
class FollowEvent {
  const FollowEvent({
    required this.mid,
    required this.isFollowing,
  });

  /// 被关注/取关用户的 MID
  final int mid;

  /// 最新关注状态（true: 已关注/特别关注/互相关注; false: 未关注）
  final bool isFollowing;

  @override
  String toString() => 'FollowEvent(mid: $mid, isFollowing: $isFollowing)';
}

/// 稿件稍后再看状态变更事件。
///
/// 当在详情页、播放页卡片、稍后再看列表中添加、移除或清空时广播。
class WatchLaterEvent {
  const WatchLaterEvent({
    required this.aid,
    this.bvid,
    required this.inWatchLater,
  });

  /// 稿件 AID
  final int aid;

  /// 稿件 BVID（可选）
  final String? bvid;

  /// 当前是否处于稍后再看列表中
  final bool inWatchLater;

  @override
  String toString() =>
      'WatchLaterEvent(aid: $aid, bvid: $bvid, inWatchLater: $inWatchLater)';
}

/// 稿件互动姿态变更事件（点赞/投币/收藏/点踩）。
///
/// 当某处触发点赞、投币、收藏、点踩或一键三连成功后广播，供其他展示同一稿件的面板同步。
class VideoInteractionEvent {
  const VideoInteractionEvent({
    required this.aid,
    this.bvid,
    this.hasLike,
    this.coinNum,
    this.hasFav,
    this.hasDislike,
  });

  final int aid;
  final String? bvid;
  final bool? hasLike;
  final int? coinNum;
  final bool? hasFav;
  final bool? hasDislike;

  @override
  String toString() =>
      'VideoInteractionEvent(aid: $aid, bvid: $bvid, hasLike: $hasLike, coinNum: $coinNum, hasFav: $hasFav, hasDislike: $hasDislike)';
}
