import 'package:flutter/foundation.dart';

import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/models/user/user_info.dart';

/// 账户状态广播服务（移植自 PiliPlus `lib/services/account_service.dart`）。
///
/// WinWin 精简版：用 [ChangeNotifier] 替代 GetX 的 Rx<bool>，供 UI 通过
/// [AnimatedBuilder] / [ListenableBuilder] 监听登录态变化。
///
/// 持有当前用户信息 [userInfo]，登录后由 [LoginUtils.onLoginMain] 写入，
/// 登出时清空。启动时从 [Pref.userInfoCache] 恢复。
class AccountService extends ChangeNotifier {
  AccountService._();
  static final AccountService _instance = AccountService._();
  factory AccountService() => _instance;

  UserInfoModel? _userInfo;

  /// 当前用户信息（null 表示未登录或未加载）。
  UserInfoModel? get userInfo => _userInfo;

  /// 是否已登录。
  bool get isLogin =>
      (_userInfo != null && _userInfo!.isLogin == true) ||
      Accounts.main.isLogin;

  /// 头像 URL。
  String get face => _userInfo?.face ?? '';

  /// 启动时从缓存恢复。
  void restore(UserInfoModel? cached) {
    _userInfo = cached;
    notifyListeners();
  }

  /// 登录成功后写入用户信息并广播。
  void onLogin(UserInfoModel info) {
    _userInfo = info;
    notifyListeners();
  }

  /// 刷新用户信息（不触发重建如果数据相同）。
  void refresh(UserInfoModel info) {
    final old = _userInfo;
    _userInfo = info;
    if (old?.mid != info.mid || old?.vipStatus != info.vipStatus) {
      notifyListeners();
    }
  }

  /// 登出：清空用户信息并广播。
  void onLogout() {
    _userInfo = null;
    notifyListeners();
  }
}
