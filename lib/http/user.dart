import 'package:dio/dio.dart';

import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/http/api.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/models/user/user_info.dart';

/// 用户信息 HTTP（移植自 PiliPlus `lib/http/user.dart` 的 userInfo 部分）。
abstract final class UserHttp {
  /// 获取当前登录用户信息（`/x/web-interface/nav`）。
  ///
  /// 含会员权限字段（vipStatus / vipType），用于会员识别与 UI 展示。
  static Future<LoadingState<UserInfoModel>> userInfo() async {
    try {
      final res = await Request().get<dynamic>(Api.userInfo);
      final data = res.data as Map<String, dynamic>;
      if (data['code'] == 0) {
        return Success(UserInfoModel.fromJson(data['data'] as Map<String, dynamic>));
      } else {
        return Error(data['message']?.toString() ?? '获取用户信息失败');
      }
    } on DioException catch (e) {
      return Error('获取用户信息失败：${e.message ?? e.type.name}');
    } catch (e) {
      return Error('获取用户信息失败：$e');
    }
  }

  /// 用户关系统计（关注/粉丝/动态数）。
  static Future<LoadingState<Map<String, int>>> userStat({int? mid}) async {
    try {
      final res = await Request().get<dynamic>(
        Api.userStatOwner,
        queryParameters: mid == null ? null : {'mid': mid},
      );
      final data = res.data as Map<String, dynamic>;
      if (data['code'] == 0) {
        final d = data['data'] as Map<String, dynamic>;
        return Success({
          'following': d['following'] as int? ?? 0,
          'follower': d['follower'] as int? ?? 0,
          'dynamic_count': d['dynamic_count'] as int? ?? 0,
        });
      } else {
        return Error(data['message']?.toString() ?? '获取统计失败');
      }
    } catch (e) {
      return Error('获取统计失败：$e');
    }
  }

  /// 登出（`/login/exit/v2`）。
  static Future<bool> logout() async {
    try {
      await Request().post<dynamic>(
        Api.logout,
        data: {'biliCSRF': Accounts.main.csrf},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
