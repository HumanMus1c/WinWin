import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:winwin/common/constants.dart';
import 'package:winwin/http/api.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/models/dynamics/dyn_type.dart';
import 'package:winwin/utils/bilibili_url_parser.dart';
import 'package:winwin/utils/id_utils.dart';

/// 动态流 HTTP（移植自 PiliPlus `lib/http/dynamic.dart`，精简为桌面端所需）。
///
/// 包含关注动态流、单条动态详情、用户空间动态三个接口。
abstract final class DynHttp {
  /// 关注动态流（`/x/polymer/web-dynamic/v1/feed/all`）。
  ///
  /// - [offset]：上一页返回的 offset 字符串，首次为空。
  /// - [type]：动态类型过滤，默认 'video'（仅视频动态）；'all' 为全部。
  ///
  /// 成功返回 [DynFeedData]，含 items 列表与下一页 offset。
  static Future<LoadingState<DynFeedData>> followDynamic({
    String? offset,
    String type = 'video',
  }) async {
    try {
      final res = await Request().get<dynamic>(
        Api.followDynamic,
        queryParameters: {
          'timezone_offset': '-480',
          'type': type,
          'offset': offset ?? '',
          'page': 1,
          'features': Constants.dynFeatures,
        },
      );
      final data = res.data as Map<String, dynamic>;
      if (data['code'] == 0) {
        return Success(
          DynFeedData.fromJson(data['data'] as Map<String, dynamic>? ?? {}),
        );
      }
      return Error(data['message']?.toString() ?? '获取动态失败');
    } on DioException catch (e) {
      return Error('获取动态失败：${e.message ?? e.type.name}');
    } catch (e) {
      return Error('获取动态失败：$e');
    }
  }

  /// 单条动态详情（`/x/polymer/web-dynamic/v1/detail`）。
  ///
  /// [dynamicId] 为动态 id 字符串。
  static Future<LoadingState<DynItemModel>> dynamicDetail({
    required String dynamicId,
  }) async {
    try {
      final res = await Request().get<dynamic>(
        Api.dynamicDetail,
        queryParameters: {'dynamic_id': dynamicId},
      );
      final data = res.data as Map<String, dynamic>;
      if (data['code'] == 0) {
        final item = data['data']?['item'];
        if (item is Map<String, dynamic>) {
          return Success(DynItemModel.fromJson(item));
        }
        return const Error('动态详情为空');
      }
      return Error(data['message']?.toString() ?? '获取动态详情失败');
    } on DioException catch (e) {
      return Error('获取动态详情失败：${e.message ?? e.type.name}');
    } catch (e) {
      return Error('获取动态详情失败：$e');
    }
  }

  /// 用户空间动态（`/x/polymer/web-dynamic/v1/feed/space`）。
  ///
  /// - [hostMid]：空间所属用户 mid。
  /// - [offset]：分页 offset，首次为空。
  static Future<LoadingState<DynFeedData>> memberDynamic({
    required int hostMid,
    String? offset,
  }) async {
    try {
      final res = await Request().get<dynamic>(
        Api.memberDynamic,
        queryParameters: {
          'host_mid': hostMid,
          'offset': offset ?? '',
          'page': 1,
          'features': Constants.dynFeatures,
        },
      );
      final data = res.data as Map<String, dynamic>;
      if (data['code'] == 0) {
        return Success(
          DynFeedData.fromJson(data['data'] as Map<String, dynamic>? ?? {}),
        );
      }
      return Error(data['message']?.toString() ?? '获取用户动态失败');
    } on DioException catch (e) {
      return Error('获取用户动态失败：${e.message ?? e.type.name}');
    } catch (e) {
      return Error('获取用户动态失败：$e');
    }
  }
}

/// 动态流分页数据。
class DynFeedData {
  final List<DynItemModel> items;
  final bool hasMore;
  final String offset;

  DynFeedData({this.items = const [], this.hasMore = false, this.offset = ''});

