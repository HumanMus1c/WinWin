import 'dart:math' show min;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:winwin/plugin/canvas_danmaku/base_danmaku_painter.dart';
import 'package:winwin/plugin/canvas_danmaku/models/danmaku_content_item.dart';
import 'package:winwin/plugin/canvas_danmaku/models/danmaku_item.dart';
import 'package:winwin/plugin/canvas_danmaku/utils/utils.dart';

final class SpecialDanmakuPainter extends BaseDanmakuPainter {
  List<DanmakuItem> danmakuItems;

  SpecialDanmakuPainter({
    required super.length,
    required this.danmakuItems,
    required super.fontSize,
    required super.fontWeight,
    required super.strokeWidth,
    required super.running,
    super.tick = 0,
    super.tickNotifier,
    super.repaint,
    super.batchThreshold,
  });

  void paintDanmaku(ui.Canvas canvas, ui.Size size, DanmakuItem item) {
    final curTick = currentTick;
    final elapsed = curTick - (item.drawTick ??= curTick);
    final content = item.content as SpecialDanmakuContentItem;
    if (0 <= elapsed && elapsed < content.duration) {
      _paintSpecialDanmaku(canvas, item, content, size, elapsed);
    } else {
      item.expired = true;
    }
  }

  @pragma("vm:prefer-inline")
  void _paintSpecialDanmaku(Canvas canvas, DanmakuItem dm,
      SpecialDanmakuContentItem item, Size size, int elapsed) {
    // 位移动画
    double dx, dy;
    if (elapsed > item.translationStartDelay) {
      late final translateProgress = item.easingType.transform(min(1.0,
          (elapsed - item.translationStartDelay) / item.translationDuration));

      double getOffset(Tween<double> tween) => tween is ConstantTween
          ? tween.begin!
          : tween.transform(translateProgress);

      dx = getOffset(item.translateXTween) * size.width;
      dy = getOffset(item.translateYTween) * size.height;
    } else {
      dx = item.translateXTween.begin! * size.width;
      dy = item.translateYTween.begin! * size.height;
    }
    dx += item.rect.left;
    dy += item.rect.top;

    final paragraph = dm.paragraph ??= DmUtils.generateSpecialParagraph(
      content: item,
      fontWeight: fontWeight,
      strokeWidth: strokeWidth,
    );

    canvas.save();
    canvas.translate(dx, dy);
    canvas.drawParagraph(paragraph, Offset.zero);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (var i in danmakuItems) {
      if (i.expired) continue;

      paintDanmaku(canvas, size, i);
    }
  }
}
