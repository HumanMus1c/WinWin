import 'package:dio/dio.dart';

import 'package:winwin/http/api.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/http/loading_state.dart';

/// 动态流 HTTP（移植自 PiliPlus `lib/http/dynamic.dart`，精简为桌面端所需）。
///
/// 仅保留关注动态流、单条动态详情、用户空间动态三个接口。
/// 数据模型按 WinWin 实际渲染需要提取关键字段，不保留完整 modules 结构。
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
          'features': 'itemOpusStyle',
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
          'features': 'itemOpusStyle',
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
    return DynFeedData(
      items: rawItems
              ?.map((e) => DynItemModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          <DynItemModel>[],
      hasMore: json['has_more'] == true,
      offset: json['offset']?.toString() ?? '',
    );
  }
}

/// 单条动态。
///
/// 仅提取 WinWin 渲染所需字段：动态 id、类型、作者、视频信息（AV 类型动态）。
/// 其他类型动态（专栏/图片等）保留原始 raw 供按需解析。
class DynItemModel {
  /// 动态 id 字符串。
  final String id;
  /// 动态类型（DYNAMIC_TYPE_AV / DYNAMIC_TYPE_DRAW / DYNAMIC_TYPE_WORD 等）。
  final String type;
  /// 作者信息。
  final DynAuthor? author;
  /// 视频信息（仅 DYNAMIC_TYPE_AV 类型存在）。
  final DynArchive? archive;
  /// 文本描述（动态正文）。
  final String? text;
  /// 发布时间（Unix 时间戳，秒）。
  final int? pubTs;

  DynItemModel({
    required this.id,
    required this.type,
    this.author,
    this.archive,
    this.text,
    this.pubTs,
  });

  /// 是否为视频动态。
  bool get isVideo => type == 'DYNAMIC_TYPE_AV';

  factory DynItemModel.fromJson(Map<String, dynamic> json) {
    final modules = json['modules'] as Map<String, dynamic>? ?? {};
    final moduleAuthor =
        modules['module_author'] as Map<String, dynamic>? ?? {};
    final moduleDynamic =
        modules['module_dynamic'] as Map<String, dynamic>? ?? {};
    final desc = moduleDynamic['desc'] as Map<String, dynamic>? ?? {};
    final major = moduleDynamic['major'] as Map<String, dynamic>? ?? {};

    return DynItemModel(
      id: json['id_str']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      author: DynAuthor.fromJson(moduleAuthor),
      archive: DynArchive.fromMajor(major),
      text: desc['text']?.toString(),
      pubTs: _asInt(moduleAuthor['pub_ts'] ?? moduleAuthor['pub_action']),
    );
  }
}

/// 动态作者信息。
class DynAuthor {
  final int? mid;
  final String? name;
  final String? face;

  DynAuthor({this.mid, this.name, this.face});

  factory DynAuthor.fromJson(Map<String, dynamic> json) {
    return DynAuthor(
      mid: _asInt(json['mid']),
      name: json['name']?.toString(),
      face: json['face']?.toString(),
    );
  }
}

/// 动态内嵌的视频稿件信息（MAJOR_TYPE_ARCHIVE）。
class DynArchive {
  final String? bvid;
  final String? title;
  final String? cover;
  final String? durationText;
  final int? play;
  final int? danmaku;

  DynArchive({
    this.bvid,
    this.title,
    this.cover,
    this.durationText,
    this.play,
    this.danmaku,
  });

  /// 从 major 节点解析：major.archive 为视频稿件。
  factory DynArchive.fromMajor(Map<String, dynamic> major) {
    if (major['type'] != 'MAJOR_TYPE_ARCHIVE') return DynArchive();
    final archive = major['archive'] as Map<String, dynamic>? ?? {};
    return DynArchive(
      bvid: archive['bvid']?.toString(),
      title: archive['title']?.toString(),
      cover: archive['cover']?.toString(),
      durationText: archive['duration_text']?.toString(),
      play: _asInt(archive['play']),
      danmaku: _asInt(archive['danmaku']),
    );
  }
}

int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}