  factory DynFeedData.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List?;
    final list = <DynItemModel>[];
    if (rawItems != null) {
      for (final e in rawItems) {
        if (e is Map) {
          try {
            list.add(DynItemModel.fromJson(Map<String, dynamic>.from(e)));
          } catch (_) {}
        }
      }
    }
    return DynFeedData(
      items: list,
      hasMore: json['has_more'] == true,
      offset: json['offset']?.toString() ?? '',
    );
  }
}

/// 单条动态。
class DynItemModel {
  /// 动态 id 字符串。
  final String id;
  /// 动态类型（DYNAMIC_TYPE_AV / DYNAMIC_TYPE_FORWARD / DYNAMIC_TYPE_DRAW 等）。
  final String type;
  /// 作者信息。
  final DynAuthor? author;
  /// 视频信息（仅 DYNAMIC_TYPE_AV 或内嵌视频存在）。
  final DynArchive? archive;
  /// 图文动态图片信息（仅 DYNAMIC_TYPE_DRAW 存在）。
  final DynDraw? draw;
  /// 专栏动态信息（仅 DYNAMIC_TYPE_ARTICLE 存在）。
  final DynArticle? article;
  /// Opus 新版图文/文章信息。
  final DynOpus? opus;
  /// 直播信息（含开播与推荐）。
  final DynLive? live;
  /// 剧集/追番信息（仅 DYNAMIC_TYPE_PGC 或 MAJOR_TYPE_PGC 存在）。
  final DynPgc? pgc;
  /// 失效/空动态提示信息。
  final DynNone? none;
  /// 文本描述（动态正文）。
  final String? text;
  /// 富文本节点（@、表情、网页链接、商品链接、BV 链接等）。
  final List<DynRichTextNode> richTextNodes;
  /// 附加模块（商品卡、投票等）。
  final DynAdditional? additional;
  /// 互动数据（点赞、转发、评论）。
  final DynStat? stat;
  /// 发布时间（Unix 时间戳，秒）。
  final int? pubTs;
  /// 转发动态的原动态（嵌套一层）。
  final DynItemModel? orig;
  /// Major 类型。
  final String? majorType;

  /// 兼容旧代码 liveRcmd 命名。
  DynLive? get liveRcmd => live;

  DynItemModel({
    required this.id,
    required this.type,
    this.author,
    this.archive,
    this.draw,
    this.article,
    this.opus,
    DynLive? live,
    DynLive? liveRcmd,
    this.pgc,
    this.none,
    this.text,
    this.richTextNodes = const [],
    this.additional,
    this.stat,
    this.pubTs,
    this.orig,
    this.majorType,
  }) : live = live ?? liveRcmd;

  /// 是否为视频动态（包含投稿视频与合集更新）。
  bool get isVideo =>
      type == DynType.av ||
      type == DynType.ugcSeason ||
      majorType == DynMajorType.archive ||
      majorType == DynMajorType.ugcSeason ||
      (archive != null && (archive!.bvid != null || archive!.title != null));

  /// 是否为转发动态。
  bool get isForward => type == DynType.forward || orig != null;

  /// 是否为图文动态（旧版图文）。
  bool get isDraw =>
      (type == DynType.draw || majorType == DynMajorType.draw) &&
      draw != null &&
      draw!.items.isNotEmpty;

  /// 是否为专栏（旧版专栏）。
  bool get isArticle =>
      (type == DynType.article || majorType == DynMajorType.article) &&
      article != null;

  /// 是否为 Opus（新版图文/文章）。
  bool get isOpus =>
      (majorType == DynMajorType.opus || opus != null) && opus != null;

  /// 是否为直播动态（UP主直播或推荐）。
  bool get isLive =>
      type == DynType.live ||
      type == DynType.liveRcmd ||
      majorType == DynMajorType.live ||
      majorType == DynMajorType.liveRcmd ||
      live != null;

  /// 是否为追番/剧集动态。
  bool get isPgc =>
      type == DynType.pgc ||
      type == DynType.pgcUnion ||
      majorType == DynMajorType.pgc ||
      majorType == DynMajorType.pgcUnion ||
      (pgc != null && (pgc!.title != null || pgc!.cover != null));

