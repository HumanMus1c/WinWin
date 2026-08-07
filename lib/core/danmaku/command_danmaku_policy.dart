// Ported from BiliPai (Kotlin) -> WinWin (Dart)
// Original: com/android/purebilibili/data/repository/CommandDanmakuPolicy.kt
//
// 命令弹幕（mode==7 高级弹幕中的命令类）分类与 JSON 字段提取。
//
// B 站 mode==7 的高级弹幕中，部分弹幕 content 为 JSON 命令串而非纯文本，
// 服务端据此触发特殊渲染（位置、变换、绘图等）。本策略负责：
//   1. 识别命令弹幕（JSON 含 cmd 字段）。
//   2. 按 cmd 值分类。
//   3. 提取各类型的关键字段供 UI/引擎使用。

import 'dart:convert';

/// 命令弹幕类型（B 站约定的 cmd 值子集）。
enum CommandDanmakuKind {
  /// 普通文本高级弹幕（非命令，content 为纯文本）。
  text,
  /// 定位弹幕（cmd=position 或 pos），含 x/y/rotation/duration。
  position,
  /// SVG 绘图弹幕（cmd=draw），content 内含 SVG 路径。
  draw,
  /// 换行弹幕（cmd=newline）。
  newline,
  /// 样式弹幕（cmd=style），含 fontSize/color/border。
  style,
  /// 未知命令类型（保留原始 cmd 字符串供调试）。
  unknown,
}

/// 命令弹幕解析结果。
class CommandDanmaku {
  /// 命令类型。
  final CommandDanmakuKind kind;
  /// 原始 cmd 字符串（kind==unknown 时保留）。
  final String? rawCmd;
  /// 定位坐标（x,y 像素，相对视频画面左上角）。
  final double? x;
  final double? y;
  /// 旋转角度（度）。
  final double? rotation;
  /// 持续时长（秒）。
  final double? duration;
  /// 透明度（0-1）。
  final double? opacity;
  /// 字号（磅）。
  final int? fontSize;
  /// 颜色（十进制 RGB）。
  final int? color;
  /// 描边颜色（十进制 RGB）。
  final int? borderColor;
  /// 绘图 SVG / 原始文本。
  final String? drawContent;
  /// 解析失败时的原始 content（供回退渲染）。
  final String? rawContent;

  const CommandDanmaku({
    required this.kind,
    this.rawCmd,
    this.x,
    this.y,
    this.rotation,
    this.duration,
    this.opacity,
    this.fontSize,
    this.color,
    this.borderColor,
    this.drawContent,
    this.rawContent,
  });

  /// 是否为命令弹幕（非纯文本）。
  bool get isCommand => kind != CommandDanmakuKind.text;
}

/// 命令弹幕策略：识别 + 分类 + 字段提取。
class CommandDanmakuPolicy {
  CommandDanmakuPolicy._();

  /// 判断 [content] 是否为命令弹幕。
  ///
  /// 命令弹幕的 content 为 JSON，且含 `cmd` 字段。非命令的纯文本返回 false。
  static bool isCommandDanmaku(String? content) {
    if (content == null || content.isEmpty) return false;
    final trimmed = content.trim();
    if (!trimmed.startsWith('{')) return false;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        return decoded.containsKey('cmd');
      }
    } catch (_) {
      // 非合法 JSON → 纯文本高级弹幕。
    }
    return false;
  }

  /// 解析命令弹幕。
  ///
  /// 非命令弹幕返回 [CommandDanmakuKind.text]；命令弹幕按 cmd 分类并提取字段。
  static CommandDanmaku parse(String? content) {
    if (content == null || content.isEmpty || !isCommandDanmaku(content)) {
      return CommandDanmaku(
        kind: CommandDanmakuKind.text,
        rawContent: content,
      );
    }

    final Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(content!.trim());
      if (decoded is! Map<String, dynamic>) {
        return CommandDanmaku(
          kind: CommandDanmakuKind.text,
          rawContent: content,
        );
      }
      json = decoded;
    } catch (_) {
      return CommandDanmaku(
        kind: CommandDanmakuKind.text,
        rawContent: content,
      );
    }

    final cmd = json['cmd']?.toString() ?? '';
    final kind = _classify(cmd);

    return CommandDanmaku(
      kind: kind,
      rawCmd: cmd,
      x: _asDouble(json['x']),
      y: _asDouble(json['y']),
      rotation: _asDouble(json['rotation'] ?? json['rotate']),
      duration: _asDouble(json['duration']),
      opacity: _asDouble(json['opacity'] ?? json['alpha']),
      fontSize: _asInt(json['fontSize'] ?? json['size']),
      color: _asInt(json['color']),
      borderColor: _asInt(json['borderColor'] ?? json['border']),
      drawContent: (json['draw'] ?? json['svg'])?.toString(),
      rawContent: content,
    );
  }

  /// 按 cmd 值分类。
  static CommandDanmakuKind _classify(String cmd) {
    switch (cmd.toLowerCase()) {
      case 'position':
      case 'pos':
        return CommandDanmakuKind.position;
      case 'draw':
        return CommandDanmakuKind.draw;
      case 'newline':
        return CommandDanmakuKind.newline;
      case 'style':
        return CommandDanmakuKind.style;
      default:
        return CommandDanmakuKind.unknown;
    }
  }

  /// 提取命令弹幕的可显示文本（draw 类型返回空，其余返回 rawContent）。
  ///
  /// 渲染层在命令弹幕无文本时不应显示占位文字。
  static String? extractDisplayText(CommandDanmaku parsed) {
    if (parsed.kind == CommandDanmakuKind.draw) return null;
    return parsed.rawContent;
  }

  static double? _asDouble(Object? value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static int? _asInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}
