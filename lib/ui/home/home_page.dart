import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart' show MiuixIconButton, MiuixMotion;

import 'package:winwin/common/widgets/app_top_bar_surface.dart';
import 'package:winwin/core/input/escape_layer_registry.dart';
import 'package:winwin/core/shell/app_routes.dart';
import 'package:winwin/core/shell/app_scaffold.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/models/common/home_tab.dart';
import 'package:winwin/pages/follow/view.dart';
import 'package:winwin/pages/hot/view.dart';
import 'package:winwin/pages/live/view.dart';
import 'package:winwin/pages/pgc/view.dart';
import 'package:winwin/pages/rcmd/view.dart';
import 'package:winwin/pages/search/search_page.dart';
import 'package:winwin/pages/search/search_result_page.dart';
import 'package:winwin/pages/search/services/search_history_service.dart';
import 'package:winwin/pages/search/widgets/search_content_panel.dart';
import 'package:winwin/pages/setting/setting_page.dart';
import 'package:winwin/theme/app_colors.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/contrast_policy.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/app_components.dart';
import 'package:winwin/ui/components/app_tooltip.dart';

/// 首页顶栏「就地扩充」用的统一动画节奏（与壳层安全行收起同手感）。
const Duration _kSearchMorphDuration = Duration(milliseconds: 220);

/// 搜索框行几何的**唯一口径**（常态「假搜索框」与搜索态真输入条共用）。
///
/// 两个状态由**不同 widget** 渲染（常态是自绘 [Container]，搜索态是
/// `AppCapsuleTextField → MiuixTextField`）。若两边的框内左边距与图标—文字
/// 间距不写成同源常量，聚焦切换的一瞬间图标/占位文字会横向跳变
/// （CVO 反馈「点击聚焦后搜索框尺寸和位置发生了偏移」的根因）。
///
/// 注意 `MiuixTextField` 在**有 leadingIcon 时不会给图标加水平内距**
/// （其 `insideMargin.left` 仅作用于无前导图标时的文本区），故前缀必须
/// 自带左内距，方可与常态框对齐。
const double _kSearchRowHeight = 38;
const double _kSearchRowInset = Style.md; // 框内左内距（图标左缘到框左缘）
const double _kSearchIconTextGap = Style.sm; // 图标与文字/占位间距

/// 搜索框字号：常态占位、搜索态占位与输入文本三者共用。
///
/// 根因备忘：`MiuixTextField` 未显式传 `textStyle` 时会回退到
/// `MiuixTheme.textStyles.main`（**17px**）。17px 行高（约 24px）塞进
/// 38−8×2=22px 的文字区 ⇒ ① 文本光标比输入框还高、溢出框体；
/// ② 输入文本(17) 与占位(13) 行盒不同高、基线错位，占位视觉下偏。
/// 统一到 13px 后，输入文本/光标与占位同号同行盒，两个问题一并消除。
const double _kSearchTextSize = 13;