  /// 是否为已失效动态。
  bool get isNone =>
      type == DynType.none ||
      majorType == DynMajorType.none ||
      none != null;

  factory DynItemModel.fromJson(Map<String, dynamic> json) {
    final modules = json['modules'] is Map
        ? Map<String, dynamic>.from(json['modules'] as Map)
        : <String, dynamic>{};
    final moduleAuthor = modules['module_author'] is Map
        ? Map<String, dynamic>.from(modules['module_author'] as Map)
        : <String, dynamic>{};
    final moduleDynamic = modules['module_dynamic'] is Map
        ? Map<String, dynamic>.from(modules['module_dynamic'] as Map)
        : <String, dynamic>{};
    final desc = moduleDynamic['desc'] is Map
        ? Map<String, dynamic>.from(moduleDynamic['desc'] as Map)
        : <String, dynamic>{};
    final major = moduleDynamic['major'] is Map
        ? Map<String, dynamic>.from(moduleDynamic['major'] as Map)
        : <String, dynamic>{};
    final additional = moduleDynamic['additional'] is Map
        ? Map<String, dynamic>.from(moduleDynamic['additional'] as Map)
        : null;
    final moduleStat = modules['module_stat'] is Map
        ? Map<String, dynamic>.from(modules['module_stat'] as Map)
        : null;

    final rawRichNodes = desc['rich_text_nodes'] as List?;
    final richNodes = <DynRichTextNode>[];
    if (rawRichNodes != null) {
      for (final n in rawRichNodes) {
        if (n is Map) {
          try {
            richNodes.add(DynRichTextNode.fromJson(Map<String, dynamic>.from(n)));
          } catch (_) {}
        }
      }
    }

    final rawOrig = json['orig'];
    DynItemModel? origItem;
    if (rawOrig is Map) {
      try {
        origItem = DynItemModel.fromJson(Map<String, dynamic>.from(rawOrig));
      } catch (_) {}
    }

    final majorTypeStr = major['type']?.toString();

    final author = DynAuthor.fromJson(moduleAuthor);

    return DynItemModel(
      id: json['id_str']?.toString() ?? json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      majorType: majorTypeStr,
      author: author,
      archive: DynArchive.fromMajor(major),
      draw: DynDraw.fromMajor(major),
      article: DynArticle.fromMajor(major),
      opus: DynOpus.fromMajor(major),
      live: DynLive.fromMajor(major, author: author),
      pgc: DynPgc.fromMajor(major),
      none: DynNone.fromMajor(major),
      text: desc['text']?.toString(),
      richTextNodes: richNodes,
      additional:
          additional != null ? DynAdditional.fromJson(additional) : null,
      stat: moduleStat != null ? DynStat.fromJson(moduleStat) : null,
      pubTs: _asInt(moduleAuthor['pub_ts']),
      orig: origItem,
    );
  }
}

/// 动态作者信息。
class DynAuthor {
  final int? mid;
  final String? name;
  final String? face;
  final String? pubAction;

  DynAuthor({this.mid, this.name, this.face, this.pubAction});

  factory DynAuthor.fromJson(Map<String, dynamic> json) {
    return DynAuthor(
      mid: _asInt(json['mid']),
      name: json['name']?.toString(),
      face: json['face']?.toString(),
      pubAction: json['pub_action']?.toString(),
    );
  }
}

/// 动态内嵌的视频/合集稿件信息（MAJOR_TYPE_ARCHIVE / MAJOR_TYPE_UGC_SEASON）。
class DynArchive {
  final String? bvid;
  final String? title;
  final String? cover;
  final String? durationText;
  final int? play;
  final int? danmaku;
  final String? badge;

  DynArchive({
    this.bvid,
    this.title,
    this.cover,
    this.durationText,
    this.play,
    this.danmaku,
    this.badge,
  });

