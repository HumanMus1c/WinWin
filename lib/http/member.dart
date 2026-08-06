import 'package:dio/dio.dart';

import 'package:winwin/common/constants.dart';
import 'package:winwin/http/api.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/http/loading_state.dart';

/// 用户空间相关 HTTP（移植自 PiliPlus `lib/http/member.dart`，精简）。
///
/// 仅保留 WinWin 所需的「空间信息 + 投稿视频列表」两个接口。
abstract final class MemberHttp {
  /// 用户空间信息（APP 端 `/x/v2/space`）。
  ///
  /// 返回 [MemberSpaceData]，含用户卡片（头像/名字/签名/粉丝数等）。
  static Future<LoadingState<MemberSpaceData>> space({required int mid}) async {
    final params = {
      'build': 8430300,
      'version': '8.43.0',
      'c_locale': 'zh_CN',
      'channel': 'master',
      'mobi_app': 'android',
      'platform': 'android',
      's_locale': 'zh_CN',
      'statistics': Constants.statisticsApp,
      'vmid': mid,
    };
    final res = await Request().get(
      Api.space,
      queryParameters: params,
      options: Options(
        headers: {
          'bili-http-engine': 'cronet',
          'user-agent': Constants.userAgentApp,
        },
      ),
    );
    if (res.data['code'] == 0) {
      return Success(
        MemberSpaceData.fromJson(res.data['data'] ?? <String, dynamic>{}),
      );
    } else {
      return Error(res.data['message']);
    }
  }

  /// 用户投稿视频列表（APP 端游标分页 `/x/v2/space/archive/cursor`）。
  static Future<LoadingState<MemberArchiveData>> spaceArchive({
    required int mid,
    String? cursor,
  }) async {
    final params = {
      'vmid': mid,
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      'build': 8430300,
      'c_locale': 'zh_CN',
      'channel': 'master',
      'mobi_app': 'android',
      'platform': 'android',
      's_locale': 'zh_CN',
      'statistics': Constants.statisticsApp,
    };
    final res = await Request().get(
      Api.spaceArchive,
      queryParameters: params,
      options: Options(
        headers: {
          'bili-http-engine': 'cronet',
          'user-agent': Constants.userAgentApp,
        },
      ),
    );
    if (res.data['code'] == 0) {
      return Success(
        MemberArchiveData.fromJson(res.data['data'] ?? <String, dynamic>{}),
      );
    } else {
      return Error(res.data['message']);
    }
  }
}

/// 用户空间数据（`/x/v2/space` 响应）。
class MemberSpaceData {
  final MemberCard? card;
  final MemberArchiveData? archives;

  MemberSpaceData({this.card, this.archives});

  factory MemberSpaceData.fromJson(Map<String, dynamic> json) {
    return MemberSpaceData(
      card: json['card'] is Map<String, dynamic>
          ? MemberCard.fromJson(json['card'])
          : null,
      archives: json['archives'] is Map<String, dynamic>
          ? MemberArchiveData.fromJson(json['archives'])
          : null,
    );
  }
}

/// 用户卡片信息。
class MemberCard {
  final int? mid;
  final String? name;
  final String? face;
  final String? sign;
  final int? level;
  final int? fans;
  final int? following;
  final MemberVip? vip;
  final MemberOfficial? officialVerify;

  MemberCard({
    this.mid,
    this.name,
    this.face,
    this.sign,
    this.level,
    this.fans,
    this.following,
    this.vip,
    this.officialVerify,
  });

  factory MemberCard.fromJson(Map<String, dynamic> json) {
    return MemberCard(
      mid: _asInt(json['mid']),
      name: json['name'] as String?,
      face: json['face'] as String?,
      sign: json['sign'] as String?,
      level: _asInt(json['level']),
      fans: _asInt(json['fans']),
      following: _asInt(json['attention']),
      vip: json['vip'] is Map<String, dynamic>
          ? MemberVip.fromJson(json['vip'])
          : null,
      officialVerify: json['official_verify'] is Map<String, dynamic>
          ? MemberOfficial.fromJson(json['official_verify'])
          : null,
    );
  }
}

class MemberVip {
  final int? type;
  final int? status;

  MemberVip({this.type, this.status});

  factory MemberVip.fromJson(Map<String, dynamic> json) {
    return MemberVip(
      type: _asInt(json['type']),
      status: _asInt(json['status']),
    );
  }

  bool get isVip => status != null && status! > 0;
}

class MemberOfficial {
  /// -1=无认证，0=个人认证，1=机构认证。
  final int? type;

  MemberOfficial({this.type});

  factory MemberOfficial.fromJson(Map<String, dynamic> json) {
    return MemberOfficial(type: _asInt(json['type']));
  }
}

/// 投稿视频列表数据（游标分页）。
class MemberArchiveData {
  final List<MemberVideoItem> list;
  final bool? isEnd;

  MemberArchiveData({this.list = const [], this.isEnd});

  factory MemberArchiveData.fromJson(Map<String, dynamic> json) {
    final itemJson = json['item'] as List?;
    return MemberArchiveData(
      list: itemJson
              ?.map((e) => MemberVideoItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          <MemberVideoItem>[],
      isEnd: json['is_end'] as bool?,
    );
  }
}

/// 投稿视频条目。
class MemberVideoItem {
  final String? bvid;
  final String? title;
  final String? pic;
  final int? play;
  final int? danmaku;
  final int? duration;
  final int? pubdate;
  final String? upName;

  MemberVideoItem({
    this.bvid,
    this.title,
    this.pic,
    this.play,
    this.danmaku,
    this.duration,
    this.pubdate,
    this.upName,
  });

  factory MemberVideoItem.fromJson(Map<String, dynamic> json) {
    return MemberVideoItem(
      bvid: json['bvid'] as String?,
      title: json['title'] as String?,
      pic: json['cover'] as String? ?? json['pic'] as String?,
      play: _asInt(json['play']),
      danmaku: _asInt(json['danmaku']),
      duration: _asInt(json['duration']),
      pubdate: _asInt(json['pubdate']),
      upName: json['owner']?['name'] as String?,
    );
  }
}

int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}
