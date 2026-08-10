import 'package:dio/dio.dart';

import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/http/api.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/models/user/user_info.dart';

/// 用户信息 HTTP（移植自 PiliPlus `lib/http/user.dart` 的 userInfo 部分）。
abstract final class UserHttp {
  /// 获取当前登录用户信息（`/x/web-interface/nav`，web 端 cookie 鉴权）。
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

  /// app 端获取当前登录用户信息（`/x/v2/account/myinfo`，access_key 鉴权）。
  ///
  /// 作为 [userInfo] 失败时的回退方案：TV QR 登录返回的 cookie 可能无法被
  /// web 端 `/x/web-interface/nav` 接口接受（返回 isLogin=false 或 -101），
  /// 但 `access_token` 始终可以用于 app 端接口获取用户基本信息。
  ///
  /// 必须传非空 queryParameters 触发 AccountManager 的 app 端签名流程
  /// （添加 access_key + appkey + ts + sign）。
  static Future<LoadingState<UserInfoModel>> userInfoApp() async {
    try {
      final res = await Request().get<dynamic>(
        Api.userInfoApp,
        queryParameters: const {'platform': 'android'},
      );
      final data = res.data as Map<String, dynamic>;
      if (data['code'] == 0) {
        final raw = data['data'] as Map<String, dynamic>;
        // app 端响应不含 isLogin 字段，由调用方在确认登录后置为 true。
        raw['isLogin'] = true;
        return Success(UserInfoModel.fromJson(raw));
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
