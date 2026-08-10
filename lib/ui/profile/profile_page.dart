import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:winwin/core/account/account_service.dart';
import 'package:winwin/core/account/login_guard.dart';
import 'package:winwin/core/account/login_utils.dart';
import 'package:winwin/models/user/user_info.dart';
import 'package:winwin/pages/dynamics/view.dart';
import 'package:winwin/pages/fav/fav_page.dart';
import 'package:winwin/pages/history/history_page.dart';
import 'package:winwin/pages/login/login_page.dart';
import 'package:winwin/pages/relation/member_relation_page.dart';
import 'package:winwin/pages/search/search_page.dart';
import 'package:winwin/pages/setting/setting_page.dart';
import 'package:winwin/pages/toview/toview_page.dart';
import 'package:winwin/theme/app_typography.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/inherited_ui_style.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/theme/ui_style.dart';
import 'package:winwin/theme/ui_style_notifier.dart';
import 'package:winwin/ui/components/app_components.dart';

/// 个人页 — 布局参照 PiliPlus `MinePage`，控件美术按 [UiStyle] 三风格切换。
///
/// 结构（PiliPlus 布局）：
/// ```
/// ┌────────────────────────────────────────────┐
/// │ [search]        [style] [setting]          │ 顶栏操作行
/// ├────────────────────────────────────────────┤
/// │ ┌──┐  Username [LV]                        │
/// │ │av│  硬币 X    经验 Y/Z  [====bar====]   │ 用户信息行
/// │ └──┘                                        │
/// ├────────────────────────────────────────────┤
/// │   动态        关注        粉丝             │ 3 统计方格
/// ├────────────────────────────────────────────┤
/// │   ⬇          📜          ⭐          ⏰    │ 4 动作方格
/// │ 离线缓存   历史记录    我的收藏   稍后再看 │
/// ├────────────────────────────────────────────┤
/// │ 账号切换                                >  │
/// │ 退出登录                                >  │ AppGroup
/// │ 设置                                    >  │
/// └────────────────────────────────────────────┘
/// ```
///
/// 所有控件（[AppActionTile] / [AppProgressBar] / [AppGroup] / [AppListItem]）
/// 均读取 [InheritedUiStyle.of] 后用 [resolvePrimitiveRenderer] 分发三风格。
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  @override
  void initState() {
    super.initState();
    AccountService().addListener(_onAccountChanged);
  }

  @override
  void dispose() {
    AccountService().removeListener(_onAccountChanged);
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
    return Scaffold(
      body: Column(
        children: [
          _HeaderActions(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 100),
              children: [
                _UserInfoSection(info: info, isLogin: isLogin),
                const SizedBox(height: 10),
                _StatsRow(info: info, isLogin: isLogin, onGuarded: _guarded),
                const SizedBox(height: 10),
                _ActionGrid(
                  onGuarded: _guarded,
                ),
                const SizedBox(height: Style.md),
                _SettingsGroup(
                  isLogin: isLogin,
                  onGuarded: _guarded,
                  onLogout: _onLogout,
                ),
              ],
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
    await LoginUtils.onLogoutMain();
  }
}

// ════════════════════════════════════════════════════════════════
// 顶栏操作行 — 搜索 + 风格切换 + 设置
// ════════════════════════════════════════════════════════════════

class _HeaderActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final style = InheritedUiStyle.of(context);
    // 下一风格（循环切换 iOS→MD3→Miuix→iOS）
    final nextStyle = UiStyle.values[(style.legacyInt + 1) % UiStyle.values.length];
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        child: Row(
          children: [
            IconButton(
              tooltip: '搜索',
              iconSize: 22,
              padding: const EdgeInsets.all(8),
              style: const ButtonStyle(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SearchPage()),
              ),
              icon: Icon(Icons.search, color: cs.onSurface),
            ),
            const Spacer(),
            IconButton(
              tooltip: '切换至${nextStyle.label}风格',
              iconSize: 22,
              padding: const EdgeInsets.all(8),
              style: const ButtonStyle(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => UiStyleNotifier.instance.setStyle(nextStyle),
              icon: Icon(Icons.palette_outlined, color: cs.onSurface),
            ),
            IconButton(
              tooltip: '设置',
              iconSize: 22,
              padding: const EdgeInsets.all(8),
              style: const ButtonStyle(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingPage()),
              ),
              icon: Icon(Icons.settings_outlined, color: cs.onSurface),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 用户信息行 — 头像 + 用户名/等级 + 硬币/经验 + 进度条
// ════════════════════════════════════════════════════════════════

class _UserInfoSection extends StatelessWidget {
  const _UserInfoSection({required this.info, required this.isLogin});

  final UserInfoModel? info;
  final bool isLogin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final typo = Theme.of(context).extension<AppTypography>() ?? AppTypography.ios;

    final levelInfo = info?.levelInfo;
    final hasLevel = levelInfo?.currentLevel != null;
    final isVip = info?.isVip ?? false;
    final nextExp = levelInfo?.nextExp;
    final curExp = levelInfo?.currentExp;
    final progress = (hasLevel &&
            nextExp != null &&
            nextExp > 0 &&
            curExp != null)
        ? (curExp / nextExp)
        : null;

    final coinLabelStyle = theme.textTheme.labelMedium?.copyWith(
      color: cs.outline,
    );
    final coinValStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: typo.titleWeight,
      color: cs.secondary,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (!isLogin) showLoginPage(context);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            // 头像（55px 圆形 + VIP 角标）
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 55,
                  height: 55,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: isLogin
                        ? null
                        : LinearGradient(
                            colors: [
                              biliPink,
                              biliPink.withValues(alpha: 0.7),
                            ],
                          ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
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
                            child: Icon(Icons.person,
                                color: Colors.white, size: 28),
                          ),
                          fit: BoxFit.cover,
                        )
                      : const Icon(Icons.person,
                          color: Colors.white, size: 28),
                ),
                if (isVip)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: biliPink,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: cs.surface, width: 1),
                      ),
                      child: const Text(
                        'VIP',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            // 用户名 + 硬币/经验 + 进度条
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    spacing: 6,
                    children: [
                      Flexible(
                        child: Text(
                          isLogin ? (info?.name ?? '未命名用户') : '点击登录',
                          style: theme.textTheme.titleMedium?.copyWith(
                            height: 1,
                            fontWeight: typo.titleWeight,
                            color: isVip && (info?.isYearVip ?? false)
                                ? biliPink
                                : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasLevel)
                        _LevelBadge(level: levelInfo!.currentLevel!),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (isLogin)
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '硬币 ', style: coinLabelStyle),
                          TextSpan(
                            text: _fmtNum(info?.money?.toInt() ?? info?.coins),
                            style: coinValStyle,
                          ),
                          TextSpan(text: '      经验 ', style: coinLabelStyle),
                          TextSpan(
                            text: _fmtNum(curExp),
                            style: coinValStyle,
                          ),
                          TextSpan(
                            text: '/${_fmtNum(nextExp)}',
                            style: coinLabelStyle,
                          ),
                        ],
                      ),
                    )
                  else
                    Text(
                      '登录后同步你的账户数据',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  const SizedBox(height: 4),
                  if (isLogin)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 225),
                      child: AppProgressBar(value: progress),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtNum(num? n) {
    if (n == null) return '-';
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    return n.toString();
  }
}

