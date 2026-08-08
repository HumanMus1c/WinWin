import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:winwin/core/account/account_service.dart';
import 'package:winwin/core/account/login_guard.dart';
import 'package:winwin/core/account/login_utils.dart';
import 'package:winwin/models/user/user_info.dart';
import 'package:winwin/pages/fav/fav_page.dart';
import 'package:winwin/pages/history/history_page.dart';
import 'package:winwin/pages/login/login_page.dart';
import 'package:winwin/pages/setting/setting_page.dart';
import 'package:winwin/pages/toview/toview_page.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/app_components.dart';

/// Profile page — ported from BiliPai's ProfileScreen.
///
/// Phase 7.8：重构为 [CustomScrollView] + [SliverToBoxAdapter] + [ClipRRect]
/// 圆角内容卡片向上覆盖壁纸 20dp（BiliPai 风格）。三风格自适应：使用
/// [AppGroup] / [AppListItem] 替换原 IOSGroup，按 [UiStyle] 切换外观。
///
/// 读取 [AccountService] 真实用户数据：
///   - 未登录：头像/用户名显示「点击登录」占位，点击进入登录流程
///   - 已登录：显示头像、昵称、等级、会员标识、关注/粉丝/动态/硬币数据
///
/// 所有读取账户数据的入口（收藏/历史/稍后再看/消息/账号切换）均经过
/// [LoginGuard.requireLogin] 守卫，未登录时跳转登录页。
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    AccountService().addListener(_onAccountChanged);
  }

  @override
  void dispose() {
    AccountService().removeListener(_onAccountChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onAccountChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final service = AccountService();
    final info = service.userInfo;
    final isLogin = service.isLogin;
    final theme = Theme.of(context);
    return Scaffold(
      body: Stack(
        children: [
          // ── 壁纸背景（渐变，固定不滚动） ──
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment(0, 0.5),
                colors: [
                  biliPink.withValues(alpha: 0.8),
                  theme.scaffoldBackgroundColor,
                ],
              ),
            ),
          ),
          // ── 滚动内容（圆角卡片向上覆盖壁纸 20dp） ──
          CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // 顶部留白：壁纸可见区域（用户信息悬浮于壁纸之上）
              const SliverToBoxAdapter(
                child: SizedBox(height: 120),
              ),
              // 用户信息区（透明背景，悬浮于壁纸）
              SliverToBoxAdapter(
                child: _UserInfoSection(info: info, isLogin: isLogin),
              ),
              // 数据统计区
              SliverToBoxAdapter(
                child: _StatsSection(info: info, isLogin: isLogin),
              ),
              // 圆角内容卡片（向上覆盖壁纸 20dp）
              SliverToBoxAdapter(
                child: _ContentCard(
                  info: info,
                  isLogin: isLogin,
                  onGuarded: _guarded,
                  onLogout: _onLogout,
                ),
              ),
              const SliverToBoxAdapter(
                child: SizedBox(height: 120),
              ),
            ],
          ),
          // ── 顶栏（居中标题） ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: SizedBox(
                height: 56,
                child: Center(
                  child: Text(
                    '我的',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 登录守卫：未登录→登录页；已登录→执行回调。
  Future<void> _guarded(
    BuildContext context,
    void Function(BuildContext) onLoggedIn,
  ) async {
    if (!await LoginGuard.requireLogin(context)) return;
    if (!mounted) return;
    onLoggedIn(context);
  }

  Future<void> _onLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出当前账号吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // 走标准登出流程：清缓存 + 广播 UI。
    await LoginUtils.onLogoutMain();
  }
}

/// 圆角内容卡片 — 向上覆盖壁纸 20dp（BiliPai 风格）。
///
/// 顶部 20dp 圆角，背景为 scaffoldBackgroundColor，包含所有服务入口列表。
/// 使用 [AppGroup] / [AppListItem] 实现三风格自适应。
class _ContentCard extends StatelessWidget {
  const _ContentCard({
    required this.info,
    required this.isLogin,
    required this.onGuarded,
    required this.onLogout,
  });

