import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart' show MiuixIconButton, MiuixTextButton;

import 'package:winwin/common/widgets/demo_mask.dart';
import 'package:winwin/core/shell/app_scaffold.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/models/search/search_type.dart';
import 'package:winwin/pages/search/search_panel.dart';
import 'package:winwin/pages/search/services/search_history_service.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/app_components.dart'
    show AppCapsuleTextField;
import 'package:winwin/ui/components/app_tab_view.dart';

/// 搜索结果页 — 搜索输入条 + 分类标签条 + 结果列表。
///
/// 移植自 PiliPlus 的 `SearchResultPage`，去除 GetX 依赖。
/// 每个分类对应一个 [SearchPanel]，通过 [SearchType] 决定渲染方式。
/// 顶部输入条支持页内二次搜索（改写关键词并重载各分类结果）。
class SearchResultPage extends StatefulWidget {
  const SearchResultPage({super.key, required this.keyword});

  final String keyword;

  @override
  State<SearchResultPage> createState() => _SearchResultPageState();
}

class _SearchResultPageState extends State<SearchResultPage> {
  late AppTabController _tabController;
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  /// 当前结果对应的关键词（页内二次搜索时改写）。
  late String _keyword;

  static const List<SearchType> _tabs = SearchType.values;

  @override
  void initState() {
    super.initState();
    _keyword = widget.keyword;
    _controller = TextEditingController(text: _keyword);
    _focusNode = FocusNode();
    _tabController = AppTabController(length: _tabs.length);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// 页内二次搜索：沿用搜索入口页的关键词历史口径，并重载各分类结果。
  void _submit(String raw) {
    final keyword = raw.trim();
    if (keyword.isEmpty) return;
    _focusNode.unfocus();
    SearchKeywordHistory.push(SearchKeywordHistory.load(), keyword);
    if (keyword == _keyword) return;
    setState(() => _keyword = keyword);
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      // 输入条自带返回键（不再用壳层顶部安全行的悬浮返回）：本页无标题栏，
      // 返回键落在搜索行最左，与上级搜索页 `AppBar(leading: ...)` 同位对齐。
      reserveTopStrip: false,
      // 输入条 + 分类标签条。Tab 头/体使用 Miuix 轨道替身。
      topBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, Style.sm, Style.sm, Style.sm),
            child: Row(
              children: [
                // 与上级搜索页 `AppBar(leading: const AppBackButton())` 同位：
                // leading 槽宽 56、按钮居中（图标中心 x≈28），输入框紧随其后
                // （上级页 titleSpacing: 0 → 输入框同样起于 x≈56）。
                const SizedBox(
                  width: 56,
                  child: Center(child: AppBackButton()),
                ),
                Expanded(
                  child: AppCapsuleTextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    textInputAction: TextInputAction.search,
                    onSubmitted: _submit,
                    hint: '搜索视频、UP主...',
                    prefix: AppIcon(AppIcons.search(), size: 20),
                    suffix: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _controller,
                      builder: (context, value, _) {
                        if (value.text.isEmpty) return const SizedBox.shrink();
                        return MiuixIconButton(
                          onPressed: _controller.clear,
                          child: AppIcon(AppIcons.clear(), size: 18),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: Style.sm),
                MiuixTextButton(
                  '搜索',
                  onPressed: () => _submit(_controller.text),
                ),
              ],
            ),
          ),
          AppTabBar(
            controller: _tabController,
            tabs: _tabs.map((t) => t.label).toList(),
          ),
        ],
      ),
      body: Pref.demoMode
          ? const DemoListSkeleton()
          : AppTabBody(
              controller: _tabController,
              children: _tabs
                  .map(
                    (t) => SearchPanel(
                      // 关键词变化时重建各分类面板（面板在 initState 发起请求）。
                      key: ValueKey('$_keyword-${t.name}'),
                      keyword: _keyword,
                      searchType: t,
                    ),
                  )
                  .toList(),
            ),
    );
  }
}