  /// 从 major 节点解析：支持 major.archive 为视频稿件，或 major.ugc_season 为合集。
  static DynArchive? fromMajor(Map<String, dynamic> major) {
    final type = major['type']?.toString();
    if (type == DynMajorType.archive && major['archive'] is Map) {
      return DynArchive.fromVideoMap(
        Map<String, dynamic>.from(major['archive'] as Map),
      );
    }
    if (type == DynMajorType.ugcSeason && major['ugc_season'] is Map) {
      return DynArchive.fromUgcSeasonMap(
        Map<String, dynamic>.from(major['ugc_season'] as Map),
      );
    }
    // 容错：有些合集或者视频没有显式写 type，但包含 ugc_season 或 archive 字典
    if (major['ugc_season'] is Map) {
      return DynArchive.fromUgcSeasonMap(
        Map<String, dynamic>.from(major['ugc_season'] as Map),
      );
    }
    if (major['archive'] is Map) {
      return DynArchive.fromVideoMap(
        Map<String, dynamic>.from(major['archive'] as Map),
      );
    }
    return null;
  }

  factory DynArchive.fromVideoMap(Map<String, dynamic> map) {
    final badgeObj = map['badge'];
    String? badgeText;
    if (badgeObj is Map) {
      badgeText = badgeObj['text']?.toString();
    } else if (badgeObj is String) {
      badgeText = badgeObj;
    }
    return DynArchive(
      bvid: map['bvid']?.toString(),
      title: map['title']?.toString(),
      cover: map['cover']?.toString(),
      durationText: map['duration_text']?.toString(),
      play: _asInt(map['play']),
      danmaku: _asInt(map['danmaku']),
      badge: badgeText,
    );
  }

  factory DynArchive.fromUgcSeasonMap(Map<String, dynamic> map) {
    final subArchive = map['archive'] is Map
        ? Map<String, dynamic>.from(map['archive'] as Map)
        : null;
    final stat = map['stat'] is Map
        ? Map<String, dynamic>.from(map['stat'] as Map)
        : null;

    String? bvid = map['bvid']?.toString() ?? subArchive?['bvid']?.toString();
    final aid = _asInt(map['aid'] ?? subArchive?['aid']);
    if ((bvid == null || bvid.isEmpty) && aid != null && aid > 0) {
      bvid = IdUtils.av2bv(aid);
    }

    final title = map['title']?.toString() ?? subArchive?['title']?.toString();
    final cover = map['cover']?.toString() ?? subArchive?['cover']?.toString();
    final durationText = map['duration_text']?.toString() ??
        subArchive?['duration_text']?.toString();
    final play = _asInt(stat?['play'] ?? map['play'] ?? subArchive?['play']);
    final danmaku = _asInt(stat?['danmaku'] ?? map['danmaku'] ?? subArchive?['danmaku']);

    final badgeObj = map['badge'];
    String? badgeText;
    if (badgeObj is Map) {
      badgeText = badgeObj['text']?.toString();
    } else if (badgeObj is String) {
      badgeText = badgeObj;
    }

    return DynArchive(
      bvid: bvid,
      title: title,
      cover: cover,
      durationText: durationText,
      play: play,
      danmaku: danmaku,
      badge: badgeText ?? '合集',
    );
  }
}

/// 图文动态单张图片。
class DynDrawItem {
  final String? src;
  final double? width;
  final double? height;
  final double? size;

  DynDrawItem({this.src, this.width, this.height, this.size});

  factory DynDrawItem.fromJson(Map<String, dynamic> json) {
    return DynDrawItem(
      src: json['src']?.toString() ?? json['url']?.toString(),
      width: _asDouble(json['width']),
      height: _asDouble(json['height']),
      size: _asDouble(json['size']),
    );
  }
}

/// 图文动态图片列表（MAJOR_TYPE_DRAW）。
class DynDraw {
  final List<DynDrawItem> items;

  DynDraw({this.items = const []});

