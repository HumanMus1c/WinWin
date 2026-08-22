import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:winwin/core/account/account_service.dart';
import 'package:winwin/models/common/home_tab.dart';
import 'package:winwin/pages/follow/view.dart';
import 'package:winwin/pages/hot/view.dart';
import 'package:winwin/pages/live/view.dart';
import 'package:winwin/pages/login/login_page.dart';
import 'package:winwin/pages/pgc/view.dart';
import 'package:winwin/pages/rcmd/view.dart';
import 'package:winwin/pages/search/search_page.dart';
import 'package:winwin/pages/setting/setting_page.dart';
import 'package:winwin/theme/app_chrome.dart';
import 'package:winwin/theme/app_shapes.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/contrast_policy.dart';
import 'package:winwin/theme/inherited_ui_style.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/theme/ui_style.dart';

/// Home page — ported from BiliPai's HomeScreen.
/// Floating top bar, category tabs, video feed grid.
class HomePage extends StatefulWidget {
  /// 头像点击跳转到「我的」页面（已登录时）。
  final VoidCallback onGotoProfile;

  const HomePage({super.key, required this.onGotoProfile});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedCategory = 0;
  /// 已访问过的 tab 索引集合 — 懒加载：首次切到某 tab 才创建其 Widget，
  /// 避免启动时一次性触发所有 tab 的 HTTP 请求。
  final Set<int> _visitedTabs = {0};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ── Feed content (lazy IndexedStack preserves per-tab state) ──
          Positioned.fill(child: _buildContent()),
          // ── Floating top bar ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: RepaintBoundary(
              child: _HomeTopBar(onGotoProfile: widget.onGotoProfile),
            ),
          ),
          // ── Category tabs ──
          Positioned(
            top: 68,
            left: 0,
            right: 0,
            child: RepaintBoundary(
              child: _CategoryTabRow(
                selectedIndex: _selectedCategory,
                onSelect: (i) => setState(() {
                  _selectedCategory = i;
                  _visitedTabs.add(i);
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 按当前选中的分类 tab 渲染内容。使用 [IndexedStack] 保留各 tab 的滚动位置与已加载数据。
  /// 未访问过的 tab 返回 [SizedBox.shrink] 占位，首次切到时才实例化对应页面。
  Widget _buildContent() {
    return IndexedStack(
      index: _selectedCategory,
      children: List.generate(HomeTabType.defaultOrder.length, (i) {
        if (!_visitedTabs.contains(i)) {
          return const SizedBox.shrink();
        }
        return switch (HomeTabType.defaultOrder[i]) {
          HomeTabType.recommend => const RcmdPage(),
          HomeTabType.follow => const FollowPage(),
          HomeTabType.hot => const HotPage(),
          HomeTabType.bangumi => const PgcPage(),
          HomeTabType.live => const LivePage(),
        };
      }),
    );
  }
}

/// Floating top bar — avatar (login entry) + search pill + settings icon.
///
/// 左上角头像为账户登录入口：未登录点击进入 [LoginPage]，已登录点击
/// 通过 [onGotoProfile] 回调切换到「我的」页面。监听 [AccountService]
/// 实时反映登录态与头像。形状按 [UiStyle] 解析（[AppShapes.floating]）。
class _HomeTopBar extends StatefulWidget {
  final VoidCallback onGotoProfile;

  const _HomeTopBar({required this.onGotoProfile});

  @override
  State<_HomeTopBar> createState() => _HomeTopBarState();
}

class _HomeTopBarState extends State<_HomeTopBar> {
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

  void _onAvatarTap() {
    final service = AccountService();
    if (service.isLogin) {
      widget.onGotoProfile();
    } else {
      showLoginPage(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final service = AccountService();
    final isLogin = service.isLogin;
    final faceUrl = service.face;
    final shapes = theme.extension<AppShapes>() ?? AppShapes.ios;
    final chrome = theme.extension<AppChrome>() ?? AppChrome.ios;
    final style = InheritedUiStyle.of(context);
    final renderer = resolvePrimitiveRenderer(style);

    // 半透明容器对比度策略（ThemeContrastPolicy）：顶栏 surface 拍平到
    // 页面背景后，为前景色（图标/文字）选出达标的可读色。
    final barColor = cs.surface.withValues(alpha: 0.72);
    final barContrast = resolveAccessibleContainerColors(
      containerColor: barColor,
      contentColor: cs.onSurfaceVariant,
      backgroundColor: theme.scaffoldBackgroundColor,
      fallbackContentColors: [cs.onSurface, cs.onInverseSurface],
    );
    final barContentColor = barContrast.contentColor;

    final barRadius = switch (renderer) {
      PrimitiveRenderer.ios => Style.radiusFloating,
      _ => chrome.containerRadius,
    };
    final showShadow = renderer != PrimitiveRenderer.miuix;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Style.lg, vertical: Style.sm),
      // 毛玻璃顶栏（Frosted Top Bar）：与 FrostedBottomBar 同质感参数
      // （sigma 20 + surface α0.72），ClipRRect 限定模糊区域。
      child: ClipRRect(
        borderRadius: BorderRadius.circular(barRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: Style.topBarHeight,
            decoration: BoxDecoration(
          color: barColor,
          borderRadius: BorderRadius.circular(barRadius),
          border: Border.all(
            color: cs.outline.withValues(alpha: renderer == PrimitiveRenderer.miuix ? 0 : 0.1),
            width: 0.5,
          ),
          boxShadow: showShadow
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : const [],
        ),
        child: Row(
          children: [
            // Avatar (login entry)
            GestureDetector(
              onTap: _onAvatarTap,
              child: Container(
                width: 36,
                height: 36,
                margin: const EdgeInsets.only(left: Style.md),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: isLogin
                      ? null
                      : LinearGradient(
                          colors: [coverGradients[3].start, coverGradients[3].end],
                        ),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1),
                ),
                clipBehavior: Clip.antiAlias,
                child: isLogin && faceUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: faceUrl,
                        placeholder: (_, _) => const ColoredBox(
                          color: Colors.grey,
                          child: SizedBox.expand(),
                        ),
                        errorWidget: (_, _, _) => const ColoredBox(
                          color: Colors.grey,
                          child: Center(
                            child: Icon(Icons.person, color: Colors.white, size: 20),
                          ),
                        ),
                        fit: BoxFit.cover,
                      )
                    : const Icon(Icons.person, color: Colors.white, size: 20),
              ),
            ),
            const SizedBox(width: 12),
            // Search pill
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SearchPage(),
                  ),
                ),
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainer.withValues(alpha: 0.5),
                    borderRadius: shapes.pillBorder,
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      Icon(Icons.search,
                          size: 18,
                          color: barContentColor),
                      const SizedBox(width: 6),
                      Text(
                        '搜索视频、UP主...',
                        style: TextStyle(
                          color: barContentColor,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Settings icon
            Padding(
              padding: const EdgeInsets.only(right: Style.md),
              child: GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SettingPage(),
                  ),
                ),
                child: Icon(Icons.settings,
                    color: barContentColor, size: 22),
              ),
            ),
          ],
        ),
          ),
        ),
      ),
    );
  }
}

