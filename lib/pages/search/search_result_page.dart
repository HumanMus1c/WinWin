import 'package:flutter/material.dart';

import 'package:winwin/models/search/search_type.dart';
import 'package:winwin/pages/search/search_panel.dart';
import 'package:winwin/theme/app_icons.dart';

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

class _SearchResultPageState extends State<SearchResultPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const List<SearchType> _tabs = SearchType.values;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(
          widget.keyword,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: _tabs.map((t) => Tab(text: t.label)).toList(),
        ),
      ),
      body: TabBarView(
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
