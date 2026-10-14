import 'package:material_ui/material_ui.dart';

import 'package:winwin/common/widgets/demo_mask.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/models/search/search_type.dart';
import 'package:winwin/pages/search/search_panel.dart';
import 'package:winwin/core/shell/app_scaffold.dart';
import 'package:winwin/ui/components/app_tab_view.dart';

/// 搜索结果页 — TabBar 分类 + TabBarView 结果列表。
///
/// 移植自 PiliPlus 的 `SearchResultPage`，去除 GetX 依赖。
/// 每个分类对应一个 [SearchPanel]，通过 [SearchType] 决定渲染方式。
class SearchResultPage extends StatefulWidget {
  const SearchResultPage({super.key, required this.keyword});

  final String keyword;

  @override
  State<SearchResultPage> createState() => _SearchResultPageState();
}

class _SearchResultPageState extends State<SearchResultPage> {
  late AppTabController _tabController;

  static const List<SearchType> _tabs = SearchType.values;

  @override
  void initState() {
    super.initState();
    _tabController = AppTabController(length: _tabs.length);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      // 仅保留分类标签条（无标题栏）。Tab 头/体改用 Miuix 轨道替身。
      topBar: AppTabBar(
        controller: _tabController,
        tabs: _tabs.map((t) => t.label).toList(),
      ),
      body: Pref.demoMode ? const DemoListSkeleton() : AppTabBody(
        controller: _tabController,
        children: _tabs
            .map((t) => SearchPanel(
                  keyword: widget.keyword,
                  searchType: t,
                ))
            .toList(),
      ),
    );
  }
}
