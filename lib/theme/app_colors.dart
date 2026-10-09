// 媒体/语义“绝对色”常量口（B6-6）。
//
// 取值与 Flutter material `Colors` 对应项逐位一致（由 SDK colors.dart 生成，
// 零视觉变化）；替代 lib 内对 material_ui `Colors` 的直接依赖，为 B7 摘除
// 依赖提供非 Material 的颜色来源。语义化精修（如红→error）属后续批次。

import 'dart:ui' show Color;

abstract final class AppColors {
  static const Color transparent = Color(0x00000000);
  static const Color black = Color(0xFF000000);
  static const Color white = Color(0xFFFFFFFF);
  static const Color black87 = Color(0xDD000000);
  static const Color black54 = Color(0x8A000000);
  static const Color black45 = Color(0x73000000);
  static const Color black38 = Color(0x61000000);
  static const Color black26 = Color(0x42000000);
  static const Color black12 = Color(0x1F000000);
  static const Color white70 = Color(0xB3FFFFFF);
  static const Color white60 = Color(0x99FFFFFF);
  static const Color white54 = Color(0x8AFFFFFF);
  static const Color white38 = Color(0x62FFFFFF);
  static const Color white30 = Color(0x4DFFFFFF);
  static const Color white24 = Color(0x3DFFFFFF);
  static const Color white12 = Color(0x1FFFFFFF);
  static const Color white10 = Color(0x1AFFFFFF);
  static const Color red = Color(0xFFF44336);
  static const Color redAccent = Color(0xFFFF5252);
  static const Color grey = Color(0xFF9E9E9E);
  static const Color grey600 = Color(0xFF757575);
  static const Color orange = Color(0xFFFF9800);
  static const Color orange700 = Color(0xFFF57C00);
  static const Color orange800 = Color(0xFFEF6C00);
  static const Color orangeAccent = Color(0xFFFFAB40);
  static const Color amber = Color(0xFFFFC107);
  static const Color amber600 = Color(0xFFFFB300);
  static const Color amber700 = Color(0xFFFFA000);
  static const Color amberAccent = Color(0xFFFFD740);
  static const Color pink = Color(0xFFE91E63);
  static const Color pink600 = Color(0xFFD81B60);
  static const Color green = Color(0xFF4CAF50);
  static const Color greenAccent = Color(0xFF69F0AE);
  static const Color blue = Color(0xFF2196F3);
  static const Color blue600 = Color(0xFF1E88E5);
}
