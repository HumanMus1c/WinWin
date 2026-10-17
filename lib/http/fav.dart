import 'package:dio/dio.dart';

import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/http/api.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/response_map.dart';
import 'package:winwin/models/fav/fav_models.dart';

/// 收藏夹 HTTP（移植自 PiliPlus `lib/http/fav.dart`，精简为 WinWin 所需接口）。
abstract final class FavHttp {
  /// 我的收藏夹列表（分页）。
  static Future<LoadingState<FavFolderData>> userFavFolder({
    required int pn,
    int ps = 20,
    required int mid,
  }) async {
    try {
      final res = await Request().get<dynamic>(
        Api.userFavFolder,
        queryParameters: {'pn': pn, 'ps': ps, 'up_mid': mid},
      );
      final data = res.data;
      if (data is Map<String, dynamic>) {
        if (data['code'] == 0) {
          final body = data['data'] as Map<String, dynamic>?;
          return Success(body != null ? FavFolderData.fromJson(body) : FavFolderData(count: 0, list: []));
        }
        return Error(data['message']?.toString() ?? '获取收藏夹失败');
      }
      return const Error('获取收藏夹失败：返回数据格式异常');
    } catch (e) {
      return Error('获取收藏夹失败：$e');
    }
  }

  /// 全部收藏夹（用于收藏面板，不分页）。
  static Future<LoadingState<FavFolderData>> allFavFolders(int mid) async {
    try {
      final res = await Request().get<dynamic>(
        Api.favFolder,
        queryParameters: {'up_mid': mid},
      );
      final data = res.data;
      if (data is Map<String, dynamic>) {
        if (data['code'] == 0) {
          final body = data['data'] as Map<String, dynamic>?;
          return Success(body != null ? FavFolderData.fromJson(body) : FavFolderData(count: 0, list: []));
        }
        return Error(data['message']?.toString() ?? '获取收藏夹失败');
      }
      return const Error('获取收藏夹失败：返回数据格式异常');
    } catch (e) {
      return Error('获取收藏夹失败：$e');
    }
  }

  /// 查看视频被收藏在哪些夹（用于面板初始勾选）。
  static Future<LoadingState<FavFolderData>> videoInFolder({
    required int mid,
    required int rid,
    int type = 2,
  }) async {
    try {
      final res = await Request().get<dynamic>(
        Api.favFolder,
        queryParameters: {'up_mid': mid, 'rid': rid, 'type': type},
      );
      final data = res.data;
      if (data is Map<String, dynamic>) {
        if (data['code'] == 0) {
          final body = data['data'] as Map<String, dynamic>?;
          return Success(body != null ? FavFolderData.fromJson(body) : FavFolderData(count: 0, list: []));
        }
        return Error(data['message']?.toString() ?? '查询失败');
      }
      return const Error('查询失败：返回数据格式异常');
    } catch (e) {
      return Error('查询失败：$e');
    }
  }

  /// 收藏夹详情（含视频列表）。
  static Future<LoadingState<FavDetailData>> favDetail({
    required int mediaId,
    int pn = 1,
    int ps = 20,
    String keyword = '',
    String order = 'mtime',
    int type = 0,
  }) async {
    try {
      final res = await Request().get<dynamic>(
        Api.favResourceList,
        queryParameters: {
          'media_id': mediaId,
          'pn': pn,
          'ps': ps,
          'keyword': keyword,
          'order': order,
          'type': type,
          'tid': 0,
          'platform': 'web',
        },
      );
      final data = res.data;
      if (data is Map<String, dynamic>) {
        if (data['code'] == 0) {
          final body = data['data'] as Map<String, dynamic>?;
          return Success(body != null ? FavDetailData.fromJson(body) : FavDetailData(medias: []));
        }
        return Error(data['message']?.toString() ?? '获取收藏夹详情失败');
      }
      return const Error('获取收藏夹详情失败：返回数据格式异常');
    } catch (e) {
      return Error('获取收藏夹详情失败：$e');
    }
  }

  /// 收藏/取消收藏视频（支持批量多选收藏夹）。
  ///
  /// [resources] 格式 `aid:type`（UGC 视频 type=2），多个逗号分隔。
  /// [addIds] / [delIds] 为逗号分隔的 media_id 列表。
  static Future<LoadingState<void>> favVideo({
    required String resources,
    String? addIds,
    String? delIds,
  }) async {
    try {
      final res = await Request().post<dynamic>(
        Api.favVideo,
        data: {
          'resources': resources,
          'add_media_ids': addIds ?? '',
          'del_media_ids': delIds ?? '',
          'csrf': Accounts.main.csrf,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final data = asJsonMap(res.data);
      if (data['code'] == 0) {
        return const Success(null);
      }
      return Error(data['message']?.toString() ?? '操作失败');
    } catch (e) {
      return Error('操作失败：$e');
    }
  }

  /// 取消收藏（从所有夹移除）。
  static Future<LoadingState<void>> unfavAll({
    required int rid,
    int type = 2,
  }) async {
    try {
      final res = await Request().post<dynamic>(
        Api.unfavAll,
        data: {
          'rid': rid,
          'type': type,
          'csrf': Accounts.main.csrf,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final data = asJsonMap(res.data);
      if (data['code'] == 0) return const Success(null);
      return Error(data['message']?.toString() ?? '取消收藏失败');
    } catch (e) {
      return Error('取消收藏失败：$e');
    }
  }

  /// 创建/编辑收藏夹。
  static Future<LoadingState<FavFolderInfo>> addOrEditFolder({
    required bool isAdd,
    int? mediaId,
    required String title,
    required int privacy,
    String cover = '',
    String intro = '',
  }) async {
    try {
      final res = await Request().post<dynamic>(
        isAdd ? Api.addFolder : Api.editFolder,
        data: {
          'title': title,
          'intro': intro,
          'privacy': privacy,
          'cover': cover.isNotEmpty ? Uri.encodeFull(cover) : cover,
          'csrf': Accounts.main.csrf,
          'media_id': ?mediaId,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final data = asJsonMap(res.data);
      if (data['code'] == 0) {
        return Success(FavFolderInfo.fromJson(data['data'] as Map<String, dynamic>));
      }
      return Error(data['message']?.toString() ?? '操作失败');
    } catch (e) {
      return Error('操作失败：$e');
    }
  }

  /// 删除收藏夹。
  static Future<LoadingState<void>> deleteFolder(int mediaId) async {
    try {
      final res = await Request().post<dynamic>(
        Api.deleteFolder,
        data: {
          'media_ids': mediaId,
          'platform': 'web',
          'csrf': Accounts.main.csrf,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final data = asJsonMap(res.data);
      if (data['code'] == 0) return const Success(null);
      return Error(data['message']?.toString() ?? '删除失败');
    } catch (e) {
      return Error('删除失败：$e');
    }
  }
}
