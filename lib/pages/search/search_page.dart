import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart' show MiuixIconButton, MiuixTextButton;

import 'package:winwin/core/shell/app_routes.dart';
import 'package:winwin/core/shell/app_scaffold.dart';
import 'package:winwin/pages/search/search_result_page.dart';
import 'package:winwin/pages/search/services/search_history_service.dart';
import 'package:winwin/pages/search/widgets/search_content_panel.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/app_components.dart';

/// 搜索页面 — 搜索框 + 历史 + 用户胶囊 + 热搜 + 联想建议。
///
/// 移植自 PiliPlus 的 `SearchPage`，去除 GetX 依赖。
/// 搜索历史存储在 Hive `localCache` Box 的 `'searchHistory'` key。
///
/// 2026-10-19：内容区收敛为共用面板 [SearchContentPanel]（与首页顶栏搜索态
/// 扩充区同一份实现，P4 单一来源）；本页保留为**独立搜索入口 / 完整榜单**形态。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  /// 历史版本号：提交 / 从结果页返回后自增，驱动面板重读历史。
  int _historyVersion = 0;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ─────────────────────────── 搜索操作 ───────────────────────────

  Future<void> _submitSearch(String keyword) async {
    final word = keyword.trim();
    if (word.isEmpty) return;
    // 口径不变：SearchKeywordHistory 去重后置顶、上限 20。
    SearchKeywordHistory.push(SearchKeywordHistory.load(), word);
    setState(() => _historyVersion++);
    await Navigator.push(
      context,
      AppRoute(
        builder: (_) => SearchResultPage(keyword: word),
      ),
    );
    if (mounted) {
      setState(() => _historyVersion++);
    }
  }

  // ─────────────────────────── UI 构建 ───────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      // 搜索行自绘（reserveTopStrip: false）；返回键由壳层单实例承担（与
      // `SearchResultPage` 严格同构，此处仅保留 56 宽槽位）。
      reserveTopStrip: false,
      topBar: _buildSearchTopBar(),
      body: SingleChildScrollView(
        child: SearchContentPanel(
          controller: _controller,
          onSubmit: _submitSearch,
          historyVersion: _historyVersion,
        ),
      ),
    );
  }

  /// 搜索顶栏（自绘行，替 Material `AppBar`）：返回键由壳层单实例承担
  /// （固定位于顶部安全行默认位，见 `global_back_button.dart`）——此处只保留
  /// 56 宽槽位让输入框原位不被遮挡；与 `SearchResultPage` 的 topBar 同尺寸同位。
  Widget _buildSearchTopBar() {
    return Padding(
      // 顶部不留内边距：使本行纵向中心与壳层返回按钮的默认位对齐。
      padding: const EdgeInsets.fromLTRB(0, 0, Style.sm, Style.sm),
      child: Row(
        children: [
          const SizedBox(width: 56, height: AppScaffold.topStripHeight),
          Expanded(
            child: AppCapsuleTextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: _submitSearch,
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
          MiuixTextButton('搜索', onPressed: () => _submitSearch(_controller.text)),
        ],
      ),
    );
  }
}