  static DynDraw? fromMajor(Map<String, dynamic> major) {
    if (major['type'] != DynMajorType.draw && major['draw'] == null) return null;
    final draw = major['draw'] as Map<String, dynamic>? ?? {};
    final rawItems = draw['items'] as List?;
    final items = rawItems
            ?.map((e) => DynDrawItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [];
    if (items.isEmpty) return null;
    return DynDraw(items: items);
  }
}

/// 专栏动态（MAJOR_TYPE_ARTICLE）。
class DynArticle {
  final int? id;
  final String? title;
  final String? desc;
  final List<String> covers;
  final String? label;
  final String? jumpUrl;

  DynArticle({
    this.id,
    this.title,
    this.desc,
    this.covers = const [],
    this.label,
    this.jumpUrl,
  });

  static DynArticle? fromMajor(Map<String, dynamic> major) {
    if (major['type'] != DynMajorType.article && major['article'] == null) return null;
    final article = major['article'] as Map<String, dynamic>? ?? {};
    final rawCovers = article['covers'] as List?;
    final title = article['title']?.toString();
    final covers = rawCovers?.map((e) => e.toString()).toList() ?? const [];
    if (title == null && covers.isEmpty) return null;
    return DynArticle(
      id: _asInt(article['id']),
      title: title,
      desc: article['desc']?.toString(),
      covers: covers,
      label: article['label']?.toString(),
      jumpUrl: article['jump_url']?.toString(),
    );
  }
}

/// Opus 新版图文/文章（MAJOR_TYPE_OPUS）。
class DynOpus {
  final String? jumpUrl;
  final String? title;
  final String? summaryText;
  final List<DynDrawItem> pics;
  final DynArchive? video;

  DynOpus({
    this.jumpUrl,
    this.title,
    this.summaryText,
    this.pics = const [],
    this.video,
  });

  static DynOpus? fromMajor(Map<String, dynamic> major) {
    if (major['type'] != DynMajorType.opus && major['opus'] == null) return null;
    final opus = major['opus'] as Map<String, dynamic>? ?? {};
    final summary = opus['summary'] as Map<String, dynamic>? ?? {};
    final rawPics = opus['pics'] as List?;
    final video = opus['video'] as Map<String, dynamic>?;

    final pics = rawPics
            ?.map((e) => DynDrawItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [];
    final title = opus['title']?.toString();
    final summaryText = summary['text']?.toString();
    final dynVideo = video != null ? DynArchive.fromVideoMap(video) : null;

    if (pics.isEmpty &&
        (title == null || title.isEmpty) &&
        (summaryText == null || summaryText.isEmpty) &&
        dynVideo == null) {
      return null;
    }

    return DynOpus(
      jumpUrl: opus['jump_url']?.toString(),
      title: title,
      summaryText: summaryText,
      pics: pics,
      video: dynVideo,
    );
  }
}

/// 直播信息（兼容 MAJOR_TYPE_LIVE_RCMD 与 MAJOR_TYPE_LIVE）。
class DynLive {
  final int? roomId;
  final String? title;
  final String? cover;
  final String? uname;
  final String? watchedShow;
  final String? descFirst;
  final int? liveStatus;
  final String? badge;
  final String? jumpUrl;

  DynLive({
    this.roomId,
    this.title,
    this.cover,
    this.uname,
    this.watchedShow,
    this.descFirst,
    this.liveStatus,
    this.badge,
    this.jumpUrl,
  });

  bool get isLiving => liveStatus == 1 || badge == '直播中';