/// 等级徽章 — 小圆角胶囊，按风格切换底色。
class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = InheritedUiStyle.of(context);
    final (bg, fg) = switch (resolvePrimitiveRenderer(style)) {
      PrimitiveRenderer.ios => (biliPink, Colors.white),
      PrimitiveRenderer.material3 => (cs.primary, cs.onPrimary),
      PrimitiveRenderer.miuix => (cs.secondaryContainer, cs.onSecondaryContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'LV$level',
        style: TextStyle(
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 3 统计方格 — 动态 / 关注 / 粉丝
// ════════════════════════════════════════════════════════════════

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.info,
    required this.isLogin,
    required this.onGuarded,
  });

  final UserInfoModel? info;
  final bool isLogin;
  final Future<void> Function(BuildContext, void Function(BuildContext)) onGuarded;

  @override
  Widget build(BuildContext context) {
    final dash = isLogin ? null : '—';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          AppActionTile(
            count: isLogin ? _fmt(info?.dynamicCount) : dash,
            label: '动态',
            onTap: () => onGuarded(context, (ctx) => showDynamicsPage(ctx)),
          ),
          AppActionTile(
            count: isLogin ? _fmt(info?.following) : dash,
            label: '关注',
            onTap: () => onGuarded(
              context,
              (ctx) => _gotoRelation(ctx, RelationType.followings),
            ),
          ),
          AppActionTile(
            count: isLogin ? _fmt(info?.follower) : dash,
            label: '粉丝',
            onTap: () => onGuarded(
              context,
              (ctx) => _gotoRelation(ctx, RelationType.fans),
            ),
          ),
        ],
      ),
    );
  }

  /// 跳转关注/粉丝列表页。需要当前账号 mid；未加载时提示重试。
  void _gotoRelation(BuildContext ctx, RelationType type) {
    final mid = info?.mid;
    if (mid == null || mid <= 0) {
      ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
        const SnackBar(content: Text('用户信息未加载，请稍后重试')),
      );
      return;
    }
    showMemberRelationPage(ctx, type: type, vmid: mid);
  }

  String _fmt(num? n) {
    if (n == null) return '0';
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    return n.toString();
  }
}

// ════════════════════════════════════════════════════════════════
// 4 动作方格 — 离线缓存 / 历史记录 / 我的收藏 / 稍后再看
// ════════════════════════════════════════════════════════════════

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({required this.onGuarded});

  final Future<void> Function(BuildContext, void Function(BuildContext)) onGuarded;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          AppActionTile(
            icon: Icons.download_outlined,
            label: '离线缓存',
            onTap: () => onGuarded(context, (_) {}),
          ),
          AppActionTile(
            icon: Icons.history,
            label: '历史记录',
            onTap: () => onGuarded(context, showHistoryPage),
          ),
          AppActionTile(
            icon: Icons.bookmark_outline,
            label: '我的收藏',
            onTap: () => onGuarded(context, showFavPage),
          ),
          AppActionTile(
            icon: Icons.watch_later_outlined,
            label: '稍后再看',
            onTap: () => onGuarded(context, showToviewPage),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 设置组 — 账号切换 / 退出登录 / 设置（AppGroup + AppListItem）
// ════════════════════════════════════════════════════════════════

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    required this.isLogin,
    required this.onGuarded,
    required this.onLogout,
  });

  final bool isLogin;
  final Future<void> Function(BuildContext, void Function(BuildContext)) onGuarded;
  final Future<void> Function(BuildContext) onLogout;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
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
                MaterialPageRoute(builder: (_) => const SettingPage()),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