/// Home page — ported from BiliPai's HomeScreen.
/// Floating top bar, category tabs, video feed grid.
///
/// 2026-10-19：搜索由「跳二级页面」改为「顶栏就地扩充」——点搜索框不再
/// 跳页，而是在首页顶栏原地长高一块（隐藏分类标签，长出来的地方放搜索
/// 历史 / 用户胶囊 / 热搜），背景压暗，提交后进搜索结果页。
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

  /// 是否处于「顶栏就地扩充」的搜索态。
  bool _searchMode = false;

  /// 搜索态输入框的控制器 / 焦点（仅在搜索态挂到顶栏输入条上）。
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  /// 搜索态在全局 Esc 路由器（[EscapeLayerRegistry]）里的注销函数。
  VoidCallback? _escapeUnregister;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_onSearchFocusChanged);
  }

  @override
  void dispose() {
    _escapeUnregister?.call();
    _escapeUnregister = null;
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // ─────────────────────────── 搜索态开关 ───────────────────────────

  void _enterSearch() {
    if (_searchMode) {
      // 已展开：再点一次仅把焦点还给输入框。
      _searchFocusNode.requestFocus();
      return;
    }
    setState(() => _searchMode = true);
    // 登记为「可被 Esc 关闭的二级浮层」：交全局 Esc 路由器（`AppEscapeScope`
    // 第 2 层）统一处理。**不再自挂 CallbackShortcuts**——键事件只沿当前焦点
    // 节点的祖先链派发，焦点一旦被导航栏/底栏等抢走，搜索态子树的快捷键就
    // 不在链上，Esc 会失效（这正是本轮实测反馈的缺陷）。
    _escapeUnregister =
        EscapeLayerRegistry.instance.register(_closeSearchLayerIfOpen);
    // `autofocus` 偶发因首帧竞态未落地；补一次，确保焦点真的在输入框里。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _searchMode && !_searchFocusNode.hasFocus) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  /// 供全局 Esc 路由器回调：仅当本页处于最上层时才消费这次 Esc。
  ///
  /// 返回 false 时路由器会剔除该登记并继续向下层——因此「设置页 / 搜索结果页 /
  /// 对话框压在最上层」时的 Esc 语义不会被躺在下面的搜索态抢走。
  bool _closeSearchLayerIfOpen() {
    if (!_searchMode) return false;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    _exitSearch();
    return true;
  }

  /// 收起搜索态：先落开关（避免 `unfocus` 回调重入），取消输入焦点、清空输入、
  /// 注销 Esc 层，然后恢复分类标签。
  void _exitSearch() {
    if (!_searchMode) return;
    _searchMode = false;
    _searchFocusNode.unfocus();
    _searchController.clear();
    _escapeUnregister?.call();
    _escapeUnregister = null;
    if (mounted) setState(() {});
  }

  /// 焦点离开输入框 = 离开搜索上下文 → 收起（例：点了导航栏 / 底栏）。
  ///
  /// 三重护栏：
  /// - **面板内点击不算"离开"**：`_HomeHeader` 已整体并入输入框的 TapRegion 组
  ///   （见其 `build` 外层 `TextFieldTapRegion`），面板内（历史词 / 用户胶囊 /
  ///   热搜条目 / 清空 / ✕ / 刷新 / 设置齿轮）的按下即"内侧"，不会触发
  ///   `EditableText` 桌面端默认的 `onTapOutside → unfocus`。**注意该默认值在
  ///   桌面端并非空实现**——`EditableText` 的 `_EditableTextTapOutsideAction` 对
  ///   windows/linux/macOS 就是 `focusNode.unfocus()`；真正空实现的是
  ///   `onTapUpOutside`。第二轮复盘把它当作"桌面端什么都不做"是**误判**，正是
  ///   本轮"点面板条目即失焦并被误收起、点击被吞"的根因。
  /// - **被路由 / 对话框压顶不算"离开"**：焦点丢失若伴随本页不再是当前路由
  ///   （push 用户空间 / 清空确认框 / 设置页等抢走焦点），应**保留**搜索态，返回
  ///   后原样还在；只有**原地**失焦（点导航栏 / 底栏）才收起。
  /// - 窗口失活（切到别的应用）会让 `FocusManager` 挂起主焦点，属"暂时"而非
  ///   "离开"，故应用不在 resumed 时直接忽略。
  void _onSearchFocusChanged() {
    if (!mounted || !_searchMode || _searchFocusNode.hasFocus) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    // 路由/对话框压顶：这次失焦是"被覆盖"，不是"离开搜索上下文"→ 保留。
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    _exitSearch();
  }

  /// 提交搜索：保存到历史（口径不变：[SearchKeywordHistory]）→ 收起搜索态
  /// → 直接进搜索结果页。
  Future<void> _submitSearch(String keyword) async {
    final word = keyword.trim();
    if (word.isEmpty) return;
    SearchKeywordHistory.push(SearchKeywordHistory.load(), word);
    _exitSearch();
    if (!mounted) return;
    await Navigator.push(
      context,
      AppRoute(builder: (_) => SearchResultPage(keyword: word)),
    );
  }

  /// 「完整榜单 ›」入口：打开独立搜索页（含完整热搜网格）。
  void _openFullRank() {
    _exitSearch();
    Navigator.push(context, AppRoute(builder: (_) => const SearchPage()));
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: '首页',
      // 顶栏与遮罩放进骨架浮层：只有在这一层才能连同「首页」安全行一起压暗。
      overlayBuilder: _buildOverlay,
      body: _buildContent(),
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

  /// 内容之上的浮层：压暗遮罩（搜索态）+ 悬浮顶栏。
  ///
  /// - 顶栏贴在安全行之下（安全行收起时随之上移），沿用首页原有滚动联动；
  /// - 搜索态压暗**含安全行在内**的整页背景，点遮罩即收起；
  /// - 扩充块高度上限按当前可用高度算，绝不顶出屏幕（超出末尾省略）。
  Widget _buildOverlay(BuildContext context, bool stripCollapsed) {
    final tokens = AppThemeHost.of(context);
    final stripHeight = stripCollapsed ? 0.0 : AppScaffold.topStripHeight;
    return LayoutBuilder(
      builder: (context, constraints) {
        // 顶栏固定部分：外壳上下边距 + 内容区上下边距 + 搜索框行 38 + 行间 6，
        // 另留 Style.md 作为底部余量。
        const fixed = Style.sm * 4 + _kSearchRowHeight + 6 + Style.md;
        final maxPanelHeight = (constraints.maxHeight - stripHeight - fixed)
            .clamp(120.0, double.infinity);
        return Stack(
          children: [
            // ① 半透明暗色遮罩（含安全行；非搜索态不吸事件、不可见）。
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !_searchMode,
                child: AnimatedOpacity(
                  opacity: _searchMode ? 1 : 0,
                  duration: _kSearchMorphDuration,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _exitSearch,
                    child: ColoredBox(
                      color: tokens.colors.scrim.withValues(alpha: 0.38),
                    ),
                  ),
                ),
              ),
            ),
            // ② 悬浮顶栏（搜索框 + 分类标签 / 就地扩充块）。
            AnimatedPositioned(
              duration: _kSearchMorphDuration,
              curve: MiuixMotion.standardDecelerate,
              top: stripHeight,
              left: 0,
              right: 0,
              child: RepaintBoundary(
                // Esc 收起不再自挂 CallbackShortcuts（焦点被抢走即失效）：
                // 搜索态已登记进全局 Esc 路由器，见 _enterSearch。
                child: _HomeHeader(
                  selectedCategory: _selectedCategory,
                  onSelectCategory: (i) => setState(() {
                    _selectedCategory = i;
                    _visitedTabs.add(i);
                  }),
                  searchMode: _searchMode,
                  searchController: _searchController,
                  searchFocusNode: _searchFocusNode,
                  onEnterSearch: _enterSearch,
                  onSubmitSearch: _submitSearch,
                  panelMaxHeight: maxPanelHeight,
                  onOpenFullRank: _openFullRank,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 首页共享顶栏容器 — 搜索框 + 一级分类 Tabs / 搜索态就地扩充块。
///
/// 头像已迁移至导航栏「我的」TAB。搜索框样式与 [SearchPage] 统一，
/// 整体包裹于同一个毛玻璃材质容器中（[AppTopBarSurface] 单一来源）。
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.selectedCategory,
    required this.onSelectCategory,
    required this.searchMode,
    required this.searchController,
    required this.searchFocusNode,
    required this.onEnterSearch,
    required this.onSubmitSearch,
    required this.panelMaxHeight,
    required this.onOpenFullRank,
  });

  final int selectedCategory;
  final ValueChanged<int> onSelectCategory;

  /// 是否处于搜索态（顶栏就地扩充）。
  final bool searchMode;

  final TextEditingController searchController;
  final FocusNode searchFocusNode;

  /// 常态下点击搜索框 → 进入搜索态。
  final VoidCallback onEnterSearch;
  final ValueChanged<String> onSubmitSearch;

  /// 扩充块高度上限（由宿主按可用高度算好，绝不顶出屏幕）。
  final double panelMaxHeight;

  /// 「完整榜单 ›」入口（搜索态热搜标题行）。
  final VoidCallback onOpenFullRank;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final shapes = tokens.shapes;
    final tabs = HomeTabType.defaultOrder;

    final barColor = AppTopBarSurface.barColor(cs.surface);
    final barContrast = resolveAccessibleContainerColors(
      containerColor: barColor,
      contentColor: cs.onSurfaceVariant,
      backgroundColor: tokens.colors.background,
      fallbackContentColors: [cs.onSurface, cs.onInverseSurface],
    );
    final barContentColor = barContrast.contentColor;

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
          // Row 1: Search bar —— 高度恒 38（搜索态内外一致，不参与长高）。
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: _kSearchRowHeight,
                  child: _buildSearchRow(searchBg, searchFg),
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
                child: AppTooltip(message: '设置', child: AppIcon(
                  AppIcons.settings(),
                  color: searchFg,
                  size: 22,
                )),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Row 2: 常态 = 分类标签（32）；搜索态 = 就地扩充块。
          // 高度变化由 AnimatedSize 补齐（220ms / standardDecelerate，同安全行手感）。
          AnimatedSize(
            duration: _kSearchMorphDuration,
            curve: MiuixMotion.standardDecelerate,
            alignment: Alignment.topCenter,
            child: searchMode
                ? SearchContentPanel(
                    controller: searchController,
                    onSubmit: onSubmitSearch,
                    maxHeight: panelMaxHeight,
                    onOpenFullRank: onOpenFullRank,
                    padding: EdgeInsets.zero,
                  )
                : SizedBox(
                    height: 32,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: tabs.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(width: Style.sm),
                      itemBuilder: (context, index) {
                        final isSelected = index == selectedCategory;
                        final baseColor = cs.primary;
                        return GestureDetector(
                          onTap: () => onSelectCategory(index),
                          child: Container(
                            alignment: Alignment.center,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? baseColor.withValues(alpha: 0.28)
                                  : AppColors.transparent,
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
          ),
        ],
      ),
    );

    // 顶栏材质单一来源：与消息中心合并栏共用 [AppTopBarSurface]（同底色/模糊/
    // 圆角/外距），避免两页各写一份而漂移。
    //
    // 外层 `TextFieldTapRegion`（F1 归组）：把整块顶栏并入搜索输入框的 TapRegion
    // 组，使面板内（历史词 / 用户胶囊 / 热搜条目 / 清空 / ✕ / 刷新 / 设置齿轮）的
    // 按下被视为"输入框内侧"，不再触发 `EditableText` 桌面端默认的
    // `onTapOutside → unfocus`——否则会被"失焦即退出"同步收起搜索态，被按下的
    // 控件在 tap-up 前就被卸载，点击被吞（本轮根因）。组外点击（遮罩 / 导航栏 /
    // 底栏）仍走默认失焦，"点导航栏即收起"的语义不变。默认 `groupId == EditableText`
    // 与输入框自身同组（SDK `TapRegion` 的既定用法，非本项目自定义）。
    return TextFieldTapRegion(
      child: AppTopBarSurface(child: headerContent),
    );
  }

  /// 搜索框行：常态为「假搜索框」（点击进搜索态）；搜索态换成真输入条
  /// （自动聚焦、回车提交、可清空），高度同为 38。
  Widget _buildSearchRow(Color searchBg, Color searchFg) {
    // 图标 + 间距为两状态共用件：搜索态把它整体作为 `prefix` 交给
    // `AppCapsuleTextField`（MiuixTextField 有前导图标时不加水平内距，
    // 故此处自带左内距），常态则直接放进自绘 Row —— 两种渲染下图标左缘
    // 与文字起点完全一致（_kSearchRowInset / _kSearchIconTextGap 单一来源）。
    final icon = AppIcon(AppIcons.search(), size: 20, color: searchFg);

    if (searchMode) {
      return AppCapsuleTextField(
        controller: searchController,
        focusNode: searchFocusNode,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onSubmitted: onSubmitSearch,
        hint: '搜索视频、UP主...',
        // 输入文本与占位同号（顺带把光标收到 13px 行高，不再高过输入框）；
        // 占位样式与常态框逐项对齐（字号 + 颜色）。
        textStyle: const TextStyle(fontSize: _kSearchTextSize),
        hintStyle: TextStyle(
          fontSize: _kSearchTextSize,
          color: searchFg.withValues(alpha: 0.7),
        ),
        prefix: Padding(
          padding: const EdgeInsets.only(
            left: _kSearchRowInset,
            right: _kSearchIconTextGap,
          ),
          child: icon,
        ),
        suffix: ValueListenableBuilder<TextEditingValue>(
          valueListenable: searchController,
          builder: (context, value, _) {
            if (value.text.isEmpty) return const SizedBox.shrink();
            return MiuixIconButton(
              onPressed: searchController.clear,
              child: AppIcon(AppIcons.clear(), size: 18),
            );
          },
        ),
      );
    }
    return GestureDetector(
      onTap: onEnterSearch,
      child: Container(
        decoration: BoxDecoration(
          color: searchBg,
          borderRadius: BorderRadius.circular(Style.radiusFull),
        ),
        padding: const EdgeInsets.only(left: _kSearchRowInset),
        child: Row(
          children: [
            icon,
            const SizedBox(width: _kSearchIconTextGap),
            Expanded(
              child: Text(
                '搜索视频、UP主...',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: _kSearchTextSize,
                  color: searchFg.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}