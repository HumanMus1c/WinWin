// B7-c3 补丁回归：底栏导航字形的线条/填充分层。
//
// 背景：Miuix 素材集 home/recent/messages 仅实心版、bell 仅 os4 线条版
// （渲染实测：实心墨迹占比 ≈27-32%，线条参照 ≈11%）——未选中（线条）字形
// 不映射、回退 Cupertino 线条字形；填充字形保持矢量映射。
// 若未来补齐线条素材（b7-d 美术批），更新映射的同时同步本测试。
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:winwin/theme/app_icons.dart';

void main() {
  test('导航未选中字形回退线条、选中字形保持矢量映射', () {
    // 未选中（线条）→ 应回退字形（无矢量映射）。
    expect(miuixVectorForGlyph(CupertinoIcons.house), isNull);
    expect(miuixVectorForGlyph(CupertinoIcons.clock), isNull);
    expect(miuixVectorForGlyph(CupertinoIcons.chat_bubble_2), isNull);
    expect(miuixVectorForGlyph(CupertinoIcons.bell_fill), isNull);
    // 选中（填充）→ 保持矢量映射。
    expect(miuixVectorForGlyph(CupertinoIcons.house_fill), isNotNull);
    expect(miuixVectorForGlyph(CupertinoIcons.clock_fill), isNotNull);
    expect(miuixVectorForGlyph(CupertinoIcons.chat_bubble_2_fill), isNotNull);
    expect(miuixVectorForGlyph(CupertinoIcons.bell), isNotNull);
  });
}
