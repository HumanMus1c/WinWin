import 'dart:ui' as ui;

import 'package:winwin/plugin/canvas_danmaku/models/danmaku_content_item.dart';
import 'package:winwin/plugin/canvas_danmaku/utils/utils.dart';

class DanmakuItem<T> {
  /// 弹幕内容
  final DanmakuContentItem<T> content;

  /// 弹幕宽度
  double width;

  /// 弹幕高度
  double height;

  /// 弹幕水平方向位置
  double xPosition;

  /// 上次绘制时间
  int? drawTick;

  /// 弹幕主体文本 Paragraph
  ui.Paragraph? paragraph;

  /// 弹幕描边文本 Paragraph
  ui.Paragraph? strokeParagraph;

  bool expired = false;

  bool suspend = false;

  @pragma("vm:prefer-inline")
  bool needRemove(bool needRemove) {
    if (needRemove) {
      dispose();
    }
    return needRemove;
  }

  void dispose() {
    paragraph?.dispose();
    paragraph = null;
    strokeParagraph?.dispose();
    strokeParagraph = null;
  }

  DanmakuItem({
    required this.content,
    required this.height,
    required this.width,
    this.xPosition = 0,
    this.paragraph,
    this.strokeParagraph,
    this.drawTick,
  });

  void drawParagraphIfNeeded(
    double fontSize,
    int fontWeight,
    double strokeWidth,
  ) {
    if (paragraph == null) {
      paragraph = DmUtils.generateParagraph(
        content: content,
        fontSize: fontSize,
        fontWeight: fontWeight,
      );
      if (strokeWidth > 0) {
        strokeParagraph = DmUtils.generateStrokeParagraph(
          content: content,
          fontSize: fontSize,
          fontWeight: fontWeight,
          strokeWidth: strokeWidth,
        );
      }
      width = paragraph!.maxIntrinsicWidth +
          strokeWidth +
          (content.selfSend ? 4.0 : 0.0);
      height = paragraph!.height + strokeWidth;
    }
  }

  @override
  String toString() {
    return 'DanmakuItem(content=$content, xPos=$xPosition, size=${ui.Size(width, height)}, drawTick=$drawTick)';
  }
}