/// Horizontally scrollable category tabs — 使用 [HomeTabType.defaultOrder]。
/// 外层包裹与顶栏同款毛玻璃材质容器（sigma 20 + surface α0.72），
/// 形状/阴影按 [UiStyle] 解析，与 [_HomeTopBar] 视觉一致。
class _CategoryTabRow extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  const _CategoryTabRow({required this.selectedIndex, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final shapes = theme.extension<AppShapes>() ?? AppShapes.ios;
    final chrome = theme.extension<AppChrome>() ?? AppChrome.ios;
    final style = InheritedUiStyle.of(context);
    final renderer = resolvePrimitiveRenderer(style);
    final tabs = HomeTabType.defaultOrder;

    // 毛玻璃容器对比度策略（与 _HomeTopBar 同参）。
    final barColor = cs.surface.withValues(alpha: 0.72);
    final barContrast = resolveAccessibleContainerColors(
      containerColor: barColor,
      contentColor: cs.onSurfaceVariant,
      backgroundColor: theme.scaffoldBackgroundColor,
      fallbackContentColors: [cs.onSurface, cs.onInverseSurface],
    );
    final contentColor = barContrast.contentColor;
    final barRadius = switch (renderer) {
      PrimitiveRenderer.ios => Style.radiusFloating,
      _ => chrome.containerRadius,
    };
    final showShadow = renderer != PrimitiveRenderer.miuix;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Style.lg),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(barRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: 36,
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: BorderRadius.circular(barRadius),
              border: Border.all(
                color: cs.outline.withValues(
                  alpha: renderer == PrimitiveRenderer.miuix ? 0 : 0.1,
                ),
                width: 0.5,
              ),
              boxShadow: showShadow
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : const [],
            ),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Style.md),
              itemCount: tabs.length,
              separatorBuilder: (_, _) => const SizedBox(width: Style.sm),
              itemBuilder: (context, index) {
                final isSelected = index == selectedIndex;
                final baseColor = cs.primary;
                return GestureDetector(
                  onTap: () => onSelect(index),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: isSelected ? baseColor.withValues(alpha: 0.28) : Colors.transparent,
                      borderRadius: shapes.pillBorder,
                    ),
                    child: Text(
                      tabs[index].label,
                      style: TextStyle(
                        color: isSelected
                            ? baseColor
                            : contentColor.withValues(alpha: 0.78),
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
