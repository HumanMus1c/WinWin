import 'package:winwin/models/common/owner.dart';

/// 稍后再看列表响应（`/x/v2/history/toview/web`）。
class LaterData {
  int? count;
  List<LaterItem>? list;

  LaterData({this.count, this.list});

  factory LaterData.fromJson(Map<String, dynamic> json) => LaterData(
        count: json['count'] as int?,
        list: (json['list'] as List<dynamic>?)
            ?.map((e) => LaterItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// 稍后再看列表项。
class LaterItem {
  int? aid;
  String? pic;
  String? title;
  String? subtitle;
  int? pubdate;
  int? duration;
  String? redirectUrl;
  Rights? rights;
  Owner? owner;
  Stat? stat;
  int? cid;
  int? progress;
  String? bvid;
  bool? isPgc;
  String? pgcLabel;
  bool? isPugv;
  bool? isCharging;

  LaterItem({
    this.aid,
    this.pic,
    this.title,
    this.subtitle,
    this.pubdate,
    this.duration,
    this.redirectUrl,
    this.rights,
    this.owner,
    this.stat,
    this.cid,
    this.progress,
    this.bvid,
    this.isPgc,
    this.pgcLabel,
    this.isPugv,
    this.isCharging,
  });

  factory LaterItem.fromJson(Map<String, dynamic> json) => LaterItem(
        aid: json['aid'] as int?,
        pic: json['pic'] as String?,
        title: json['title'] as String?,
        subtitle: json['bangumi']?['season']?['title'] as String?,
        pubdate: json['pubdate'] as int?,
        duration: json['duration'] as int?,
        redirectUrl: json['redirect_url'] as String?,
        rights: json['rights'] == null
            ? null
            : Rights.fromJson(json['rights'] as Map<String, dynamic>),
        owner: json['owner'] == null
            ? null
            : Owner.fromJson(json['owner'] as Map<String, dynamic>),
        stat: json['stat'] == null
            ? null
            : Stat.fromJson(json['stat'] as Map<String, dynamic>),
        cid: json['cid'] as int?,
        progress: json['progress'] as int?,
        bvid: json['bvid'] as String?,
        isPgc: json['is_pgc'] as bool?,
        pgcLabel: json['pgc_label'] as String?,
        isPugv: json['is_pugv'] as bool?,
        isCharging: json['is_charging'] as bool?,
      );
}

class Rights {
  int? isCooperation;

  Rights({this.isCooperation});

  factory Rights.fromJson(Map<String, dynamic> json) =>
      Rights(isCooperation: json['is_cooperation'] as int?);
}

class Stat {
  int? view;
  int? danmaku;

  Stat({this.view, this.danmaku});

  factory Stat.fromJson(Map<String, dynamic> json) => Stat(
        view: json['view'] as int?,
        danmaku: json['danmaku'] as int?,
      );
}
