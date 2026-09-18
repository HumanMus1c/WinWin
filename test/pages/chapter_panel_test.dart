import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/models/video/play_info.dart';

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
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                const panelWidth = 300.0;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // 底层视频/播放器区域
                    const Positioned.fill(
                      child: ColoredBox(color: Colors.blue),
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
                                      ? Colors.black.withValues(alpha: 0.25)
                                      : Colors.transparent,
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
                                  color: Colors.black87,
                                  child: Column(
                                    children: [
                                      const Text('章节 (2)'),
                                      for (final ch in testChapters)
                                        Material(
                                          color: Colors.transparent,
                                          child: ListTile(
                                            title: Text(ch.title),
                                            onTap: () {
                                              itemTappedCount++;
                                            },
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
