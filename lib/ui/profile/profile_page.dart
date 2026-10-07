import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';

import 'package:winwin/core/account/account_service.dart';
import 'package:winwin/core/account/login_guard.dart';
import 'package:winwin/core/account/login_utils.dart';
import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/core/demo/demo_overrides.dart';
import 'package:winwin/core/log/app_logger.dart';
import 'package:winwin/models/user/user_info.dart';
import 'package:winwin/pages/dynamics/view.dart';
import 'package:winwin/pages/login/login_page.dart';
import 'package:winwin/pages/member/member_space_page.dart';
import 'package:winwin/pages/relation/member_relation_page.dart';
import 'package:winwin/pages/setting/setting_page.dart';
import 'package:winwin/pages/setting/widgets/normal_item.dart';
import 'package:winwin/theme/app_shapes.dart';
import 'package:winwin/theme/app_typography.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/common/widgets/demo_editable.dart';
import 'package:winwin/common/widgets/level_badge.dart';
import 'package:winwin/ui/components/app_components.dart';
import 'package:winwin/ui/components/frosted_bottom_bar.dart';
import 'package:winwin/ui/profile/widgets/profile_sections.dart';
import 'package:winwin/utils/image_utils.dart';
import 'package:winwin/theme/app_icons.dart';

/// 个人页 — 布局参照 PiliPlus `MinePage`，控件美术单轨 Miuix（阶段5d-L4-2）。
///
/// 结构（PiliPlus 布局升级版）：
/// ```
/// ┌────────────────────────────────────────────┐
/// │ ┌──┐  Username [LV]                        │
/// │ │av│  硬币 X    经验 Y/Z  [====bar====]   │ 用户信息行
/// │ └──┘                                        │
/// ├────────────────────────────────────────────┤
/// │   动态        关注        粉丝             │ 3 统计方格
/// ├────────────────────────────────────────────┤
/// │ 离线缓存 [>]                           [🔄]│
/// │ [===== 横向直接展示内容卡片列表 =====]     │
/// ├────────────────────────────────────────────┤
/// │ 我的收藏 [>]                           [🔄]│
/// │ [===== 横向直接展示内容卡片列表 =====]     │
/// ├────────────────────────────────────────────┤
/// │ 历史记录 [>]                           [🔄]│
/// │ [===== 横向直接展示内容卡片列表 =====]     │
/// ├────────────────────────────────────────────┤
/// │ 稍后再看 [>]                           [🔄]│
/// │ [===== 横向直接展示内容卡片列表 =====]     │
/// ├────────────────────────────────────────────┤
/// │ 账号切换                                >  │
/// │ 退出登录                                >  │ AppGroup
/// │ 设置                                    >  │
/// └────────────────────────────────────────────┘
/// ```
///
/// 所有控件（[AppProgressBar] / [AppGroup] / [AppListItem]）
/// 均读取 [InheritedUiStyle.of] 后用 [resolvePrimitiveRenderer] 分发三风格。
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.onNavigate});

  /// 切换到根导航 tab（动态/历史等）。
  ///
  /// 传入时「动态」「历史记录」入口切换到对应根级共享实例，
  /// 与导航栏入口内容保持一致；未传入时回退为 push 独立页面。
  final ValueChanged<AppPage>? onNavigate;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _downloadKey = GlobalKey<ProfileDownloadSectionState>();
  final _favKey = GlobalKey<ProfileFavSectionState>();
  final _historyKey = GlobalKey<ProfileHistorySectionState>();
  final _toviewKey = GlobalKey<ProfileToviewSectionState>();

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

  Future<void> _onRefresh() async {
    await Future.wait([
      LoginUtils.onLoginMain(),
      _downloadKey.currentState?.reload() ?? Future.value(),
      _favKey.currentState?.reload() ?? Future.value(),
      _historyKey.currentState?.reload() ?? Future.value(),
      _toviewKey.currentState?.reload() ?? Future.value(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final service = AccountService();
    final info = service.displayUserInfo;
    final isLogin = service.isLogin;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: biliPink,
          onRefresh: _onRefresh,
          child: ListView(
            padding: const EdgeInsets.only(top: 16, bottom: 100),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              _UserInfoSection(info: info, isLogin: isLogin),
              const SizedBox(height: 10),
              _StatsRow(
                info: info,
                isLogin: isLogin,
                onGuarded: _guarded,
                onNavigate: widget.onNavigate,
              ),
              const SizedBox(height: 12),
              ProfileDownloadSection(key: _downloadKey),
              const SizedBox(height: 12),
              ProfileFavSection(key: _favKey),
              const SizedBox(height: 12),
              ProfileHistorySection(
                key: _historyKey,
                onNavigate: widget.onNavigate,
              ),
              const SizedBox(height: 12),
              ProfileToviewSection(key: _toviewKey),
              const SizedBox(height: Style.md),
              _SettingsGroup(
                isLogin: isLogin,
                onLogout: _onLogout,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 登录守卫：未登录→登录页；已登录→执行回调。
  ///
  /// 探针走 [AppLogger]（`[W]` 级）：原 `ApiBlackbox` 仅在 kDebugMode 初始化，
  /// Release 复测日志中完全不可见（见复盘「覆盖探针」一节）。
  Future<void> _guarded(
    BuildContext context,
    void Function(BuildContext) onLoggedIn,
  ) async {
    AppLogger.w(
      'Coverage',
      'profile guard tapped isLogin=${AccountService().isLogin}',
    );
    if (!await LoginGuard.requireLogin(context)) {
      AppLogger.w('Coverage', 'profile guard blocked (still logged out)');
      return;
    }
    if (!context.mounted) return;
    AppLogger.w('Coverage', 'profile guard passed → running callback');
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
// 用户信息行 — 头像 + 用户名/等级 + 硬币/经验 + 进度条
// ════════════════════════════════════════════════════════════════

/// 演示模式：VIP 类型下拉选项。
const List<(int, String)> _kVipOptions = [
  (0, '无'),
  (1, '月度大会员'),
  (2, '年度大会员'),
];

/// 演示模式：等级下拉选项。
const List<(int, String)> _kLevelOptions = [
  (0, 'LV0'),
  (1, 'LV1'),
  (2, 'LV2'),
  (3, 'LV3'),
  (4, 'LV4'),
  (5, 'LV5'),
  (6, 'LV6'),
];

class _UserInfoSection extends StatefulWidget {
  const _UserInfoSection({required this.info, required this.isLogin});

  final UserInfoModel? info;
  final bool isLogin;

  @override
  State<_UserInfoSection> createState() => _UserInfoSectionState();
}

class _UserInfoSectionState extends State<_UserInfoSection> {
  @override
  void initState() {
    super.initState();
    // 覆盖值变更时联动重建（经验条/昵称颜色跟随编辑值）。
    DemoOverrides.revision.addListener(_onOverrideChanged);
  }

  @override
  void dispose() {
    DemoOverrides.revision.removeListener(_onOverrideChanged);
    super.dispose();
  }

  void _onOverrideChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final isLogin = widget.isLogin;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final typo = Theme.of(context).extension<AppTypography>() ?? AppTypography.miuix;

    final levelInfo = info?.levelInfo;
    final hasLevel = levelInfo?.currentLevel != null;

    // 演示模式覆盖值：无覆盖时回退真实值。
    final realVip = (info?.isVip ?? false)
        ? ((info?.isYearVip ?? false) ? 2 : 1)
        : 0;
    final displayVip = DemoOverrides.choice('profile.vipType') ?? realVip;
    final displayCurExp =
        DemoOverrides.number('profile.exp') ?? levelInfo?.currentExp;
    final displayNextExp =
        DemoOverrides.number('profile.expNext') ?? levelInfo?.nextExp;
    // 进度：常规为 curExp/nextExp；LV6（nextExp 为 null/"–"）但经验有值时
    // 渲染满格——原先返回 null 会渲染为空轨道（复测反馈：经验条不可见）。
    final progress = (hasLevel &&
            displayNextExp != null &&
            displayNextExp > 0 &&
            displayCurExp != null)
        ? (displayCurExp / displayNextExp).clamp(0.0, 1.0)
        : (displayCurExp != null && displayCurExp > 0 ? 1.0 : null);

    final coinLabelStyle = theme.textTheme.labelMedium?.copyWith(
      color: cs.outline,
    );
    final coinValStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: typo.titleWeight,
      color: cs.secondary,
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!isLogin) {
            showLoginPage(context);
          } else {
            final mid = info?.mid;
            if (mid != null && mid > 0) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MemberSpacePage(mid: mid),
                ),
              );
            }
          }
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
                            imageUrl: ImageUtils.thumbnailUrl(info!.face!,
                                type: 'avatar'),
                            memCacheWidth:
                                ImageUtils.decodeClamp(55, context, max: 256),
                            memCacheHeight:
                                ImageUtils.decodeClamp(55, context, max: 256),
                            placeholder: (_, _) => const ColoredBox(
                              color: Colors.grey,
                              child: SizedBox.expand(),
                            ),
                            errorBuilder: (_, _, _) => Center(
                              child: AppIcon(AppIcons.profile(),
                                  color: Colors.white, size: 28),
                            ),
                            fit: BoxFit.cover,
                          )
                        : AppIcon(AppIcons.profile(),
                            color: Colors.white, size: 28),
                  ),
                  if (isLogin)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: DemoEditableChoice(
                        overrideKey: 'profile.vipType',
                        value: realVip,
                        options: _kVipOptions,
                        title: 'VIP 类型',
                        builder: (context, vip) => (vip ?? 0) > 0
                            ? Container(
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
                              )
                            : const SizedBox(width: 30, height: 16),
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
                              color: displayVip == 2 ? biliPink : null,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasLevel)
                          DemoEditableChoice(
                            overrideKey: 'profile.level',
                            value: levelInfo!.currentLevel,
                            options: _kLevelOptions,
                            title: '等级',
                            builder: (context, level) => LevelBadge(
                              level: level ?? 0,
                              height: 12,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (isLogin)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('硬币 ', style: coinLabelStyle),
                          DemoEditableNumber(
                            overrideKey: 'profile.coins',
                            value: info?.money?.toInt() ?? info?.coins,
                            title: '硬币数',
                            builder: (context, v) =>
                                Text(_fmtNum(v), style: coinValStyle),
                          ),
                          const SizedBox(width: 16),
                          Text('经验 ', style: coinLabelStyle),
                          DemoEditableNumber(
                            overrideKey: 'profile.exp',
                            value: levelInfo?.currentExp,
                            title: '经验值（当前）',
                            builder: (context, v) =>
                                Text(_fmtNum(v), style: coinValStyle),
                          ),
                          Text('/', style: coinLabelStyle),
                          DemoEditableNumber(
                            overrideKey: 'profile.expNext',
                            value: levelInfo?.nextExp,
                            title: '经验值（升级上限）',
                            builder: (context, v) =>
                                Text(_fmtNum(v), style: coinLabelStyle),
                          ),
                        ],
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
              if (isLogin) ...[
                const SizedBox(width: 8),
                AppIcon(AppIcons.chevronForward(),
                  color: cs.outline.withValues(alpha: 0.5),
                  size: 22,
                ),
              ],
            ],
          ),
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


// ════════════════════════════════════════════════════════════════
// 3 统计方格 — 动态 / 关注 / 粉丝
// ════════════════════════════════════════════════════════════════

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.info,
    required this.isLogin,
    required this.onGuarded,
    this.onNavigate,
  });

  final UserInfoModel? info;
  final bool isLogin;
  final Future<void> Function(BuildContext, void Function(BuildContext)) onGuarded;
  final ValueChanged<AppPage>? onNavigate;

  @override
  Widget build(BuildContext context) {
    final dash = isLogin ? null : '—';
    // Flexible 必须在 Row 的直接子级：演示外壳会包裹多层组件，
    // 因此统一在最外层提供 Flexible，并让 AppActionTile 关闭自带外壳。
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Flexible(
            child: DemoEditableNumber(
              overrideKey: 'profile.dynamic',
              value: info?.dynamicCount,
              title: '动态数',
              builder: (context, v) => AppActionTile(
                flexible: false,
                count: isLogin ? _fmt(v) : dash,
                label: '动态',
                // 切换到根导航「动态」tab，与导航栏入口共用同一实例。
                onTap: () => onGuarded(
                  context,
                  (ctx) => onNavigate != null
                      ? onNavigate!(AppPage.dynamic)
                      : showDynamicsPage(ctx),
                ),
              ),
            ),
          ),
          Flexible(
            child: DemoEditableNumber(
              overrideKey: 'profile.following',
              value: info?.following,
              title: '关注数',
              builder: (context, v) => AppActionTile(
                flexible: false,
                count: isLogin ? _fmt(v) : dash,
                label: '关注',
                onTap: () => onGuarded(
                  context,
                  (ctx) => _gotoRelation(ctx, RelationType.followings),
                ),
              ),
            ),
          ),
          Flexible(
            child: DemoEditableNumber(
              overrideKey: 'profile.follower',
              value: info?.follower,
              title: '粉丝数',
              builder: (context, v) => AppActionTile(
                flexible: false,
                count: isLogin ? _fmt(v) : dash,
                label: '粉丝',
                onTap: () => onGuarded(
                  context,
                  (ctx) => _gotoRelation(ctx, RelationType.fans),
                ),
              ),
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
      showToast(ctx, '用户信息未加载，请稍后重试');
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
// 设置组 — 账号切换 / 退出登录 / 设置（AppGroup + AppListItem）
// ════════════════════════════════════════════════════════════════

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    required this.isLogin,
    required this.onLogout,
  });

  final bool isLogin;
  final Future<void> Function(BuildContext) onLogout;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shapes = Theme.of(context).extension<AppShapes>() ?? AppShapes.miuix;
    // 阶段5d-L1：M3 分支已移除。
    final r = Radius.circular(shapes.large.x);

    Widget trailingChevron(ThemeData theme) => AppIcon(AppIcons.chevronForward(),
          size: 14,
          color: theme.colorScheme.outline,
        );

    return Column(
      children: [
        AppGroup(
          margin: const EdgeInsets.symmetric(horizontal: Style.lg),
          children: [
            NormalItem(
              leading: Icon(Icons.swap_horiz, color: cs.primary),
              title: '账号切换',
              getTrailing: trailingChevron,
              borderRadius: isLogin
                  ? BorderRadius.vertical(top: r)
                  : BorderRadius.all(r),
              // 直接进入登录页（**无论当前是否已登录**）：账号切换的入口语义
              // 就是去登录页换一个账号登录。原实现走 `_guarded` + 空回调，
              // 导致「已登录」时点击毫无反应（未登录时才偶然可用）。
              onTap: (ctx, _) {
                AppLogger.w('Coverage', 'profile account-switch → login page');
                showLoginPage(context);
              },
            ),
            if (isLogin)
              NormalItem(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: '退出登录',
                titleStyle: const TextStyle(color: Colors.red),
                getTrailing: trailingChevron,
                borderRadius: BorderRadius.vertical(bottom: r),
                onTap: (ctx, _) => onLogout(context),
              ),
          ],
        ),
        const SizedBox(height: Style.md),
        AppGroup(
          margin: const EdgeInsets.symmetric(horizontal: Style.lg),
          children: [
            NormalItem(
              leading: AppIcon(AppIcons.settings(), color: cs.primary),
              title: '设置',
              getTrailing: trailingChevron,
              borderRadius: BorderRadius.all(r),
              onTap: (ctx, _) => Navigator.push(
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
