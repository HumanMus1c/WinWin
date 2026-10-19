import 'dart:async';

import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart'
    show
        MiuixBasicComponent,
        MiuixIconButton,
        MiuixPressFeedbackType,
        MiuixPressable,
        MiuixTextButton;

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:winwin/common/skeleton/skeleton.dart';
import 'package:winwin/common/widgets/app_chip.dart';
import 'package:winwin/core/demo/demo_overrides.dart';
import 'package:winwin/core/shell/app_dialogs.dart';
import 'package:winwin/core/shell/app_routes.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/common/widgets/app_dialog_shell.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/search.dart';
import 'package:winwin/models/search/result.dart';
import 'package:winwin/models/search/suggest.dart';
import 'package:winwin/pages/member/member_space_page.dart';
import 'package:winwin/pages/search/services/search_history_service.dart';
import 'package:winwin/pages/search/widgets/hot_keyword.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/app_progress.dart';
import 'package:winwin/utils/image_utils.dart';

/// 搜索内容面板 —— 搜索态的**唯一**内容实现（P4：概念只在一处定义）。
///
/// 自上而下（文本为空时）：
/// 1. 搜索历史（词胶囊，可单删 / 清空）；
/// 2. 点过的用户胶囊（头像 + 名字，点进空间、长按删）；
/// 3. 大家都在搜（两列网格热搜，见 [HotKeywordGrid]）。
///
/// 文本非空时切换为「搜索联想建议」。
///
/// **数据口径零改动**：历史词仍走 [SearchKeywordHistory]、用户胶囊仍走
/// [SearchHistoryService]（同一缓存键、同一上限、同一去重/置顶规则），
/// 本面板只负责展示位置。
///
/// 两个宿主共用本面板：
/// - 首页顶栏搜索态扩充区（`lib/ui/home/home_page.dart`，传 [maxHeight] 限高）；
/// - 独立搜索页（`lib/pages/search/search_page.dart`，外层可滚动）。
class SearchContentPanel extends StatefulWidget {
  const SearchContentPanel({
    super.key,
    required this.controller,
    required this.onSubmit,
    this.maxHeight,
    this.historyVersion = 0,
    this.onOpenFullRank,
    this.padding = const EdgeInsets.all(Style.md),
  });

  /// 搜索输入控制器（由宿主持有；本面板只读文本 + 监听变化拉联想）。
  final TextEditingController controller;

  /// 提交某个关键词（点历史词 / 点热搜 / 点联想 / 回车——回传关键词原文）。
  ///
  /// 宿主负责「保存到历史 + 跳转结果页 + 收起搜索态」。
  final ValueChanged<String> onSubmit;

  /// 高度上限（null = 不限高，由宿主自己滚动）。超出时末尾内容被省略，
  /// 绝不允许顶出屏幕（见设计文档 §6.2）。
  final double? maxHeight;

  /// 历史版本号：宿主改动历史后自增，触发本面板重新读取历史。
  final int historyVersion;

  /// 非空时在热搜标题行显示「完整榜单 ›」入口。
  final VoidCallback? onOpenFullRank;

  /// 内容内边距（顶栏宿主传更紧凑的值以对齐搜索框行）。
  final EdgeInsets padding;

  @override
  State<SearchContentPanel> createState() => _SearchContentPanelState();
}

class _SearchContentPanelState extends State<SearchContentPanel> {
  /// 搜索历史（词）列表。
  List<String> _history = [];

  /// 搜索后交互过的作者/用户列表（数据口径唯一来源在服务层，此处只读）。
  List<SearchHistoryUser> get _users => SearchHistoryService().users;

  /// 热搜列表。
  List<SearchTrendingItemModel> _trending = [];
  bool _trendingLoading = true;

  /// 搜索建议列表。
  List<SearchSuggestItem> _suggests = [];
  Timer? _debounce;

