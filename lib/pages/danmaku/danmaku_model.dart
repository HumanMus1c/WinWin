// Ported from PiliPlus (Dart) -> WinWin
// Original: lib/pages/danmaku/danmaku_model.dart
//
// 弹幕附加元数据模型。
//
// 作为 [DanmakuContentItem.extra] 的承载类型，区分视频弹幕与直播弹幕的
// 附加信息（点赞 / 用户标记 / 时间戳等），供 UI 层（点赞、举报、跳转）
// 与发送层（回显）使用。

/// 弹幕附加元数据基类。
sealed class DanmakuExtra {
  Object get mid;
  Object get id;

  const DanmakuExtra();
}

/// 视频弹幕附加元数据。
class VideoDanmaku extends DanmakuExtra {
  @override
  final int id;
  @override
  final String mid;

  int like;
  bool isLike;

  VideoDanmaku({
    required this.id,
    required this.mid,
    this.like = 0,
    this.isLike = false,
  });
}

/// 直播弹幕附加元数据。
class LiveDanmaku extends DanmakuExtra {
  @override
  final Object id;
  @override
  final Object mid;

  final int dmType;
  final Object ts;
  final Object ct;

  const LiveDanmaku({
    required this.id,
    required this.mid,
    required this.dmType,
    required this.ts,
    required this.ct,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'mid': mid,
        'dm_type': dmType,
        'ts': ts,
        'ct': ct,
      };
}
