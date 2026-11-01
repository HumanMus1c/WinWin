import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/models/video/rec_video_item.dart';
import 'package:winwin/pages/rcmd/controller.dart';

/// 直接以 `List<dynamic>` 形参接收，绕开「具体模型列表」的静态类型检查，
/// 只保留 Dart 运行时的泛型校验行为 —— 这正是线上 `addAll` 抛错的现场。
void _addAllDynamic(List<dynamic> target, Iterable<dynamic> items) =>
    target.addAll(items);

void _addOneDynamic(List<dynamic> target, dynamic item) => target.add(item);

RcmdVideoItemModel _webItem(String bvid) => RcmdVideoItemModel.fromJson({
      'bvid': bvid,
      'pic': 'https://example.com/$bvid.jpg',
      'title': '标题 $bvid',
    });

void main() {
  group('首页推荐流合并的泛型不变量（2026-11-01 滚到底不加载回归）', () {
    test('addAll 基类/动态集合必抛 TypeError（禁止用法）', () {
      final list = <RcmdVideoItemModel>[_webItem('BV1a')];
      final added = <BaseRcmdVideoItemModel>[_webItem('BV1b')];
      expect(() => _addAllDynamic(list, added), throwsA(isA<TypeError>()));
    });

    test('逐条 add 走元素级校验，同源模型可正常追加', () {
      final list = <RcmdVideoItemModel>[_webItem('BV1a')];
      final added = <BaseRcmdVideoItemModel>[_webItem('BV1b')];
      _addOneDynamic(list, added.first);
      expect(list.map((e) => e.bvid), ['BV1a', 'BV1b']);
    });

    test('刷新合并：新批次在前、旧数据去重后在后，且不抛异常', () {
      final controller = RcmdController();
      controller.page = 0;
      final old = <RcmdVideoItemModel>[
        _webItem('BV1old1'),
        _webItem('BV1old2'),
      ];
      controller.loadingState.value = Success<List<dynamic>?>(old);
      final fresh = <RcmdVideoItemModel>[
        _webItem('BV1new'),
        _webItem('BV1old1'),
      ];

      expect(() => controller.handleListResponse(fresh), returnsNormally);
      expect(fresh.map((e) => e.bvid), ['BV1new', 'BV1old1', 'BV1old2']);
      // 新批次去重后 2 条（BV1old1 在旧列表里，但属于新批次），
      // 旧列表剩余 1 条 ⇒ 分隔位落在 2。
      expect(controller.lastRefreshAt, 2);
    });
  });
}
