import 'package:dio/dio.dart';

import 'package:winwin/http/api.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/utils/wbi_sign.dart';

/// 直播 HTTP（移植自 PiliPlus `lib/http/live.dart`，精简为桌面端所需）。
///
/// 保留推荐直播列表、直播间基础信息两个接口，为后续 Phase 3 直播弹幕
/// 和 Phase 4 直播播放预留数据入口。
abstract final class LiveHttp {
  /// 推荐直播列表（使用免风控官方接口 `Api.liveRoomList`）。
  ///
  /// [page] 从 1 开始。成功返回 [LiveRecommendData]，含直播卡片列表。
  /// 原 web 接口 `Api.liveList` 强制校验设备指纹返回 -352，现切换至
  /// `/room/v1/Area/getRoomList?parent_area_id=0&sort_type=online`。
  static Future<LoadingState<LiveRecommendData>> liveRecommend({
    int page = 1,
    int pageSize = 30,
    int parentAreaId = 0,
  }) async {
    try {
      final res = await Request().get<dynamic>(
        Api.liveRoomList,
        queryParameters: {
          'parent_area_id': parentAreaId,
          'page': page,
          'page_size': pageSize,
          'sort_type': 'online',
        },
      );
      final data = res.data as Map<String, dynamic>;
      if (data['code'] == 0) {
        final rawData = data['data'];
        final List<dynamic> rawList = rawData is List
            ? rawData
            : ((rawData as Map<String, dynamic>?)?['list'] as List? ??
                const []);
        final items = rawList
            .map((e) => LiveItemModel.fromJson(e as Map<String, dynamic>))
            .toList();
        return Success(LiveRecommendData(list: items));
      }
      return Error(data['message']?.toString() ?? '获取直播列表失败');
    } on DioException catch (e) {
      return Error('获取直播列表失败：${e.message ?? e.type.name}');
    } catch (e) {
      return Error('获取直播列表失败：$e');
    }
  }

  /// 获取直播一级分区列表（免登录接口 `Api.liveRoomAreaList`）。
  static Future<LoadingState<List<LiveAreaItem>>> liveAreaList() async {
    try {
      final res = await Request().get<dynamic>(Api.liveRoomAreaList);
      final data = res.data as Map<String, dynamic>;
      if (data['code'] == 0) {
        final rawList = data['data'] as List<dynamic>? ?? const [];
        final areas = rawList
            .map((e) => LiveAreaItem.fromJson(e as Map<String, dynamic>))
            .where((e) => e.id > 0 && e.name.isNotEmpty)
            .toList();
        return Success(areas);
      }
      return Error(data['message']?.toString() ?? '获取直播分区失败');
    } on DioException catch (e) {
      return Error('获取直播分区失败：${e.message ?? e.type.name}');
    } catch (e) {
      return Error('获取直播分区失败：$e');
    }
  }

  /// 获取当前登录用户关注的主播正在直播列表（`Api.liveFollow`）。
  static Future<LoadingState<LiveFollowData>> liveFollow({
    int page = 1,
    int pageSize = 30,
  }) async {
    try {
      final res = await Request().get<dynamic>(
        Api.liveFollow,
        queryParameters: {
          'page': page,
          'page_size': pageSize,
          'ignoreRecord': 1,
          'hit_ab': true,
        },
      );
      final data = res.data as Map<String, dynamic>;
      if (data['code'] == 0) {
        final rawData = data['data'] as Map<String, dynamic>? ?? {};
        return Success(LiveFollowData.fromJson(rawData));
      }
      return Error(data['message']?.toString() ?? '获取关注直播失败');
    } on DioException catch (e) {
      return Error('获取关注直播失败：${e.message ?? e.type.name}');
    } catch (e) {
      return Error('获取关注直播失败：$e');
    }
  }

