import 'package:flutter/widgets.dart';

import 'package:winwin/core/account/account_service.dart';
import 'package:winwin/pages/login/login_page.dart';

/// 登录守卫（移植自 PiliPlus 各页面的 `if (!Accounts.main.isLogin)` 守卫）。
///
/// 所有读取账户数据的入口（收藏夹、历史记录、稍后再看、关注按钮、
/// 个人中心头像/用户名等）在点击时都应先经过 [LoginGuard.requireLogin]，
/// 未登录则跳转到登录页，登录成功后继续执行原回调。
abstract final class LoginGuard {
  /// 检查登录态：
  ///   - 已登录 → 返回 true，调用方继续执行后续逻辑。
  ///   - 未登录 → 弹出登录页，返回 false，调用方应中止当前操作。
  ///
  /// 使用方式：
  /// ```dart
  /// onTap: () async {
  ///   if (!await LoginGuard.requireLogin(context)) return;
  ///   // 已登录，继续执行业务逻辑
  ///   Navigator.push(...);
  /// }
  /// ```
  static Future<bool> requireLogin(BuildContext context) async {
    if (AccountService().isLogin) return true;
    if (!context.mounted) return false;
    await showLoginPage(context);
    // 登录页关闭后再次检查登录态（用户可能登录成功也可能取消）。
    return AccountService().isLogin;
  }

  /// 同步版本的登录检查（不弹登录页），用于 UI 状态判断。
  /// 调用方仍需在点击时调用 [requireLogin] 走异步流程。
  static bool get isLoggedIn => AccountService().isLogin;
}
