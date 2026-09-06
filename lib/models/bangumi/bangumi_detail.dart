/// 番剧 / 影视详情数据模型（参考 PiliPlus 与 BiliPai）。
///
/// 对应 B站 `/pgc/view/web/season` 接口返回的数据结构。
library;

int? _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

double? _asDouble(dynamic v) {
  if (v is double) return v;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

/// 番剧完整详情。
class BangumiDetail {
  final int seasonId;
  final int mediaId;
  final String title;
  final String? subtitle;
  final String? seasonTitle;
  final String? cover;
  final String? squareCover;
  final String evaluate;
  final BangumiRating? rating;
  final BangumiStat? stat;
  final NewEpDetail? newEp;
  final List<BangumiEpisode> episodes;
  final List<SeasonInfo> seasons;
  final List<BangumiSection> sections;
  final List<String> styles;
  final List<AreaInfo> areas;
  final String actors;
  final String staff;
  final int seasonType;
  final String seasonTypeName;
  final int total;
  final int mode;
  final BangumiUserStatus? userStatus;
  final BangumiPublish? publish;
  final BangumiRights? rights;

  const BangumiDetail({
    required this.seasonId,
    required this.mediaId,
    required this.title,
    this.subtitle,
    this.seasonTitle,
    this.cover,
    this.squareCover,
    this.evaluate = '',
    this.rating,
    this.stat,
    this.newEp,
    this.episodes = const [],
    this.seasons = const [],
    this.sections = const [],
    this.styles = const [],
    this.areas = const [],
    this.actors = '',
    this.staff = '',
    this.seasonType = 1,
    this.seasonTypeName = '番剧',
    this.total = 0,
    this.mode = 3,
    this.userStatus,
    this.publish,
    this.rights,
  });

  factory BangumiDetail.fromJson(Map<String, dynamic> json) {
    // 选集主列表
    final epsList = <BangumiEpisode>[];
    if (json['episodes'] is List) {
      for (final e in json['episodes'] as List) {
        if (e is Map<String, dynamic>) {
          epsList.add(BangumiEpisode.fromJson(e));
        } else if (e is Map) {
          epsList.add(BangumiEpisode.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }

    // 关联多季
    final seasonsList = <SeasonInfo>[];
    if (json['seasons'] is List) {
      for (final s in json['seasons'] as List) {
        if (s is Map<String, dynamic>) {
          seasonsList.add(SeasonInfo.fromJson(s));
        } else if (s is Map) {
          seasonsList.add(SeasonInfo.fromJson(Map<String, dynamic>.from(s)));
        }
      }
    }

    // 衍生分段（花絮、PV、预告）
    final sectionsList = <BangumiSection>[];
    if (json['section'] is List) {
      for (final sec in json['section'] as List) {
        if (sec is Map<String, dynamic>) {
          sectionsList.add(BangumiSection.fromJson(sec));
        } else if (sec is Map) {
          sectionsList.add(BangumiSection.fromJson(Map<String, dynamic>.from(sec)));
        }
      }
    }

    // 风格
    final stylesList = <String>[];
    if (json['styles'] is List) {
      for (final st in json['styles'] as List) {
        if (st is String && st.isNotEmpty) {
          stylesList.add(st);
        } else if (st is Map && st['name'] != null) {
          stylesList.add(st['name'].toString());
        }
      }
    }

    // 产地 / 地区
    final areasList = <AreaInfo>[];
    if (json['areas'] is List) {
      for (final a in json['areas'] as List) {
        if (a is Map<String, dynamic>) {
          areasList.add(AreaInfo.fromJson(a));
        } else if (a is Map) {
          areasList.add(AreaInfo.fromJson(Map<String, dynamic>.from(a)));
        }
      }
    }

    return BangumiDetail(
      seasonId: _asInt(json['season_id']) ?? 0,
      mediaId: _asInt(json['media_id']) ?? 0,
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString(),
      seasonTitle: json['season_title']?.toString(),
      cover: json['cover']?.toString(),
      squareCover: json['square_cover']?.toString(),
      evaluate: json['evaluate']?.toString() ?? '',
      rating: json['rating'] is Map
          ? BangumiRating.fromJson(Map<String, dynamic>.from(json['rating'] as Map))
          : null,
      stat: json['stat'] is Map
          ? BangumiStat.fromJson(Map<String, dynamic>.from(json['stat'] as Map))
          : null,
      newEp: json['new_ep'] is Map
          ? NewEpDetail.fromJson(Map<String, dynamic>.from(json['new_ep'] as Map))
          : null,
      episodes: epsList,
      seasons: seasonsList,
      sections: sectionsList,
      styles: stylesList,
      areas: areasList,
      actors: json['actors']?.toString() ?? '',
      staff: json['staff']?.toString() ?? '',
      seasonType: _asInt(json['season_type']) ?? 1,
      seasonTypeName: json['season_type_name']?.toString() ?? '番剧',
      total: _asInt(json['total']) ?? 0,
      mode: _asInt(json['mode']) ?? 3,
      userStatus: json['user_status'] is Map
          ? BangumiUserStatus.fromJson(Map<String, dynamic>.from(json['user_status'] as Map))
          : null,
      publish: json['publish'] is Map
          ? BangumiPublish.fromJson(Map<String, dynamic>.from(json['publish'] as Map))
          : null,
      rights: json['rights'] is Map
          ? BangumiRights.fromJson(Map<String, dynamic>.from(json['rights'] as Map))
          : null,
    );
  }

  /// 复制并更新部分字段（例如合并 section 分集）。
  BangumiDetail copyWith({
    List<BangumiEpisode>? episodes,
    List<BangumiSection>? sections,
    BangumiUserStatus? userStatus,
  }) {
    return BangumiDetail(
      seasonId: seasonId,
      mediaId: mediaId,
      title: title,
      subtitle: subtitle,
      seasonTitle: seasonTitle,
      cover: cover,
      squareCover: squareCover,
      evaluate: evaluate,
      rating: rating,
      stat: stat,
      newEp: newEp,
      episodes: episodes ?? this.episodes,
      seasons: seasons,
      sections: sections ?? this.sections,
      styles: styles,
      areas: areas,
      actors: actors,
      staff: staff,
      seasonType: seasonType,
      seasonTypeName: seasonTypeName,
      total: total,
      mode: mode,
      userStatus: userStatus ?? this.userStatus,
      publish: publish,
      rights: rights,
    );
  }
}

/// 单集数据模型。
class BangumiEpisode {
  final int id; // ep_id
  final int? aid;
  final String? bvid;
  final int? cid;
  final String title; // "1"
  final String? longTitle; // "第一话标题"
  final String? cover;
  final int? duration; // 毫秒
  final String? badge; // "会员", "预告", "限免"
  final int? badgeType;
  final int? status;
  final int? pubTime;
  final EpisodeSkip? skip;

  const BangumiEpisode({
    required this.id,
    this.aid,
    this.bvid,
    this.cid,
    required this.title,
    this.longTitle,
    this.cover,
    this.duration,
    this.badge,
    this.badgeType,
    this.status,
    this.pubTime,
    this.skip,
  });

  factory BangumiEpisode.fromJson(Map<String, dynamic> json) {
    return BangumiEpisode(
      id: _asInt(json['id'] ?? json['ep_id']) ?? 0,
      aid: _asInt(json['aid']),
      bvid: json['bvid']?.toString(),
      cid: _asInt(json['cid']),
      title: json['title']?.toString() ?? '',
      longTitle: json['long_title']?.toString(),
      cover: json['cover']?.toString(),
      duration: _asInt(json['duration']),
      badge: json['badge']?.toString(),
      badgeType: _asInt(json['badge_type']),
      status: _asInt(json['status']),
      pubTime: _asInt(json['pub_time']),
      skip: json['skip'] is Map
          ? EpisodeSkip.fromJson(Map<String, dynamic>.from(json['skip'] as Map))
          : null,
    );
  }

  /// 展示用完整标题（如 "第1话 终焉的开始" 或 "PV 1"）。
  String get displayTitle {
    final t = title.trim();
    final lt = longTitle?.trim();
    if (t.isNotEmpty && lt != null && lt.isNotEmpty) {
      return int.tryParse(t) != null ? '第$t话 $lt' : '$t $lt';
    }
    if (t.isNotEmpty) {
      return int.tryParse(t) != null ? '第$t话' : t;
    }
    return lt ?? '';
  }

  /// 格式化时长字符串（分:秒）。
  String get formattedDuration {
    if (duration == null || duration! <= 0) return '';
    final totalSec = duration! ~/ 1000;
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

/// 片头片尾跳过区间。
class EpisodeSkip {
  final SkipRange? op;
  final SkipRange? ed;

  const EpisodeSkip({this.op, this.ed});

  factory EpisodeSkip.fromJson(Map<String, dynamic> json) {
    return EpisodeSkip(
      op: json['op'] is Map
          ? SkipRange.fromJson(Map<String, dynamic>.from(json['op'] as Map))
          : null,
      ed: json['ed'] is Map
          ? SkipRange.fromJson(Map<String, dynamic>.from(json['ed'] as Map))
          : null,
    );
  }
}

class SkipRange {
  final int start;
  final int end;

  const SkipRange({required this.start, required this.end});

  factory SkipRange.fromJson(Map<String, dynamic> json) {
    return SkipRange(
      start: _asInt(json['start']) ?? 0,
      end: _asInt(json['end']) ?? 0,
    );
  }
}

/// 季度信息。
class SeasonInfo {
  final int seasonId;
  final String seasonTitle;
  final String title;
  final String? cover;
  final String? badge;
  final int? isNew;

  const SeasonInfo({
    required this.seasonId,
    required this.seasonTitle,
    required this.title,
    this.cover,
    this.badge,
    this.isNew,
  });

  factory SeasonInfo.fromJson(Map<String, dynamic> json) {
    return SeasonInfo(
      seasonId: _asInt(json['season_id']) ?? 0,
      seasonTitle: json['season_title']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      cover: json['cover']?.toString(),
      badge: json['badge']?.toString(),
      isNew: _asInt(json['is_new']),
    );
  }
}

/// 衍生分段（花絮/预告/特典）。
class BangumiSection {
  final int id;
  final String title;
  final int type;
  final List<BangumiEpisode> episodes;

  const BangumiSection({
    required this.id,
    required this.title,
    required this.type,
    this.episodes = const [],
  });

  factory BangumiSection.fromJson(Map<String, dynamic> json) {
    final eps = <BangumiEpisode>[];
    if (json['episodes'] is List) {
      for (final e in json['episodes'] as List) {
        if (e is Map<String, dynamic>) {
          eps.add(BangumiEpisode.fromJson(e));
        } else if (e is Map) {
          eps.add(BangumiEpisode.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return BangumiSection(
      id: _asInt(json['id']) ?? 0,
      title: json['title']?.toString() ?? '',
      type: _asInt(json['type']) ?? 0,
      episodes: eps,
    );
  }
}

/// 评分。
class BangumiRating {
  final double score;
  final int count;

  const BangumiRating({required this.score, required this.count});

  factory BangumiRating.fromJson(Map<String, dynamic> json) {
    return BangumiRating(
      score: _asDouble(json['score']) ?? 0.0,
      count: _asInt(json['count']) ?? 0,
    );
  }
}

/// 统计数据。
class BangumiStat {
  final int views;
  final int danmakus;
  final int favorites;
  final int coins;
  final int likes;
  final int reply;
  final int share;

  const BangumiStat({
    this.views = 0,
    this.danmakus = 0,
    this.favorites = 0,
    this.coins = 0,
    this.likes = 0,
    this.reply = 0,
    this.share = 0,
  });

  factory BangumiStat.fromJson(Map<String, dynamic> json) {
    return BangumiStat(
      views: _asInt(json['views'] ?? json['view']) ?? 0,
      danmakus: _asInt(json['danmakus'] ?? json['danmaku']) ?? 0,
      favorites: _asInt(json['favorites'] ?? json['follow']) ?? 0,
      coins: _asInt(json['coins'] ?? json['coin']) ?? 0,
      likes: _asInt(json['likes'] ?? json['like']) ?? 0,
      reply: _asInt(json['reply']) ?? 0,
      share: _asInt(json['share']) ?? 0,
    );
  }
}

/// 最新一集简述。
class NewEpDetail {
  final int id;
  final String title;
  final String desc;
  final int isNew;

  const NewEpDetail({
    this.id = 0,
    this.title = '',
    this.desc = '',
    this.isNew = 0,
  });

  factory NewEpDetail.fromJson(Map<String, dynamic> json) {
    return NewEpDetail(
      id: _asInt(json['id']) ?? 0,
      title: json['title']?.toString() ?? '',
      desc: json['desc']?.toString() ?? '',
      isNew: _asInt(json['is_new']) ?? 0,
    );
  }
}

/// 用户追番与观看状态。
class BangumiUserStatus {
  final int follow; // 1=已追番, 0=未追番
  final int followStatus; // 1=想看, 2=在看, 3=看过
  final int pay;
  final int? progressLastEpId;
  final int? progressLastTime; // ms

  const BangumiUserStatus({
    this.follow = 0,
    this.followStatus = 0,
    this.pay = 0,
    this.progressLastEpId,
    this.progressLastTime,
  });

  factory BangumiUserStatus.fromJson(Map<String, dynamic> json) {
    final progress = json['progress'] as Map<String, dynamic>?;
    return BangumiUserStatus(
      follow: _asInt(json['follow']) ?? 0,
      followStatus: _asInt(json['follow_status']) ?? 0,
      pay: _asInt(json['pay']) ?? 0,
      progressLastEpId: _asInt(progress?['last_ep_id']),
      progressLastTime: _asInt(progress?['last_time']),
    );
  }

  bool get isFollowed => follow == 1;

  BangumiUserStatus copyWith({
    int? follow,
    int? followStatus,
    int? pay,
    int? progressLastEpId,
    int? progressLastTime,
  }) {
    return BangumiUserStatus(
      follow: follow ?? this.follow,
      followStatus: followStatus ?? this.followStatus,
      pay: pay ?? this.pay,
      progressLastEpId: progressLastEpId ?? this.progressLastEpId,
      progressLastTime: progressLastTime ?? this.progressLastTime,
    );
  }
}

/// 发行与完结状态。
class BangumiPublish {
  final String? pubTime;
  final String? releaseDateShow;
  final int? isFinish;

  const BangumiPublish({
    this.pubTime,
    this.releaseDateShow,
    this.isFinish,
  });

  factory BangumiPublish.fromJson(Map<String, dynamic> json) {
    return BangumiPublish(
      pubTime: json['pub_time']?.toString(),
      releaseDateShow: json['release_date_show']?.toString(),
      isFinish: _asInt(json['is_finish']),
    );
  }
}

/// 权限与观看配置。
class BangumiRights {
  final int canWatch;
  final int allowReview;

  const BangumiRights({this.canWatch = 1, this.allowReview = 1});

  factory BangumiRights.fromJson(Map<String, dynamic> json) {
    return BangumiRights(
      canWatch: _asInt(json['can_watch']) ?? 1,
      allowReview: _asInt(json['allow_review']) ?? 1,
    );
  }
}

/// 地区信息。
class AreaInfo {
  final int id;
  final String name;

  const AreaInfo({required this.id, required this.name});

  factory AreaInfo.fromJson(Map<String, dynamic> json) {
    return AreaInfo(
      id: _asInt(json['id']) ?? 0,
      name: json['name']?.toString() ?? '',
    );
  }
}