  /// 是否显示建议（输入框有内容且已拿到建议）。
  bool get _showSuggests =>
      widget.controller.text.isNotEmpty && _suggests.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _history = SearchKeywordHistory.load();
    _loadTrending();
    widget.controller.addListener(_onTextChanged);
    SearchHistoryService().addListener(_onHistoryChanged);
  }

  @override
  void didUpdateWidget(SearchContentPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
    // 宿主改动历史（提交搜索 / 从结果页返回）后重新读取。
    if (oldWidget.historyVersion != widget.historyVersion) {
      setState(() => _history = SearchKeywordHistory.load());
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _debounce?.cancel();
    SearchHistoryService().removeListener(_onHistoryChanged);
    super.dispose();
  }

  void _onHistoryChanged() {
    if (mounted) setState(() {});
  }

  // ─────────────────────────── 数据加载 ───────────────────────────

  Future<void> _loadTrending() async {
    // 演示模式：不跑真实热搜（骨架占位由构建期分支给出）。
    if (Pref.demoMode) return;
    final res = await SearchHttp.searchTrending(limit: 20);
    if (!mounted) return;
    setState(() {
      _trendingLoading = false;
      if (res case Success(:final response)) {
        _trending = response.list ?? [];
      }
    });
  }

  void _refreshTrending() {
    if (Pref.demoMode) return;
    setState(() => _trendingLoading = true);
    _loadTrending();
  }

  void _onTextChanged() {
    final text = widget.controller.text;
    _debounce?.cancel();
    if (text.isEmpty) {
      setState(() => _suggests = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      final res = await SearchHttp.searchSuggest(term: text);
      if (!mounted) return;
      setState(() {
        if (res case Success(:final response)) {
          _suggests = response.tag ?? [];
        } else {
          _suggests = [];
        }
      });
    });
  }

  // ─────────────────────────── 历史操作（口径不变） ───────────────────────────

  void _removeHistory(String keyword) {
    setState(() => _history = SearchKeywordHistory.remove(_history, keyword));
  }

  void _clearHistory() {
    // 演示模式：不操作真实搜索历史。
    if (Pref.demoMode) return;
    showAppDialog(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: const Text('清空搜索历史'),
        content: const Text('确定要清空所有搜索历史吗？'),
        actions: [
          MiuixTextButton('取消', onPressed: () => Navigator.pop(ctx)),
          MiuixTextButton('清空', onPressed: () {
            SearchKeywordHistory.clear();
            SearchHistoryService().clearVisitedUsers();
            setState(() => _history = []);
            Navigator.pop(ctx);
          }),
        ],
      ),
    );
  }

  // ─────────────────────────── UI 构建 ───────────────────────────

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: widget.padding,
      child: (_showSuggests && !Pref.demoMode)
          ? _buildSuggestsList()
          : _buildMainContent(),
    );
    final maxHeight = widget.maxHeight;
    if (maxHeight == null) return content;
    // 限高 + 末尾省略：内容自然高度超过上限时，超出部分被裁掉（不溢出、
    // 不硬塞滚动条）。
    //
    // `fit: OverflowBoxFit.deferToChild` **必须显式指定**：`OverflowBox` 默认
    // `OverflowBoxFit.max` 会让自身 `sizedByParent` 并取 `constraints.biggest`
    // ——即无论内容多矮都撑满上限，正是"扩充区下方多出好几行空白"的根因；
    // deferToChild 才是「按内容高度、上限处截断」。
    return ClipRect(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: OverflowBox(
          fit: OverflowBoxFit.deferToChild,
          alignment: Alignment.topCenter,
          minHeight: 0,
          maxHeight: double.infinity,
          child: content,
        ),
      ),
    );
  }

  /// 主内容：历史 / 用户胶囊 / 热搜（演示模式用本地占位，布局对齐正常模式）。
  Widget _buildMainContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (Pref.demoMode) ...[
          _buildHistoryHeader(),
          const SizedBox(height: Style.sm),
          _buildHistoryChips(),
          const SizedBox(height: Style.sm),
          _buildVisitedUserChips(),
          const SizedBox(height: Style.lg),
        ] else if (_history.isNotEmpty || _users.isNotEmpty) ...[
          _buildHistoryHeader(),
          if (_history.isNotEmpty) ...[
            const SizedBox(height: Style.sm),
            _buildHistoryChips(),
          ],
          if (_users.isNotEmpty) ...[
            const SizedBox(height: Style.sm),
            _buildVisitedUserChips(),
          ],
          const SizedBox(height: Style.lg),
        ],
        _buildTrendingSection(),
      ],
    );
  }

  Widget _buildHistoryHeader() {
    final tokens = AppThemeHost.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          '搜索历史',
          style: tokens.text.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        GestureDetector(
          onTap: _clearHistory,
          child: AppIcon(AppIcons.delete(), size: 18, color: tokens.colors.outline),
        ),
      ],
    );
  }

  Widget _buildHistoryChips() {
    // 演示模式：本地占位胶囊（不展示真实搜索历史）。
    if (Pref.demoMode) {
      return Wrap(
        spacing: Style.sm,
        runSpacing: Style.sm,
        children: [
          for (final w in const [56.0, 72.0, 48.0, 84.0, 64.0])
            SkeletonBox(
              width: w,
              height: 32,
              borderRadius: BorderRadius.circular(100),
            ),
        ],
      );
    }
    return Wrap(
      spacing: Style.sm,
      runSpacing: Style.sm,
      children: _history.map((word) {
        return AppInputChip(
          label: Text(word),
          onSelected: (_) => widget.onSubmit(word),
          deleteIcon: AppIcon(AppIcons.clear(), size: 14),
          onDeleted: () => _removeHistory(word),
        );
      }).toList(),
    );
  }

  /// 第二行搜索历史：搜索后观看稿件对应的作者与直接访问过的用户空间用户。
  Widget _buildVisitedUserChips() {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;

    // 演示模式：本地演示用户卡片（程序图标 + WinWin，布局对齐正常模式）。
    if (Pref.demoMode) {
      return SizedBox(
        height: 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: 4,
          separatorBuilder: (_, _) => const SizedBox(width: Style.sm),
          itemBuilder: (context, index) => Container(
            padding: const EdgeInsets.only(left: 3, right: 10, top: 3, bottom: 3),
            decoration: BoxDecoration(
              color: cs.surfaceContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.4),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: AppIcon(
                    AppIcons.profile(),
                    size: 14,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  kDemoDisplayName,
                  style: TextStyle(fontSize: 12, color: cs.onSurface),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _users.length,
        separatorBuilder: (_, _) => const SizedBox(width: Style.sm),
        itemBuilder: (context, index) {
          final user = _users[index];
          return MiuixPressable(
            feedbackType: MiuixPressFeedbackType.sink,
            sinkAmount: 0.98,
            borderRadius: BorderRadius.circular(100),
            onPressed: () {
              Navigator.push(
                context,
                AppRoute(builder: (_) => MemberSpacePage(mid: user.mid)),
              );
            },
            onLongPress: () {
              SearchHistoryService().removeVisitedUser(user.mid);
            },
            child: Container(
              padding:
                  const EdgeInsets.only(left: 3, right: 10, top: 3, bottom: 3),
              decoration: BoxDecoration(
                color: cs.surfaceContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipOval(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: user.face.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: ImageUtils.thumbnailUrl(user.face,
                                  type: 'avatar'),
                              fit: BoxFit.cover,
                              memCacheWidth:
                                  ImageUtils.decodeClamp(24, context, max: 256),
                              memCacheHeight:
                                  ImageUtils.decodeClamp(24, context, max: 256),
                              placeholder: (_, _) => Container(
                                color: cs.surfaceContainerHigh,
                              ),
                              errorBuilder: (_, _, _) => AppIcon(
                                AppIcons.profile(),
                                size: 16,
                                color: cs.onSurfaceVariant,
                              ),
                            )
                          : AppIcon(
                              AppIcons.profile(),
                              size: 16,
                              color: cs.onSurfaceVariant,
                            ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(
                      user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: cs.onSurface),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTrendingSection() {
    // 演示模式：本地演示热搜（两列网格骨架占位，无序号）。
    if (Pref.demoMode) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTrendingHeader(onRefresh: null),
          const SizedBox(height: Style.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              final cellWidth =
                  (constraints.maxWidth - HotKeywordGrid.columnSpacing) / 2;
              return Wrap(
                spacing: HotKeywordGrid.columnSpacing,
                runSpacing: HotKeywordGrid.rowSpacing,
                children: [
                  for (var i = 0; i < 8; i++)
                    SizedBox(
                      width: cellWidth,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: SkeletonLine(width: double.infinity, height: 13),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      );
    }
    if (_trendingLoading) {
      return const Padding(
        padding: EdgeInsets.all(Style.xl),
        child: Center(child: AppProgressIndicator()),
      );
    }
    if (_trending.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTrendingHeader(onRefresh: _refreshTrending),
        const SizedBox(height: Style.sm),
        HotKeywordGrid(
          list: _trending,
          onTap: (keyword) {
            if (keyword.isNotEmpty) widget.onSubmit(keyword);
          },
        ),
      ],
    );
  }

  /// 热搜标题行：「大家都在搜」+（可选）「完整榜单 ›」+「刷新」。
  Widget _buildTrendingHeader({required VoidCallback? onRefresh}) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final onOpenFullRank = widget.onOpenFullRank;
    return Row(
      children: [
        Text(
          '大家都在搜',
          style: tokens.text.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        if (onOpenFullRank != null) ...[
          const SizedBox(width: Style.md),
          MiuixPressable(
            borderRadius: BorderRadius.circular(4),
            onPressed: onOpenFullRank,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Style.xs,
                vertical: 2,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '完整榜单',
                    style: TextStyle(fontSize: 13, color: cs.primary),
                  ),
                  AppIcon(
                    AppIcons.chevronForward(),
                    size: 16,
                    color: cs.primary,
                  ),
                ],
              ),
            ),
          ),
        ],
        const Spacer(),
        if (onRefresh != null)
          MiuixPressable(
            borderRadius: BorderRadius.circular(4),
            onPressed: onRefresh,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Style.xs,
                vertical: 2,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(
                    AppIcons.refresh(),
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: Style.xs),
                  Text(
                    '刷新',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// 搜索建议列表。
  Widget _buildSuggestsList() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final item in _suggests)
          MiuixBasicComponent(
            // 图标对齐行标题字号（MiuixBasicComponent 标题取 headline1），
            // 经 TextScaler 换算，与标题实际渲染高度一致。
            startAction: AppIcon(
              AppIcons.search(),
              size: appRowIconSize(context),
            ),
            title: item.name ?? '',
            onClick: () => widget.onSubmit(item.term ?? item.name ?? ''),
          ),
      ],
    );
  }
}

/// 顶栏宿主用的「清空」图标按钮（供宿主的搜索框 suffix 复用同一观感）。
class SearchClearButton extends StatelessWidget {
  const SearchClearButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return MiuixIconButton(
      onPressed: onPressed,
      child: AppIcon(AppIcons.clear(), size: 18),
    );
  }
}