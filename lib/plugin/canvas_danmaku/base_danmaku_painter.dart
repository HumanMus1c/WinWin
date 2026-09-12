import 'package:flutter/material.dart';
import 'package:winwin/plugin/canvas_danmaku/models/danmaku_item.dart';

abstract base class BaseDanmakuPainter extends CustomPainter {
  final int length;
  final double fontSize;
  final int fontWeight;
  final double strokeWidth;
  final bool running;
  final int batchThreshold;
  final int tick;
  final ValueNotifier<int>? tickNotifier;

  int get currentTick => tickNotifier?.value ?? tick;

  static final Paint _selfSendPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0
    ..color = Colors.green;

  const BaseDanmakuPainter({
    required this.length,
    required this.fontSize,
    required this.fontWeight,
    required this.strokeWidth,
    required this.running,
    this.tick = 0,
    this.tickNotifier,
    this.batchThreshold = 10,
    super.repaint,
  });

  static void paintItem(
    Canvas canvas,
    DanmakuItem item,
    double dx,
    double dy,
    double strokeWidth,
  ) {
    final offset = Offset(
      dx + (strokeWidth / 2.0) + (item.content.selfSend ? 2.0 : 0.0),
      dy + strokeWidth / 2.0,
    );
    if (strokeWidth > 0) {
      if (item.strokeParagraph case final strokeP?) {
        canvas.drawParagraph(strokeP, offset);
      }
    }
    if (item.paragraph case final p?) {
      canvas.drawParagraph(p, offset);
    }
    if (item.content.selfSend) {
      _selfSendPaint.strokeWidth = strokeWidth > 0 ? strokeWidth : 1.0;
      canvas.drawRect(
        Rect.fromLTWH(dx, dy, item.width, item.height),
        _selfSendPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant BaseDanmakuPainter oldDelegate) {
    return oldDelegate.length != length ||
        oldDelegate.fontSize != fontSize ||
        oldDelegate.fontWeight != fontWeight ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.running != running;
  }
}
