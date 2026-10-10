import 'dart:async';

import 'package:flutter_miuix/miuix.dart' show MiuixBasicComponent, MiuixIconButton, MiuixPressFeedbackType, MiuixPressable;
import 'package:material_ui/material_ui.dart';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:winwin/common/skeleton/skeleton.dart';
import 'package:winwin/core/demo/demo_overrides.dart';
import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/search.dart';
import 'package:winwin/models/search/result.dart';
import 'package:winwin/models/search/suggest.dart';
import 'package:winwin/pages/member/member_space_page.dart';
import 'package:winwin/pages/search/search_result_page.dart';
import 'package:winwin/pages/search/services/search_history_service.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/utils/image_utils.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/core/shell/app_routes.dart';
import 'package:winwin/core/shell/app_dialogs.dart';
import 'package:winwin/ui/components/app_progress.dart';

/// 搜索页面 — 搜索框 + 热搜 + 历史 + 联想建议。
///
/// 移植自 PiliPlus 的 `SearchPage`，去除 GetX 依赖。
/// 搜索历史存储在 Hive `localCache` Box 的 `'searchHistory'` key。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  /// 搜索历史列表。
  List<String> _history = [];

  /// 搜索后交互过的作者/用户列表。
  List<SearchHistoryUser> get _visitedUsers => SearchHistoryService().users;

  /// 热搜列表。
  List<SearchTrendingItemModel> _trending = [];
  bool _trendingLoading = true;

  /// 搜索建议列表。
  List<SearchSuggestItem> _suggests = [];
  Timer? _debounce;

  /// 是否显示建议（输入框有内容时显示）。
  bool get _showSuggests => _controller.text.isNotEmpty && _suggests.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _loadTrending();
    _controller.addListener(_onTextChanged);
    SearchHistoryService().addListener(_onHistoryChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    SearchHistoryService().removeListener(_onHistoryChanged);
    super.dispose();
  }

  void _onHistoryChanged() {
    if (mounted) setState(() {});
  }

  // ─────────────────────────── 数据加载 ───────────────────────────

  void _loadHistory() {
    final list = GStorage.localCache.get('searchHistory');
    if (list is List) {
      _history = list.cast<String>();
    }
  }

  Future<void> _loadTrending() async {
    final res = await SearchHttp.searchTrending(limit: 20);
    if (!mounted) return;
    setState(() {
      _trendingLoading = false;
      if (res case Success(:final response)) {
        _trending = response.list ?? [];
      }
    });
  }

  void _onTextChanged() {
    final text = _controller.text;
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

  // ─────────────────────────── 搜索操作 ───────────────────────────

  void _submitSearch(String keyword) async {
    keyword = keyword.trim();
    if (keyword.isEmpty) return;
    _saveHistory(keyword);
    await Navigator.push(
      context,
      AppRoute(
        builder: (_) => SearchResultPage(keyword: keyword),
      ),
    );
    if (mounted) {
      _loadHistory();
      setState(() {});
    }
  }

  void _saveHistory(String keyword) {
    _history.remove(keyword);
    _history.insert(0, keyword);
    if (_history.length > 20) {
      _history = _history.sublist(0, 20);
    }
    GStorage.localCache.put('searchHistory', _history);
    setState(() {});
  }

  void _removeHistory(String keyword) {
    _history.remove(keyword);
    GStorage.localCache.put('searchHistory', _history);
    setState(() {});
  }

  void _clearHistory() {
    // 演示模式：不操作真实搜索历史。
    if (Pref.demoMode) return;
    showAppDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空搜索历史'),
        content: const Text('确定要清空所有搜索历史吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              _history.clear();
              GStorage.localCache.delete('searchHistory');
              SearchHistoryService().clearVisitedUsers();
              Navigator.pop(ctx);
              setState(() {});
            },
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── UI 构建 ───────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildSearchAppBar(),
      body: (_showSuggests && !Pref.demoMode)
          ? _buildSuggestsList()
          : _buildMainContent(),
    );
  }

  PreferredSizeWidget _buildSearchAppBar() {
    return AppBar(
      leading: const AppBackButton(),
      titleSpacing: 0,
      title: TextField(
        controller: _controller,
        focusNode: _focusNode,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onSubmitted: _submitSearch,
        decoration: InputDecoration(
          hintText: '搜索视频、UP主...',
          prefixIcon: AppIcon(AppIcons.search(), size: 20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(100),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: AppThemeHost.of(context).colors.surfaceContainer.withValues(alpha: 0.5),
          contentPadding: const EdgeInsets.symmetric(horizontal: Style.md),
          suffixIcon: _controller.text.isNotEmpty
              ? MiuixIconButton(

                  onPressed: () {
                    _controller.clear();
                    setState(() => _suggests = []);
                  },

                  child: AppIcon(AppIcons.clear(), size: 18),
              )
              : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _submitSearch(_controller.text),
          child: const Text('搜索'),
        ),
      ],
    );
  }

  /// 主内容：热搜 + 历史（演示模式使用本地演示数据，布局与正常模式对齐）。
  Widget _buildMainContent() {
    return ListView(
      padding: const EdgeInsets.all(Style.md),
      children: [
        if (Pref.demoMode) ...[
          _buildHistoryHeader(),
          const SizedBox(height: Style.sm),
          _buildHistoryChips(),
          const SizedBox(height: Style.sm),
          _buildVisitedUserChips(),
          const SizedBox(height: Style.lg),
        ] else if (_history.isNotEmpty || _visitedUsers.isNotEmpty) ...[
          _buildHistoryHeader(),
          if (_history.isNotEmpty) ...[
            const SizedBox(height: Style.sm),
            _buildHistoryChips(),
          ],
          if (_visitedUsers.isNotEmpty) ...[
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          '搜索历史',
          style: AppThemeHost.of(context).text.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        GestureDetector(
          onTap: _clearHistory,
          child: AppIcon(AppIcons.delete(),
              size: 18, color: AppThemeHost.of(context).colors.outline),
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
        return InputChip(
          label: Text(word),
          onSelected: (_) => _submitSearch(word),
          deleteIcon: AppIcon(AppIcons.clear(), size: 14),
          onDeleted: () => _removeHistory(word),
          visualDensity: VisualDensity.compact,
        );
      }).toList(),
    );
  }

  /// 第二行搜索历史：展示搜索后观看稿件对应的作者与直接访问过的用户空间用户。
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
            padding: const EdgeInsets.only(
              left: 3,
              right: 10,
              top: 3,
              bottom: 3,
            ),
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
        itemCount: _visitedUsers.length,
        separatorBuilder: (_, _) => const SizedBox(width: Style.sm),
        itemBuilder: (context, index) {
          final user = _visitedUsers[index];
          return MiuixPressable(
            feedbackType: MiuixPressFeedbackType.sink,
            sinkAmount: 0.98,
            borderRadius: BorderRadius.circular(100),
            onPressed: () {
              Navigator.push(
                context,
                AppRoute(
                  builder: (_) => MemberSpacePage(mid: user.mid),
                ),
              );
            },
            onLongPress: () {
              SearchHistoryService().removeVisitedUser(user.mid);
            },
            child: Container(
              padding: const EdgeInsets.only(
                left: 3,
                right: 10,
                top: 3,
                bottom: 3,
              ),
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
                              errorBuilder: (_, _, _) => AppIcon(AppIcons.profile(),
                                size: 16,
                                color: cs.onSurfaceVariant,
                              ),
                            )
                          : AppIcon(AppIcons.profile(),
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
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface,
                      ),
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
    // 演示模式：本地演示热搜（布局与正常模式一致：序号 + 标题/副标题占位）。
    if (Pref.demoMode) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '大家都在搜',
            style: AppThemeHost.of(context).text.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: Style.sm),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 8,
            itemBuilder: (context, index) => MiuixBasicComponent(
              insideMargin: EdgeInsets.zero,
              startAction: SizedBox(
                width: 28,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: index < 3 ? biliPink : null,
                    fontWeight:
                        index < 3 ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              content: [
                const SkeletonLine(width: double.infinity, height: 13),
                if (index.isEven)
                  const SkeletonLine(width: 120, height: 10),
              ],
            ),
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
        Text(
          '大家都在搜',
          style: AppThemeHost.of(context).text.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: Style.sm),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _trending.length,
          itemBuilder: (context, index) {
            final item = _trending[index];
            return MiuixBasicComponent(
              insideMargin: EdgeInsets.zero,
              startAction: SizedBox(
                width: 28,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: index < 3 ? biliPink : null,
                    fontWeight: index < 3 ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              title: item.keyword ?? '',
              summary: item.recommendReason,
              onClick: () => _submitSearch(item.keyword ?? ''),
            );
          },
        ),
      ],
    );
  }

  /// 搜索建议列表。
  Widget _buildSuggestsList() {
    return ListView.builder(
      itemCount: _suggests.length,
      itemBuilder: (context, index) {
        final item = _suggests[index];
        return MiuixBasicComponent(
          startAction: AppIcon(AppIcons.search(), size: 18),
          title: item.name ?? '',
          onClick: () => _submitSearch(item.term ?? item.name ?? ''),
        );
      },
    );
  }
}
