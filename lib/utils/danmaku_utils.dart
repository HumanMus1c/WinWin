import 'package:flutter/widgets.dart';

import 'package:winwin/plugin/canvas_danmaku/canvas_danmaku.dart';

/// 弹幕工具集（移植自 PiliPlus `lib/utils/danmaku_utils.dart`）。
///
/// 纯 Dart 逻辑，无平台依赖：
/// - [decimalToColor]：B 站弹幕颜色（十进制 int，RGB 24 位）→ Flutter [Color]。
/// - [getPosition]：弹幕 mode（1/4/5/7…）→ 渲染引擎 [DanmakuItemType]。
abstract final class DmUtils {
  /// 十进制颜色（如 16777215 = 0xFFFFFF）转 [Color]，高位补 alpha=255。
  static Color decimalToColor(int decimalColor) =>
      Color(decimalColor | 0xFF000000);

  /// 弹幕 mode → 渲染类型。
  ///
  /// B 站 mode 约定：1/2/3=滚动，4=底部，5=顶部，7=高级（special），
  /// 其余按滚动处理。
  static DanmakuItemType getPosition(int mode) => switch (mode) {
        4 => DanmakuItemType.bottom,
        5 => DanmakuItemType.top,
        7 => DanmakuItemType.special,
        _ => DanmakuItemType.scroll,
      };
}
