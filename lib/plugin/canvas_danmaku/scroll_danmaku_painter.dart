import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:winwin/plugin/canvas_danmaku/base_danmaku_painter.dart';
import 'package:winwin/plugin/canvas_danmaku/models/danmaku_item.dart';

final class ScrollDanmakuPainter extends BaseDanmakuPainter {
  final double trackHeight;
  final List<List<DanmakuItem>> danmakuItems;
  final double durationInMilliseconds;

  const ScrollDanmakuPainter({
    required super.length,
    required this.trackHeight,
    required this.danmakuItems,
    required this.durationInMilliseconds,
    required super.fontSize,
    required super.fontWeight,
    required super.strokeWidth,
    required super.running,
    super.tick = 0,
    super.tickNotifier,
    super.repaint,
    super.batchThreshold,
  });

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    DanmakuItem? suspend;
    int suspendIndex = 0;
    for (int index = 0; index < danmakuItems.length; index++) {
      for (var i in danmakuItems[index]) {
        if (i.expired) continue;

        if (i.suspend) {
          suspend = i;
          suspendIndex = index;
          continue;
        }

        paintDanmaku(canvas, size, i, index * trackHeight);
      }
    }

    if (suspend case final suspend?) {
      paintDanmaku(canvas, size, suspend, suspendIndex * trackHeight);
    }

    canvas.restore();
  }

  void paintDanmaku(
    ui.Canvas canvas,
    ui.Size size,
    DanmakuItem item,
    double yPos,
  ) {
    item.drawParagraphIfNeeded(
      fontSize,
      fontWeight,
      strokeWidth,
    );
    final curTick = currentTick;
    if (!item.suspend) {
      final startPosition = size.width;
      final endPosition = -item.width;

      if (item.drawTick == null) {
        item
          ..drawTick = curTick
          ..xPosition = startPosition;
      } else {
        if (durationInMilliseconds.isNegative) {
          item.xPosition += (curTick - item.drawTick!) * durationInMilliseconds;
        } else {
          final distance = startPosition - endPosition;
          item.xPosition +=
              ((item.drawTick! - curTick) / durationInMilliseconds) * distance;
        }
      }

      if (item.xPosition < endPosition || item.xPosition > startPosition) {
        item.expired = true;
        return;
      }
    }

    BaseDanmakuPainter.paintItem(
      canvas,
      item,
      item.xPosition,
      yPos,
      strokeWidth,
    );

    item.drawTick = curTick;
  }
}