  static DynLive? fromMajor(Map<String, dynamic> major, {DynAuthor? author}) {
    final type = major['type']?.toString();

    // 1. UP 主直接开播动态（MAJOR_TYPE_LIVE，数据挂在 major['live']）
    if ((type == DynMajorType.live || major['live'] is Map) &&
        major['live'] is Map) {
      final live = Map<String, dynamic>.from(major['live'] as Map);
      final badgeObj = live['badge'];
      String? badgeText;
      if (badgeObj is Map) {
        badgeText = badgeObj['text']?.toString();
      } else if (badgeObj is String) {
        badgeText = badgeObj;
      }
      final state = _asInt(live['live_state']);
      final jumpUrl = live['jump_url']?.toString();

      // 关键修复：B站 MAJOR_TYPE_LIVE 下 live['id'] 为开播场次记录 ID（非房间号）！
      // 必须优先从 jump_url 提取真实房间号，其次取 room_id / roomid，最后兜底 id
      int? resolvedRoomId;
      if (jumpUrl != null && jumpUrl.isNotEmpty) {
        resolvedRoomId = BilibiliUrlParser.parse(jumpUrl).roomId;
      }
      resolvedRoomId ??= _asInt(live['room_id'] ?? live['roomid'] ?? live['id']);

      return DynLive(
        roomId: resolvedRoomId,
        title: live['title']?.toString(),
        cover: live['cover']?.toString() ?? author?.face,
        uname: author?.name,
        descFirst: live['desc_first']?.toString(),
        liveStatus: state,
        badge: badgeText ?? (state == 1 ? '直播中' : '已结束'),
        jumpUrl: jumpUrl,
      );
    }

    // 2. 直播推荐动态（MAJOR_TYPE_LIVE_RCMD，数据挂在 major['live_rcmd']）
    if ((type == DynMajorType.liveRcmd || major['live_rcmd'] is Map) &&
        major['live_rcmd'] is Map) {
      final liveRcmd = Map<String, dynamic>.from(major['live_rcmd'] as Map);
      Map<String, dynamic> liveInfo = {};
      if (liveRcmd['content'] is String) {
        try {
          final decoded = jsonDecode(liveRcmd['content'] as String);
          if (decoded is Map<String, dynamic>) {
            liveInfo =
                decoded['live_play_info'] as Map<String, dynamic>? ?? decoded;
          }
        } catch (_) {}
      } else if (liveRcmd['live_play_info'] is Map<String, dynamic>) {
        liveInfo = liveRcmd['live_play_info'] as Map<String, dynamic>;
      } else {
        liveInfo = liveRcmd;
      }

      final watched = liveInfo['watched_show'] is Map<String, dynamic>
          ? liveInfo['watched_show'] as Map<String, dynamic>
          : null;

      final liveStatus = _asInt(liveInfo['live_status']);
      final jumpUrl = liveInfo['jump_url']?.toString();

      int? resolvedRoomId;
      if (jumpUrl != null && jumpUrl.isNotEmpty) {
        resolvedRoomId = BilibiliUrlParser.parse(jumpUrl).roomId;
      }
      resolvedRoomId ??= _asInt(liveInfo['room_id'] ?? liveInfo['roomid'] ?? liveInfo['id']);

      return DynLive(
        roomId: resolvedRoomId,
        title: liveInfo['title']?.toString(),
        cover: liveInfo['cover']?.toString() ?? author?.face,
        uname: liveInfo['uname']?.toString() ?? author?.name,
        watchedShow: watched?['text_large']?.toString() ??
            watched?['text_small']?.toString() ??
            liveInfo['watched_show']?.toString(),
        liveStatus: liveStatus,
        badge: liveStatus == 1 ? '直播中' : null,
        jumpUrl: jumpUrl,
      );
    }

    return null;
  }
}

/// 兼容旧别名
typedef DynLiveRcmd = DynLive;

/// 剧集/追番动态（MAJOR_TYPE_PGC）。
class DynPgc {
  final int? seasonId;
  final int? epId;
  final String? title;
  final String? cover;
  final String? badge;
  final String? jumpUrl;
  final String? subType;
  final int? play;
  final int? danmaku;

  DynPgc({
    this.seasonId,
    this.epId,
    this.title,
    this.cover,
    this.badge,
    this.jumpUrl,
    this.subType,
    this.play,
    this.danmaku,
  });

