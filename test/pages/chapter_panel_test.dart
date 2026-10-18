import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_test_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Chapter Panel Interaction Tests', () {
    testWidgets(
        'Tapping outside chapter panel triggers dismiss while tapping inside does not',
        (tester) async {
      bool isOpen = true;
      int itemTappedCount = 0;

      final testChapters = [
        const ViewPoint(from: 0, to: 30, title: 'Chapter 1'),
        const ViewPoint(from: 30, to: 90, title: 'Chapter 2'),
      ];

      await tester.pumpWidget(
        AppTestApp(
          home: AppTestScaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                const panelWidth = 300.0;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // 底层视频/播放器区域
                    const Positioned.fill(
                      child: ColoredBox(color: Color(0xFF2196F3)),
                    ),
                    // 模拟顶层章节面板及其 Dismiss 遮罩
                    Positioned.fill(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // 1. 面板外 Dismiss 遮罩
                          Positioned.fill(
                            child: IgnorePointer(
                              ignoring: !isOpen,
                              child: GestureDetector(
                                key: const ValueKey('dismiss_barrier'),
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  setState(() => isOpen = false);
                                },
                                child: Container(
                                  color: isOpen
                                      ? const Color(0x40000000)
                                      : const Color(0x00000000),
                                ),
                              ),
                            ),
                          ),
                          // 2. 右侧面板本体
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 260),
                            right: isOpen ? 0 : -panelWidth - 10,
                            top: 0,
                            bottom: 0,
                            width: panelWidth,
                            child: IgnorePointer(
                              ignoring: !isOpen,
                              child: GestureDetector(
                                key: const ValueKey('panel_body'),
                                behavior: HitTestBehavior.opaque,
                                onTap: () {}, // 吸收点击
                                child: Container(
                                  color: const Color(0xDD000000),
                                  child: Column(
                                    children: [
                                      const Text('章节 (2)'),
                                      for (final ch in testChapters)
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () {
                                            itemTappedCount++;
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.all(16),
                                            child: Text(ch.title),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );

      // 验证初始状态处于展开
      expect(isOpen, isTrue);
      expect(find.text('Chapter 1'), findsOneWidget);

      // 点击右侧面板内部条目
      await tester.tap(find.text('Chapter 1'));
      await tester.pumpAndSettle();
      expect(itemTappedCount, 1);
      // 面板内部点击不应触发 dismiss
      expect(isOpen, isTrue);

      // 点击左侧视频区域（Dismiss 遮罩区域，坐标 Offset(50, 200) 在宽度 800 的屏幕左侧）
      await tester.tapAt(const Offset(50, 200));
      await tester.pumpAndSettle();

      // 验证已被成功 Dismiss 关闭
      expect(isOpen, isFalse);
    });
  });
}

/// 章节数据（最小组件替身，仅供本用例构建列表）。
class ViewPoint {
  const ViewPoint({required this.from, required this.to, required this.title});
  final int from;
  final int to;
  final String title;
}