  final UserInfoModel? info;
  final bool isLogin;
  final Future<void> Function(BuildContext, void Function(BuildContext)) onGuarded;
  final Future<void> Function(BuildContext) onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Transform.translate(
      // 向上偏移 20dp，使圆角卡片覆盖壁纸
      offset: const Offset(0, -20),
      child: Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(Style.radiusXl),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: Style.md),
            // 服务列表
            AppGroup(
              margin: const EdgeInsets.symmetric(horizontal: Style.lg),
              children: [
                AppListItem(
                  icon: Icons.download,
                  title: '离线缓存',
                  iconTint: iosBlue,
                  onTap: () => onGuarded(context, (_) {}),
                ),
                AppListItem(
                  icon: Icons.history,
                  title: '历史记录',
                  iconTint: iosBlue,
                  onTap: () => onGuarded(context, showHistoryPage),
                ),
                AppListItem(
                  icon: Icons.bookmark,
                  title: '我的收藏',
                  iconTint: iosYellow,
                  onTap: () => onGuarded(context, showFavPage),
                ),
                AppListItem(
                  icon: Icons.watch_later,
                  title: '稍后再看',
                  iconTint: iosGreen,
                  onTap: () => onGuarded(context, showToviewPage),
                ),
                AppListItem(
                  icon: Icons.message,
                  title: '消息中心',
                  iconTint: iosPink,
                  onTap: () => onGuarded(context, (_) {}),
                ),
              ],
            ),
            const SizedBox(height: Style.md),
            AppGroup(
              margin: const EdgeInsets.symmetric(horizontal: Style.lg),
              children: [
                AppListItem(
                  icon: Icons.swap_horiz,
                  title: '账号切换',
                  iconTint: iosBlue,
                  onTap: () => onGuarded(context, (_) {}),
                ),
                if (isLogin)
                  AppListItem(
                    icon: Icons.logout,
                    title: '退出登录',
                    iconTint: Colors.red,
                    onTap: () => onLogout(context),
                  ),
              ],
            ),
            const SizedBox(height: Style.md),
            AppGroup(
              margin: const EdgeInsets.symmetric(horizontal: Style.lg),
              children: [
                AppListItem(
                  icon: Icons.settings,
                  title: '设置',
                  iconTint: iosBlue,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SettingPage(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Style.lg),
          ],
        ),
      ),
    );
  }
}

/// 用户信息区：未登录显示「点击登录」占位，已登录显示真实数据。
class _UserInfoSection extends StatelessWidget {
  final UserInfoModel? info;
  final bool isLogin;

  const _UserInfoSection({required this.info, required this.isLogin});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Style.xl, vertical: Style.lg),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!isLogin) showLoginPage(context);
        },
        child: Row(
          children: [
            // Avatar (72px circle)
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: isLogin
                    ? null
                    : LinearGradient(colors: [biliPink, biliPink.withValues(alpha: 0.7)]),
                border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: isLogin && (info?.face?.isNotEmpty ?? false)
                  ? CachedNetworkImage(
                      imageUrl: info!.face!,
                      placeholder: (_, __) => const ColoredBox(
                        color: Colors.grey,
                        child: SizedBox.expand(),
                      ),
                      errorWidget: (_, __, ___) => const Center(
                        child: Icon(Icons.person, color: Colors.white, size: 32),
                      ),
                      fit: BoxFit.cover,
                    )
                  : const Icon(Icons.person, color: Colors.white, size: 32),
            ),
            const SizedBox(width: Style.lg),
            // Name + badges
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isLogin ? (info?.name ?? '未命名用户') : '点击登录',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (isLogin) ...[
                    Row(
                      children: [
                        // Level badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: biliPink,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'LV ${info?.levelInfo?.currentLevel ?? info?.level ?? 0}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // VIP badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: (info?.isVip ?? false)
                                ? biliPink
                                : theme.colorScheme.surfaceContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            (info?.isYearVip ?? false)
                                ? '年度大会员'
                                : (info?.isVip ?? false)
                                    ? '大会员'
                                    : '正式会员',
                            style: TextStyle(
                              color: (info?.isVip ?? false)
                                  ? Colors.white
                                  : theme.colorScheme.onSurfaceVariant,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else
                    Text(
                      '登录后同步你的账户数据',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                ],
              ),
            ),
            if (!isLogin)
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatsSection extends StatelessWidget {
  final UserInfoModel? info;
  final bool isLogin;

  const _StatsSection({required this.info, required this.isLogin});

  @override
  Widget build(BuildContext context) {
    final dash = isLogin ? '-' : '—';
    return Padding(
      padding: const EdgeInsets.only(bottom: Style.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statColumn(context, '动态', isLogin ? _fmt(info?.dynamicCount) : dash),
          _statColumn(context, '关注', isLogin ? _fmt(info?.following) : dash),
          _statColumn(context, '粉丝', isLogin ? _fmt(info?.follower) : dash),
          _statColumn(context, '硬币', isLogin ? _fmt(info?.coins) : dash),
        ],
      ),
    );
  }

  String _fmt(num? n) {
    if (n == null) return '0';
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    return n.toString();
  }

  Widget _statColumn(BuildContext context, String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