  static DynPgc? fromMajor(Map<String, dynamic> major) {
    if (major['type'] != DynMajorType.pgc &&
        major['type'] != DynMajorType.pgcUnion &&
        major['pgc'] == null) {
      return null;
    }
    final pgc = major['pgc'] as Map<String, dynamic>? ?? {};
    final stat = pgc['stat'] as Map<String, dynamic>? ?? {};
    final badgeObj = pgc['badge'];
    String? badgeText;
    if (badgeObj is Map) {
      badgeText = badgeObj['text']?.toString();
    } else if (badgeObj is String) {
      badgeText = badgeObj;
    }
    final title = pgc['title']?.toString();
    final cover = pgc['cover']?.toString();
    if (title == null && cover == null) return null;

    return DynPgc(
      seasonId: _asInt(pgc['season_id']),
      epId: _asInt(pgc['epid'] ?? pgc['ep_id']),
      title: title,
      cover: cover,
      badge: badgeText ?? pgc['sub_type_name']?.toString(),
      jumpUrl: pgc['jump_url']?.toString(),
      subType: pgc['sub_type']?.toString(),
      play: _asInt(stat['play']),
      danmaku: _asInt(stat['danmaku']),
    );
  }
}

/// 失效/空动态信息（MAJOR_TYPE_NONE）。
class DynNone {
  final String? tips;

  DynNone({this.tips});

  static DynNone? fromMajor(Map<String, dynamic> major) {
    if (major['type'] != DynMajorType.none && major['none'] == null) {
      return null;
    }
    final none = major['none'] as Map<String, dynamic>? ?? {};
    final tips = none['tips']?.toString();
    return DynNone(tips: tips ?? '内容已失效');
  }
}

/// 富文本节点。
class DynRichTextNode {
  final String? type;
  final String? text;
  final String? origText;
  final String? jumpUrl;
  final String? rid;
  final String? emojiUrl;

  DynRichTextNode({
    this.type,
    this.text,
    this.origText,
    this.jumpUrl,
    this.rid,
    this.emojiUrl,
  });

  factory DynRichTextNode.fromJson(Map<String, dynamic> json) {
    final emoji = json['emoji'] as Map<String, dynamic>?;
    return DynRichTextNode(
      type: json['type']?.toString(),
      text: json['text']?.toString() ?? json['orig_text']?.toString(),
      origText: json['orig_text']?.toString(),
      jumpUrl: json['jump_url']?.toString(),
      rid: json['rid']?.toString(),
      emojiUrl: emoji?['icon_url']?.toString(),
    );
  }
}

/// 附加模块（商品卡等）。
class DynAdditional {
  final String? type;
  final String? goodsHeadText;
  final List<DynGoodsItem> goodsItems;

  DynAdditional({this.type, this.goodsHeadText, this.goodsItems = const []});

  factory DynAdditional.fromJson(Map<String, dynamic> json) {
    final goods = json['goods'] as Map<String, dynamic>? ?? {};
    final rawItems = goods['items'] as List?;
    return DynAdditional(
      type: json['type']?.toString(),
      goodsHeadText: goods['head_text']?.toString(),
      goodsItems: rawItems
              ?.map((e) => DynGoodsItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}

/// 商品卡子项。
class DynGoodsItem {
  final String? id;
  final String? name;
  final String? cover;
  final String? price;
  final String? jumpUrl;

  DynGoodsItem({
    this.id,
    this.name,
    this.cover,
    this.price,
    this.jumpUrl,
  });

  factory DynGoodsItem.fromJson(Map<String, dynamic> json) {
    return DynGoodsItem(
      id: json['id']?.toString(),
      name: json['name']?.toString(),
      cover: json['cover']?.toString(),
      price: json['price']?.toString(),
      jumpUrl: json['jump_url']?.toString(),
    );
  }
}

/// 互动统计（点赞/转发/评论）。
class DynStat {
  final int? repost;
  final int? comment;
  final int? like;

  DynStat({this.repost, this.comment, this.like});

  factory DynStat.fromJson(Map<String, dynamic> json) {
    return DynStat(
      repost: _asInt((json['repost'] as Map<String, dynamic>?)?['count']),
      comment: _asInt((json['comment'] as Map<String, dynamic>?)?['count']),
      like: _asInt((json['like'] as Map<String, dynamic>?)?['count']),
    );
  }
}

int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

double? _asDouble(Object? value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

