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
  /// 推荐直播列表（`/xlive/web-interface/v1/second/getUserRecommend`）。
  ///
  /// [page] 从 1 开始。成功返回 [LiveRecommendData]，含直播卡片列表。
  /// 该 web 接口需 WBI 签名（w_rid/wts），否则触发风控 -352。
  static Future<LoadingState<LiveRecommendData>> liveRecommend({
    int page = 1,
    int pageSize = 30,
  }) async {
    try {
      final res = await Request().get<dynamic>(
        Api.liveList,
        queryParameters: await WbiSign.makSign({
          'page': page,
          'page_size': pageSize,
          'platform': 'web',
          'web_location': 444.8,
        }),
      );
      final data = res.data as Map<String, dynamic>;
      if (data['code'] == 0) {
        return Success(
          LiveRecommendData.fromJson(
            data['data'] as Map<String, dynamic>? ?? {},
          ),
        );
      }
      return Error(data['message']?.toString() ?? '获取直播列表失败');
    } on DioException catch (e) {
      return Error('获取直播列表失败：${e.message ?? e.type.name}');
    } catch (e) {
      return Error('获取直播列表失败：$e');
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

/// 直播卡片条目（推荐流）。
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
    return LiveItemModel(
      roomId: _asInt(json['roomid']),
      uid: _asInt(json['uid']),
      title: json['title']?.toString(),
      cover: _http2https(json['cover']?.toString() ?? json['pic']?.toString()),
      uname: json['uname']?.toString(),
      face: _http2https(json['face']?.toString()),
      online: _asInt(json['online'] ?? json['watched_show']?['num']),
      areaName: json['area_name']?.toString() ?? json['area_v2_name']?.toString(),
      isLiving: json['live_status'] == 1,
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
