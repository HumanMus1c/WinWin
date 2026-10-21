import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/models/search/result.dart';
import 'package:winwin/pages/search/widgets/hot_keyword.dart';

import '../support/app_test_host.dart';

/// 顿挫取证的**最小复现**：量出「加载骨架」与「真实网格」在相同宽度下的高度，
/// 判断二者是否逐像素相等（不等 ⇒ 换真身时子尺寸变化 ⇒ `AnimatedSize` 从 0 重跑）。
void main() {
  const probeKey = Key('height-probe');

  List<SearchTrendingItemModel> items(int n) => List<SearchTrendingItemModel>.generate(
        n,
        (i) => SearchTrendingItemModel(keyword: '关键字$i', showName: '关键字$i'),
      );

  Future<double> measure(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      AppTestApp(
        home: AppTestScaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: KeyedSubtree(key: probeKey, child: child),
            ),
          ),
        ),
      ),
    );
    return tester.getSize(find.byKey(probeKey)).height;
  }

  Future<void> report(WidgetTester tester, String tag, Widget child) async {
    final h = await measure(tester, child);
    debugPrint('[HEIGHT] $tag = $h');
  }

  testWidgets('热搜：骨架 vs 网格 高度对比', (tester) async {
    await report(tester, 'skeleton(20)', const HotKeywordSkeleton(itemCount: 20));
    await report(tester, 'grid(20)', HotKeywordGrid(list: items(20), onTap: (_) {}));
    await report(tester, 'skeleton(16)', const HotKeywordSkeleton(itemCount: 16));
    await report(tester, 'grid(16)', HotKeywordGrid(list: items(16), onTap: (_) {}));
    await report(tester, 'skeleton(10)', const HotKeywordSkeleton(itemCount: 10));
    await report(tester, 'grid(10)', HotKeywordGrid(list: items(10), onTap: (_) {}));
  });
}