  /// 直播间信息（`/xlive/web-room/v1/index/getH5InfoByRoom`）。
  ///
  /// [roomId] 为直播间号。返回 [LiveRoomInfo]，含标题、主播、直播状态等。
  static Future<LoadingState<LiveRoomInfo>> roomInfo({required int roomId}) async {
    try {
      final res = await Request().get<dynamic>(
        Api.liveRoomInfoH5,
        queryParameters: {'room_id': roomId},
      );
      final data = res.data as Map<String, dynamic>;
      if (data['code'] == 0) {
        return Success(
          LiveRoomInfo.fromJson(
            data['data']?['room_info'] as Map<String, dynamic>? ?? {},
          ),
        );
      }
      return Error(data['message']?.toString() ?? '获取直播间信息失败');
    } on DioException catch (e) {
      return Error('获取直播间信息失败：${e.message ?? e.type.name}');
    } catch (e) {
      return Error('获取直播间信息失败：$e');
    }
  }

  /// 获取直播间播放推流地址（`/xlive/web-room/v2/index/getRoomPlayInfo`）。
  ///
  /// 返回 [LivePlayUrlData]，包含协议流列表与推流 URL 解析逻辑。
  static Future<LoadingState<LivePlayUrlData>> liveRoomPlayInfo({
    required int roomId,
    int? qn,
  }) async {
    try {
      final res = await Request().get<dynamic>(
        Api.liveRoomInfo,
        queryParameters: await WbiSign.makSign({
          'room_id': roomId,
          'protocol': '0,1',
          'format': '0,1,2',
          'codec': '0,1',
          'qn': ?qn,
          'platform': 'web',
          'ptype': 8,
          'dolby': 5,
          'panorama': 1,
          'web_location': 444.8,
        }),
      );
      final data = res.data as Map<String, dynamic>;
      if (data['code'] == 0) {
        final rawData = data['data'] as Map<String, dynamic>? ?? {};
        return Success(LivePlayUrlData.fromJson(rawData));
      }
      return Error(data['message']?.toString() ?? '获取直播播放流失败');
    } on DioException catch (e) {
      return Error('获取直播播放流失败：${e.message ?? e.type.name}');
    } catch (e) {
      return Error('获取直播播放流失败：$e');
    }
  }
}

/// 直播推流播放地址数据。
class LivePlayUrlData {
  final int? roomId;
  final int? liveStatus;
  final int? liveTime;
  final bool? isPortrait;
  final List<LiveStreamItem> streams;

  LivePlayUrlData({
    this.roomId,
    this.liveStatus,
    this.liveTime,
    this.isPortrait,
    this.streams = const [],
  });

  /// 是否开播中（liveStatus == 1）。
  bool get isLiving => liveStatus == 1;

  /// 提取最优播放地址（优先 FLV，其次 HLS）。
  String? get bestPlayUrl {
    if (streams.isEmpty) return null;
    // 1. 优先查找 http_stream (FLV)
    for (final s in streams) {
      if (s.protocolName == 'http_stream') {
        final url = s.firstUrl;
        if (url != null && url.isNotEmpty) return url;
      }
    }
    // 2. 其次查找 http_hls
    for (final s in streams) {
      if (s.protocolName == 'http_hls') {
        final url = s.firstUrl;
        if (url != null && url.isNotEmpty) return url;
      }
    }
    // 3. 兜底返回任意有效流
    for (final s in streams) {
      final url = s.firstUrl;
      if (url != null && url.isNotEmpty) return url;
    }
    return null;
  }

  factory LivePlayUrlData.fromJson(Map<String, dynamic> json) {
    final playurlInfo =
        json['playurl_info']?['playurl'] as Map<String, dynamic>?;
    final rawStream = playurlInfo?['stream'] as List?;
    final streams = rawStream
            ?.map((e) => LiveStreamItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [];

    return LivePlayUrlData(
      roomId: _asInt(json['room_id']),
      liveStatus: _asInt(json['live_status']),
      liveTime: _asInt(json['live_time']),
      isPortrait: json['is_portrait'] as bool?,
      streams: streams,
    );
  }
}

class LiveStreamItem {
  final String? protocolName;
  final List<LiveFormatItem> formats;

  LiveStreamItem({this.protocolName, this.formats = const []});

