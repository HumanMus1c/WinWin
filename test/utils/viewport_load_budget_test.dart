import 'package:flutter_test/flutter_test.dart';

import 'package:winwin/utils/viewport_load_budget.dart';

void main() {
  group('ViewportLoadBudget.visibleRows', () {
    test('按视口高度与行高取整，并受上下限约束', () {
      expect(
        ViewportLoadBudget.visibleRows(
          viewportExtent: 720,
          rowExtent: 72,
        ),
        10,
      );
      expect(
        ViewportLoadBudget.visibleRows(
          viewportExtent: 40,
          rowExtent: 72,
        ),
        1,
      );
      expect(
        ViewportLoadBudget.visibleRows(
          viewportExtent: 5000,
          rowExtent: 72,
        ),
        ViewportLoadBudget.maxRowsPerViewport,
      );
      expect(
        ViewportLoadBudget.visibleRows(
          viewportExtent: 720,
          rowExtent: 0,
        ),
        1,
      );
    });
  });

  group('ViewportLoadBudget.visibleGridItems', () {
    test('网格条目数 = 行数 × 列数（列数向上取整）', () {
      expect(
        ViewportLoadBudget.visibleGridItems(
          viewportExtent: 640,
          viewportWidth: 1280,
          rowExtent: 98,
          maxCrossAxisExtent: 240,
        ),
        6 * 6,
      );
    });
  });

  group('ViewportLoadBudget.capRequestItems', () {
    test('冷启动最多 2 屏，滚动最多 1 屏', () {
      expect(
        ViewportLoadBudget.capRequestItems(
          fallback: 100,
          visibleItems: 9,
          firstPage: true,
        ),
        18,
      );
      expect(
        ViewportLoadBudget.capRequestItems(
          fallback: 100,
          visibleItems: 9,
          firstPage: false,
        ),
        9,
      );
    });

    test('原页大小小于预算时只收紧不放大', () {
      expect(
        ViewportLoadBudget.capRequestItems(
          fallback: 20,
          visibleItems: 30,
          firstPage: false,
        ),
        20,
      );
      expect(
        ViewportLoadBudget.capRequestItems(
          fallback: 20,
          visibleItems: 30,
          firstPage: true,
        ),
        20,
      );
    });
  });
}
