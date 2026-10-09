import 'dart:ui';

import 'package:flutter_miuix/miuix.dart' show MiuixIconButton;
import 'package:material_ui/material_ui.dart';
import 'package:winwin/models/common/home_tab.dart';
import 'package:winwin/pages/follow/view.dart';
import 'package:winwin/pages/hot/view.dart';
import 'package:winwin/pages/live/view.dart';
import 'package:winwin/pages/pgc/view.dart';
import 'package:winwin/pages/rcmd/view.dart';
import 'package:winwin/pages/search/search_page.dart';
import 'package:winwin/pages/setting/setting_page.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/contrast_policy.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/core/shell/app_routes.dart';
import 'package:winwin/core/shell/app_scaffold.dart';

/// Home page — ported from BiliPai's HomeScreen.
/// Floating top bar, category tabs, video feed grid.
class HomePage extends StatefulWidget {
  /// 头像点击跳转到「我的」页面（保留可选向后兼容）。
  final VoidCallback? onGotoProfile;

  const HomePage({super.key, this.onGotoProfile});

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
    return AppScaffold(
      title: '首页',
      body: Stack(
        children: [
          // ── Feed content (lazy IndexedStack preserves per-tab state) ──
          Positioned.fill(child: _buildContent()),
          // ── Floating shared header (search bar + category tabs) ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: RepaintBoundary(
              child: _HomeHeader(
                selectedCategory: _selectedCategory,
                onSelectCategory: (i) => setState(() {
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

/// 首页共享顶栏容器 — 搜索框 + 一级分类 Tabs。
///
/// 头像已迁移至导航栏「我的」TAB。搜索框样式与 [SearchPage] 统一，
/// 整体包裹于同一个毛玻璃材质/M3 Surface 容器中。
class _HomeHeader extends StatelessWidget {
  final int selectedCategory;
  final ValueChanged<int> onSelectCategory;

  const _HomeHeader({
    required this.selectedCategory,
    required this.onSelectCategory,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final shapes = tokens.shapes;
    final chrome = tokens.chrome;
    final tabs = HomeTabType.defaultOrder;

    final barColor = cs.surface.withValues(alpha: 0.72);
    final barContrast = resolveAccessibleContainerColors(
      containerColor: barColor,
      contentColor: cs.onSurfaceVariant,
      backgroundColor: tokens.colors.background,
      fallbackContentColors: [cs.onSurface, cs.onInverseSurface],
    );
    final barContentColor = barContrast.contentColor;
    final barRadius = chrome.containerRadius;

    final searchBg = cs.surfaceContainer.withValues(alpha: 0.5);
    final searchFg = barContentColor;

    final headerContent = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Style.md,
        vertical: Style.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Search bar (Search box + Settings icon)
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    readOnly: true,
                    onTap: () => Navigator.push(
                      context,
                      AppRoute(
                        builder: (_) => const SearchPage(),
                      ),
                    ),
                    decoration: InputDecoration(
                      hintText: '搜索视频、UP主...',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: searchFg.withValues(alpha: 0.7),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: Style.md,
                        vertical: 8,
                      ),
                      prefixIcon: AppIcon(
                        AppIcons.search(),
                        size: 20,
                        color: searchFg,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(100),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: searchBg,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Style.sm),
              MiuixIconButton(

                onPressed: () => Navigator.push(
                  context,
                  AppRoute(
                    builder: (_) => const SettingPage(),
                  ),
                ),

                child: Tooltip(message: '设置', child: AppIcon(
                  AppIcons.settings(),
                  color: searchFg,
                  size: 22,
                )),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Row 2: Category tabs
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: tabs.length,
              separatorBuilder: (_, _) => const SizedBox(width: Style.sm),
              itemBuilder: (context, index) {
                final isSelected = index == selectedCategory;
                final baseColor = cs.primary;
                return GestureDetector(
                  onTap: () => onSelectCategory(index),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? baseColor.withValues(alpha: 0.28)
                          : Colors.transparent,
                      borderRadius: shapes.pillBorder,
                    ),
                    child: Text(
                      tabs[index].label,
                      style: TextStyle(
                        color: isSelected
                            ? baseColor
                            : barContentColor.withValues(alpha: 0.78),
                        fontSize: 13,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Style.lg,
        vertical: Style.sm,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(barRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: BorderRadius.circular(barRadius),
              border: Border.all(
                color: cs.outline.withValues(alpha: 0),
                width: 0.5,
              ),
            ),
            child: headerContent,
          ),
        ),
      ),
    );
  }
}
