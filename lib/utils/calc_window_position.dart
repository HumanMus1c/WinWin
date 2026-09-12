import 'package:collection/collection.dart';
import 'package:flutter/rendering.dart' show Offset, Size;
import 'package:screen_retriever/screen_retriever.dart';
import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/core/storage/storage_key.dart';

/// 动态计算窗口初始位置（对标 PiliPlus）。
///
/// 具备多显示器感知与光标位置感知能力：
/// 1. 获取当前所有可用显示器列表与当前鼠标指针所在屏幕坐标；
/// 2. 优先匹配鼠标当前所在的显示器，未命中时回退到主显示器；
/// 3. 读取本地持久化的窗口历史坐标，校验其是否仍然处于目标显示器的有效可见工作区内；
/// 4. 若有效则恢复该位置，若越界或无记录则在该显示器可见工作区内绝对居中呈现。
Future<Offset> calcWindowPosition(Size windowSize) async {
  final allDisplays = screenRetriever.getAllDisplays();
  final cursorScreenPoint = await screenRetriever.getCursorScreenPoint();

  final currentDisplay =
      (await allDisplays).firstWhereOrNull(
        (display) =>
            display.visiblePosition != null &&
            (display.visiblePosition! & display.size).contains(
              cursorScreenPoint,
            ),
      ) ??
      await screenRetriever.getPrimaryDisplay();

  final double visibleWidth;
  final double visibleHeight;
  if (currentDisplay.visibleSize case final size?) {
    visibleWidth = size.width;
    visibleHeight = size.height;
  } else {
    visibleWidth = currentDisplay.size.width;
    visibleHeight = currentDisplay.size.height;
  }

  final double visibleStartX;
  final double visibleStartY;
  if (currentDisplay.visiblePosition case final offset?) {
    visibleStartX = offset.dx;
    visibleStartY = offset.dy;
  } else {
    visibleStartX = visibleStartY = 0;
  }

  final rawPosition = GStorage.setting.get(SettingBoxKey.windowPosition);
  if (rawPosition is List && rawPosition.length >= 2) {
    try {
      final dx = (rawPosition[0] as num?)?.toDouble() ?? 0.0;
      final dy = (rawPosition[1] as num?)?.toDouble() ?? 0.0;
      if (dx >= visibleStartX &&
          dy >= visibleStartY &&
          dx < (visibleStartX + visibleWidth - 30) &&
          dy < (visibleStartY + visibleHeight - 30)) {
        return Offset(dx, dy);
      }
    } catch (_) {}
  }

  return Offset(
    visibleStartX + (visibleWidth / 2) - (windowSize.width / 2),
    visibleStartY + ((visibleHeight / 2) - (windowSize.height / 2)),
  );
}
