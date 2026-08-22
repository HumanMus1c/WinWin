import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:winwin/plugin/canvas_danmaku/models/danmaku_content_item.dart';

abstract final class DmUtils {
  static double devicePixelRatio = 1;
  static final Paint _selfSendPaint = Paint()
    ..style = PaintingStyle.stroke
    ..color = Colors.green;

  static void updateSelfSendPaint(double strokeWidth) {
    _selfSendPaint.strokeWidth = strokeWidth;
  }

  static ui.Paragraph generateParagraph({
    required DanmakuContentItem content,
    required double fontSize,
    required int fontWeight,
  }) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.left,
      fontWeight: FontWeight.values[fontWeight],
      textDirection: TextDirection.ltr,
      maxLines: 1,
    ));

    if (content.count case final count?) {
      builder
        ..pushStyle(ui.TextStyle(
          color: content.color,
          fontSize: fontSize * 0.6,
        ))
        ..addText('($count)')
        ..pop();
    }

    builder
      ..pushStyle(ui.TextStyle(color: content.color, fontSize: fontSize))
      ..addText(content.text);

    return builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
  }

  static ui.Paragraph generateStrokeParagraph({
    required DanmakuContentItem content,
    required double fontSize,
    required int fontWeight,
    required double strokeWidth,
  }) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.left,
      fontWeight: FontWeight.values[fontWeight],
      textDirection: TextDirection.ltr,
      maxLines: 1,
    ));
    final Paint strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    if (content.isColorful) {
      strokePaint.shader = const LinearGradient(
        colors: [Color(0xFFF2509E), Color(0xFF308BCD)],
      ).createShader(const Rect.fromLTWH(0, 0, 300, 30));
    } else {
      strokePaint.color = Colors.black;
    }

    if (content.count case final count?) {
      builder
        ..pushStyle(ui.TextStyle(
          fontSize: fontSize * 0.6,
          foreground: strokePaint,
        ))
        ..addText('($count)')
        ..pop();
    }

    builder
      ..pushStyle(ui.TextStyle(fontSize: fontSize, foreground: strokePaint))
      ..addText(content.text);

    return builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));
  }

  static ui.Paragraph generateSpecialParagraph({
    required SpecialDanmakuContentItem content,
    required int fontWeight,
    required double strokeWidth,
  }) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.left,
      fontWeight: FontWeight.values[fontWeight],
      textDirection: TextDirection.ltr,
      fontSize: content.fontSize,
    ))
      ..pushStyle(ui.TextStyle(
        color: content.color,
        fontSize: content.fontSize,
        shadows: content.hasStroke && strokeWidth > 0
            ? [Shadow(color: Colors.black, blurRadius: strokeWidth)]
            : null,
      ))
      ..addText(content.text);

    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));

    final totalWidth = paragraph.maxIntrinsicWidth + strokeWidth;
    final totalHeight = paragraph.height + strokeWidth;

    if (content.rotateZ != 0 || content.matrix != null) {
      content.rect = calculateRotatedBounds(
        totalWidth,
        totalHeight,
        content.rotateZ,
        content.matrix,
      );
    } else {
      content.rect = Rect.fromLTWH(0, 0, totalWidth, totalHeight);
    }

    return paragraph;
  }

  static Rect calculateRotatedBounds(
    double w,
    double h,
    double rotateZ,
    Matrix4? matrix,
  ) {
    final double cosZ;
    final double cosY;
    final double sinZ;
    if (matrix == null) {
      cosZ = cos(rotateZ);
      sinZ = sin(rotateZ);
      cosY = 1;
    } else {
      cosZ = matrix[5];
      sinZ = matrix[1];
      cosY = matrix[10];
    }

    final wx = w * cosZ * cosY;
    final wy = w * sinZ;
    final hx = -h * sinZ * cosY;
    final hy = h * cosZ;

    final minX = _min4(0.0, wx, hx, wx + hx);
    final maxX = _max4(0.0, wx, hx, wx + hx);
    final minY = _min4(0.0, wy, hy, wy + hy);
    final maxY = _max4(0.0, wy, hy, wy + hy);

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  @pragma("vm:prefer-inline")
  static double _min4(double a, double b, double c, double d) {
    final ab = a < b ? a : b;
    final cd = c < d ? c : d;
    return ab < cd ? ab : cd;
  }

  @pragma("vm:prefer-inline")
  static double _max4(double a, double b, double c, double d) {
    final ab = a > b ? a : b;
    final cd = c > d ? c : d;
    return ab > cd ? ab : cd;
  }
}
