import 'package:winwin/utils/id_utils.dart';

/// Abstract base classes shared by web-style and app-style video items.
abstract class BaseOwner {
  int? mid;
  String? name;
}

abstract class BaseStat {
  int? view;
  int? like;
  int? danmu;
}

/// Owner as returned by the web feed (`owner` object).
class Owner extends BaseOwner {
  Owner.fromJson(Map<String, dynamic> json) {
    mid = json['mid'];
    name = json['name'];
  }
}

/// Stat as returned by the web feed (`stat` object).
class Stat extends BaseStat {
  Stat.fromJson(Map<String, dynamic> json) {
    view = json['view'];
    like = json['like'];
    danmu = json['danmaku'];
  }
}

/// Owner for the app feed, where the up name lives in `args.up_name`
/// (or `desc_button.text` for non-av cards).
class RcmdOwner extends BaseOwner {
  RcmdOwner.fromJson(Map<String, dynamic> json) {
    name = json['goto'] == 'av'
        ? ((json['args']?['up_name'] ?? '') as String)
        : ((json['desc_button']?['text'] ?? '') as String);
    mid = json['args']?['up_id'] ?? 0;
  }
}

/// Stat for the app feed, where play/danmaku counts are formatted strings
/// such as `cover_left_text_1 = "23.4万"`.
class RcmdStat extends BaseStat {
  RcmdStat.fromJson(Map<String, dynamic> json) {
    view = _parseCount(json['cover_left_text_1']);
    danmu = _parseCount(json['cover_left_text_2']);
  }
}

/// Parses bilibili-style count strings ("1234", "23.4万", "1.2亿") into a
/// plain int. Returns null when the input cannot be interpreted.
int? _parseCount(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  final text = value.toString().trim();
  if (text.isEmpty) return null;

  // Pure integers.
  final asInt = int.tryParse(text);
  if (asInt != null) return asInt;

  // Suffixed numbers, e.g. "23.4万" or "1.2亿".
  final match = RegExp(r'^([\d.]+)\s*([万亿wWkK]?)$').firstMatch(text);
  if (match == null) return null;
  final num? base = num.tryParse(match.group(1)!);
  if (base == null) return null;
  final multiplier = switch (match.group(2)!) {
    '万' || 'w' || 'W' => 10000,
    '亿' => 100000000,
    'k' || 'K' => 1000,
    _ => 1,
  };
  return (base * multiplier).round();
}

abstract class BaseRcmdVideoItemModel {
  String? title;
  String? bvid;
  int? cid;
  String? cover;
  int duration = -1;
  late BaseOwner owner;
  late BaseStat stat;
  String? rcmdReason;
  bool isFollowed = false;
  String? goto;
  String? uri;
  int? param;
  String? pgcBadge;
}

/// Item of the web recommend feed (`/x/web-interface/wbi/index/top/feed/rcmd`).
class RcmdVideoItemModel extends BaseRcmdVideoItemModel {
  int? pubdate;

  RcmdVideoItemModel.fromJson(Map<String, dynamic> json) {
    bvid = json['bvid'];
    cid = json['cid'];
    goto = json['goto'];
    uri = json['uri'];
    cover = json['pic'];
    title = json['title'];
    duration = json['duration'] ?? -1;
    pubdate = json['pubdate'];
    param = json['id'];
    if (json['owner'] is Map<String, dynamic>) {
      owner = Owner.fromJson(json['owner']);
    } else {
      owner = Owner.fromJson(const {});
    }
    if (json['stat'] is Map<String, dynamic>) {
      stat = Stat.fromJson(json['stat']);
    } else {
      stat = Stat.fromJson(const {});
    }
    isFollowed = json['is_followed'] == 1 || json['is_followed'] == true;
    rcmdReason = json['rcmd_reason']?['content'];
  }
}

/// Item of the app recommend feed (`app.bilibili.com/x/v2/feed/index`).
class RcmdVideoItemAppModel extends BaseRcmdVideoItemModel {
  String? cardType;
  String? desc;

  RcmdVideoItemAppModel.fromJson(Map<String, dynamic> json) {
    final playerArgs = json['player_args'] is Map<String, dynamic>
        ? json['player_args'] as Map<String, dynamic>
        : null;

    param = playerArgs?['aid'] ?? int.tryParse('${json['param'] ?? ''}');
    bvid = json['bvid'] ??
        (param != null && param! > 0 ? IdUtils.av2bv(param!) : null);
    cid = playerArgs?['cid'];
    cover = json['cover'];
    title = json['title'];
    duration = playerArgs?['duration'] ?? 0;
    owner = RcmdOwner.fromJson(json);
    stat = RcmdStat.fromJson(json);
    rcmdReason = json['rcmd_reason'];
    // 由于app端api并不会直接返回与owner的关注状态
    // 所以借用推荐原因是否为“已关注”、“新关注”判别关注状态，从而与web端接口等效
    isFollowed = const {'已关注', '新关注'}.contains(rcmdReason);
    // 如果是，就无需再显示推荐原因，交由view统一处理即可
    if (isFollowed) rcmdReason = null;

    goto = json['goto'];
    uri = json['uri'];

    if (json['goto'] == 'bangumi') {
      pgcBadge = json['cover_right_text'];
    }

    cardType = json['card_type'];
    desc = json['desc'];
  }
}
