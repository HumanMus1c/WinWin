import 'package:flutter/foundation.dart';

import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/core/demo/demo_overrides.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/models/user/user_info.dart';

/// 账户状态广播服务（移植自 PiliPlus `lib/services/account_service.dart`）。
///
/// WinWin 精简版：用 [ChangeNotifier] 替代 GetX 的 `Rx<bool>`，供 UI 通过
/// [AnimatedBuilder] / [ListenableBuilder] 监听登录态变化。
///
/// 持有当前用户信息 [userInfo]，登录后由 [LoginUtils.onLoginMain] 写入，
/// 登出时清空。启动时从 [Pref.userInfoCache] 恢复。
class AccountService extends ChangeNotifier {
  AccountService._() {
    // 演示模式开关变化时转发通知：已监听本服务的界面（个人页/导航栏）立即重建。
    Pref.demoModeNotifier.addListener(notifyListeners);
  }

  static final AccountService _instance = AccountService._();
  factory AccountService() => _instance;

  UserInfoModel? _userInfo;

  /// 当前用户信息（null 表示未登录或未加载）。
  UserInfoModel? get userInfo => _userInfo;

  /// 演示模式展示模型：仅替换头像（走程序默认图标）与昵称（程序名）。
  ///
  /// 其余字段（等级/硬币/经验/关注/粉丝/会员类型等）保留真实值，
  /// 供个人页"照常展示 + 演示期即时编辑"读取；mid 与 isLogin 原样保留
  /// （导航与功能不受影响）。
  ///
  /// 仅供展示读取，绝不写回 [Pref.userInfoCache] 等持久化路径。
  UserInfoModel? get displayUserInfo {
    final info = _userInfo;
    if (!Pref.demoMode || info == null) return info;
    return UserInfoModel(
      isLogin: info.isLogin,
      mid: info.mid,
      name: kDemoDisplayName,
      face: null,
      level: info.level,
      silence: info.silence,
      coins: info.coins,
      money: info.money,
      biliMid: info.biliMid,
      following: info.following,
      follower: info.follower,
      dynamicCount: info.dynamicCount,
      email: info.email,
      phone: info.phone,
      vipDueDate: info.vipDueDate,
      vipStatus: info.vipStatus,
      vipType: info.vipType,
      vipPayType: info.vipPayType,
      vipThemeType: info.vipThemeType,
      vipLabel: info.vipLabel,
      vipAvatarSub: info.vipAvatarSub,
      vipNicknameColor: info.vipNicknameColor,
      levelInfo: info.levelInfo,
    );
  }

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