  String? get firstUrl {
    for (final f in formats) {
      for (final c in f.codecs) {
        if (c.baseUrl != null && c.urlInfo.isNotEmpty) {
          final host = c.urlInfo.first.host ?? '';
          final extra = c.urlInfo.first.extra ?? '';
          return '$host${c.baseUrl}$extra';
        }
      }
    }
    return null;
  }

  factory LiveStreamItem.fromJson(Map<String, dynamic> json) {
    final rawFormats = json['format'] as List?;
    return LiveStreamItem(
      protocolName: json['protocol_name']?.toString(),
      formats: rawFormats
              ?.map((e) => LiveFormatItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}

class LiveFormatItem {
  final String? formatName;
  final List<LiveCodecItem> codecs;

  LiveFormatItem({this.formatName, this.codecs = const []});

  factory LiveFormatItem.fromJson(Map<String, dynamic> json) {
    final rawCodecs = json['codec'] as List?;
    return LiveFormatItem(
      formatName: json['format_name']?.toString(),
      codecs: rawCodecs
              ?.map((e) => LiveCodecItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}

class LiveCodecItem {
  final String? codecName;
  final int? currentQn;
  final List<int> acceptQn;
  final String? baseUrl;
  final List<LiveUrlInfoItem> urlInfo;

  LiveCodecItem({
    this.codecName,
    this.currentQn,
    this.acceptQn = const [],
    this.baseUrl,
    this.urlInfo = const [],
  });

  factory LiveCodecItem.fromJson(Map<String, dynamic> json) {
    final rawAcceptQn = json['accept_qn'] as List?;
    final rawUrlInfo = json['url_info'] as List?;
    return LiveCodecItem(
      codecName: json['codec_name']?.toString(),
      currentQn: _asInt(json['current_qn']),
      acceptQn: rawAcceptQn?.map((e) => _asInt(e) ?? 0).toList() ?? const [],
      baseUrl: json['base_url']?.toString(),
      urlInfo: rawUrlInfo
              ?.map((e) => LiveUrlInfoItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}

class LiveUrlInfoItem {
  final String? host;
  final String? extra;

  LiveUrlInfoItem({this.host, this.extra});

  factory LiveUrlInfoItem.fromJson(Map<String, dynamic> json) {
    return LiveUrlInfoItem(
      host: json['host']?.toString(),
      extra: json['extra']?.toString(),
    );
  }
}

/// 直播分区条目（一级/二级父子分区）。
class LiveAreaItem {
  final int id;
  final String name;
  final String? pic;
  final List<LiveAreaItem> children;

  const LiveAreaItem({
    required this.id,
    required this.name,
    this.pic,
    this.children = const [],
  });

  factory LiveAreaItem.fromJson(Map<String, dynamic> json) {
    final rawList = json['list'] as List<dynamic>?;
    return LiveAreaItem(
      id: _asInt(json['id']) ?? 0,
      name: json['name']?.toString() ?? '',
      pic: _http2https(json['pic']?.toString()),
      children: rawList != null
          ? rawList
              .map((e) => LiveAreaItem.fromJson(e as Map<String, dynamic>))
              .toList()
          : const [],
    );
  }

  /// 预置的官方核心直播父分区列表（用于网络异常或首屏即时呈现兜底）。
  static const List<LiveAreaItem> defaultAreas = [
    LiveAreaItem(id: 2, name: '网游'),
    LiveAreaItem(id: 3, name: '手游'),
    LiveAreaItem(id: 6, name: '单机游戏'),
    LiveAreaItem(id: 1, name: '娱乐'),
    LiveAreaItem(id: 5, name: '电台'),
    LiveAreaItem(id: 9, name: '虚拟主播'),
    LiveAreaItem(id: 14, name: '聊天室'),
    LiveAreaItem(id: 10, name: '生活'),
    LiveAreaItem(id: 11, name: '知识'),
    LiveAreaItem(id: 13, name: '赛事'),
    LiveAreaItem(id: 15, name: '互动玩法'),
    LiveAreaItem(id: 16, name: '购物'),
  ];
}

/// 关注直播列表数据包。
class LiveFollowData {
  final List<LiveItemModel> list;
  final int liveCount;
  final int count;

  LiveFollowData({
    this.list = const [],
    this.liveCount = 0,
    this.count = 0,
  });

  factory LiveFollowData.fromJson(Map<String, dynamic> json) {
    final rawList = json['list'] as List<dynamic>? ?? const [];
    final list = rawList
        .where((e) {
          if (e is! Map<String, dynamic>) return false;
          final status = e['live_status'];
          return status == null || status == 1;
        })
        .map((e) => LiveItemModel.fromJson(e as Map<String, dynamic>))
        .toList();
    return LiveFollowData(
      list: list,
      liveCount: _asInt(json['live_count']) ?? list.length,
      count: _asInt(json['count']) ?? list.length,
    );
  }
}

/// 推荐直播列表数据。
class LiveRecommendData {
  final List<LiveItemModel> list;

  LiveRecommendData({this.list = const []});

  factory LiveRecommendData.fromJson(Map<String, dynamic> json) {
    return LiveRecommendData(
      list: (json['list'] as List?)
              ?.map(
                (e) => LiveItemModel.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          <LiveItemModel>[],
    );
  }
}

/// 直播卡片条目（推荐流 / 关注流 / 分区流通用）。
class LiveItemModel {
  final int? roomId;
  final int? uid;
  final String? title;
  final String? cover;
  final String? uname;
  final String? face;
  final int? online;
  final String? areaName;
  final bool isLiving;

  LiveItemModel({
    this.roomId,
    this.uid,
    this.title,
    this.cover,
    this.uname,
    this.face,
    this.online,
    this.areaName,
    this.isLiving = false,
  });

  factory LiveItemModel.fromJson(Map<String, dynamic> json) {
    final liveStatus = json['live_status'];
    final rawCover = json['cover']?.toString();
    final rawUserCover = json['user_cover']?.toString();
    final rawRoomCover = json['room_cover']?.toString();
    final rawPic = json['pic']?.toString();
    final effectiveCover = (rawCover != null && rawCover.isNotEmpty)
        ? rawCover
        : (rawUserCover != null && rawUserCover.isNotEmpty)
            ? rawUserCover
            : (rawRoomCover != null && rawRoomCover.isNotEmpty)
                ? rawRoomCover
                : rawPic;

    return LiveItemModel(
      roomId: _asInt(json['roomid'] ?? json['room_id']),
      uid: _asInt(json['uid']),
      title: json['title']?.toString(),
      cover: _http2https(effectiveCover),
      uname: json['uname']?.toString(),
      face: _http2https(json['face']?.toString()),
      online: _asInt(json['online'] ?? json['watched_show']?['num']),
      areaName: json['area_name']?.toString() ?? json['area_v2_name']?.toString(),
      isLiving: liveStatus == null || liveStatus == 1,
    );
  }
}

/// 直播间信息（room_info 节点）。
class LiveRoomInfo {
  final int? roomId;
  final int? uid;
  final String? title;
  final String? cover;
  final String? uname;
  final String? face;
  final String? areaName;
  final int? liveStatus;
  final int? online;

  LiveRoomInfo({
    this.roomId,
    this.uid,
    this.title,
    this.cover,
    this.uname,
    this.face,
    this.areaName,
    this.liveStatus,
    this.online,
  });

  /// 是否正在直播（live_status==1）。
  bool get isLiving => liveStatus == 1;

  factory LiveRoomInfo.fromJson(Map<String, dynamic> json) {
    return LiveRoomInfo(
      roomId: _asInt(json['room_id']),
      uid: _asInt(json['uid']),
      title: json['title']?.toString(),
      cover: _http2https(json['cover']?.toString()),
      uname: json['uname']?.toString(),
      face: _http2https(json['face']?.toString()),
      areaName: json['area_name']?.toString() ??
          json['area_v2_name']?.toString(),
      liveStatus: _asInt(json['live_status']),
      online: _asInt(json['online']),
    );
  }
}

String? _http2https(String? url) {
  if (url == null || url.isEmpty) return null;
  if (url.startsWith('//')) return 'https:$url';
  if (url.startsWith('http://')) return 'https://${url.substring(7)}';
  return url;
}

int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}
