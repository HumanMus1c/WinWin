import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// 系统字体信息。
///
/// [family] 是唯一标识键（如 "Microsoft YaHei Bold"），供持久化存储与匹配使用。
/// [actualFamily] 是底层 DirectWrite 基础字体族名（如 "Microsoft YaHei"）。
/// [label] 是显示名称，优先中文全名（如 "微软雅黑 Bold"）。
/// [weight] 是具体字重（如 [FontWeight.w700]）。
/// [isItalic] 是否为斜体。
class FontInfo {
  final String family;
  final String actualFamily;
  final String label;
  final FontWeight weight;
  final bool isItalic;

  const FontInfo({
    required this.family,
    required this.actualFamily,
    required this.label,
    this.weight = FontWeight.w400,
    this.isItalic = false,
  });

  @override
  String toString() =>
      'FontInfo($family, actualFamily: $actualFamily, weight: $weight, italic: $isItalic)';
}

/// 扫描 Windows 系统已安装的字体，解析 TTF/OTF/TTC 文件的 name table
/// 提取字体族名（Family Name）。
///
/// **字体目录**：
/// - `C:\Windows\Fonts` — 系统级字体
/// - `%LOCALAPPDATA%\Microsoft\Windows\Fonts` — 用户级字体（Win10 1809+）
///
/// **解析方式**：使用 [RandomAccessFile] 仅读取每个字体文件的
/// offset table + table directory + name table（通常 < 10KB），
/// 避免将整个 CJK 字体文件（可达 40MB）读入内存。
///
/// **name table 提取规则**：
/// - platformID=3 (Microsoft) 下所有 encodingID 均为 UTF-16BE 编码
/// - 优先 langID=0x0409 (en-US) 的 nameID=16 (Typographic Family)
/// - 其次 nameID=1 (Font Family)，再次 nameID=4 (Full Name)
/// - 中文名（langID=0x0804）用于显示标签
class SystemFontScanner {
  static List<FontInfo>? _cache;

  /// 扫描系统字体目录，返回去重后的字体列表。
  /// 首次调用执行扫描，后续调用返回缓存。
  static Future<List<FontInfo>> scan({bool force = false}) async {
    if (!force && _cache != null) return _cache!;
    _cache = await _scanDirectories();
    return _cache!;
  }

  /// 清除缓存（用于强制重新扫描）。
  static void clearCache() => _cache = null;

  /// 根据英文族名从缓存中获取字体信息（如存在）。
  static FontInfo? getByFamily(String family) {
    final list = _cache;
    if (list == null) return null;
    for (final item in list) {
      if (item.family == family) return item;
    }
    return null;
  }

  static Future<List<FontInfo>> _scanDirectories() async {
    final dirs = <String>[
      r'C:\Windows\Fonts',
    ];
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null && localAppData.isNotEmpty) {
      dirs.add('$localAppData\\Microsoft\\Windows\\Fonts');
    }

    final seen = <String>{};
    final fonts = <FontInfo>[];

    for (final dirPath in dirs) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;

      try {
        await for (final entity in dir.list(followLinks: false)) {
          if (entity is! File) continue;
          final lowerPath = entity.path.toLowerCase();
          if (!lowerPath.endsWith('.ttf') &&
              !lowerPath.endsWith('.otf') &&
              !lowerPath.endsWith('.ttc')) {
            continue;
          }

          try {
            final parsed = await _parseFontFamilyNames(entity);
            for (final info in parsed) {
              final key = info.family;
              if (key.isNotEmpty && seen.add(key)) {
                fonts.add(info);
              }
            }
          } catch (e) {
            // 跳过无法解析的字体文件。
            debugPrint('SystemFontScanner: 跳过 ${entity.path} — $e');
          }
        }
      } catch (e) {
        debugPrint('SystemFontScanner: 无法访问 $dirPath — $e');
      }
    }

    fonts.sort((a, b) => a.label.compareTo(b.label));
    return fonts;
  }

  // ── 字体文件解析 ──────────────────────────────────────────

  /// 解析字体文件，返回包含的所有字体信息。
  /// TTC 文件可包含多个字体。
  static Future<List<FontInfo>> _parseFontFamilyNames(File file) async {
    RandomAccessFile? raf;
    try {
      raf = await file.open();
      final lowerPath = file.path.toLowerCase();
      if (lowerPath.endsWith('.ttc')) {
        return await _parseTtc(raf);
      }
      return await _parseTtfFamily(raf, 0);
    } finally {
      await raf?.close();
    }
  }

  /// 解析 TTC (TrueType Collection) 文件。
  /// 每个子字体独立 try/catch，单个失败不影响其他。
  static Future<List<FontInfo>> _parseTtc(RandomAccessFile raf) async {
    // TTC header: tag(4) + majorVersion(2) + minorVersion(2) + numFonts(4)
    await raf.setPosition(8);
    final numFontsBytes = await _readExact(raf, 4);
    final numFonts =
        ByteData.sublistView(numFontsBytes).getUint32(0, Endian.big);

    final offsetsBytes = await _readExact(raf, numFonts * 4);
    final offsetsData = ByteData.sublistView(offsetsBytes);

    final fonts = <FontInfo>[];
    for (int i = 0; i < numFonts; i++) {
      try {
        final offset = offsetsData.getUint32(i * 4, Endian.big);
        final parsed = await _parseTtfFamily(raf, offset);
        fonts.addAll(parsed);
      } catch (e) {
        // 单个子字体解析失败，跳过继续。
        debugPrint('SystemFontScanner: TTC 子字体 $i 解析失败 — $e');
      }
    }
    return fonts;
  }

  /// 解析单个 TTF/OTF 字体的 offset table，提取 name table 中的族名。
  static Future<List<FontInfo>> _parseTtfFamily(
      RandomAccessFile raf, int baseOffset) async {
    // Offset table: sfVersion(4) + numTables(2) + searchRange(2) +
    // entrySelector(2) + rangeShift(2) = 12 bytes
    await raf.setPosition(baseOffset + 4);
    final headerBytes = await _readExact(raf, 8);
    if (headerBytes.length < 8) return [];
    final header = ByteData.sublistView(headerBytes);
    final numTables = header.getUint16(0, Endian.big);

    // Table directory: numTables entries × 16 bytes
    // Each: tag(4) + checkSum(4) + offset(4) + length(4)
    final dirBytes = await _readExact(raf, numTables * 16);
    // 防止 corrupt 文件：实际读到的字节可能少于 numTables*16。
    if (dirBytes.length < numTables * 16) return [];

    int? nameOffset;
    int? nameLength;
    int? os2Offset;
    int? os2Length;
    for (int i = 0; i < numTables; i++) {
      final off = i * 16;
      if (off + 16 > dirBytes.length) break;
      final tag = String.fromCharCodes(dirBytes.sublist(off, off + 4));
      if (tag == 'name') {
        final dir = ByteData.sublistView(dirBytes);
        nameOffset = dir.getUint32(off + 8, Endian.big);
        nameLength = dir.getUint32(off + 12, Endian.big);
      } else if (tag == 'OS/2') {
        final dir = ByteData.sublistView(dirBytes);
        os2Offset = dir.getUint32(off + 8, Endian.big);
        os2Length = dir.getUint32(off + 12, Endian.big);
      }
    }

    if (nameOffset == null || nameLength == null || nameLength == 0) {
      return [];
    }

    int usWeightClass = 400;
    if (os2Offset != null && os2Length != null && os2Length >= 6) {
      try {
        await raf.setPosition(os2Offset);
        final os2Bytes = await _readExact(raf, 6);
        if (os2Bytes.length >= 6) {
          final os2 = ByteData.sublistView(os2Bytes);
          usWeightClass = os2.getUint16(4, Endian.big);
        }
      } catch (_) {}
    }

    // OpenType 规范中，Table Directory 的 offset 字段是相对于整个字体文件开头的绝对偏移量。
    // 在 TTC 集合文件中同样是文件绝对偏移量，绝不可叠加 baseOffset。
    return _parseNameTable(raf, nameOffset, nameLength, usWeightClass);
  }

  /// 解析 name table，提取字体族名（英文 family + 中文 label）。
  static Future<List<FontInfo>> _parseNameTable(
      RandomAccessFile raf, int tableOffset, int tableLength, int usWeightClass) async {
    await raf.setPosition(tableOffset);
    final tableBytes = await _readExact(raf, tableLength);
    if (tableBytes.length < 6) return [];
    final data = ByteData.sublistView(tableBytes);

    final count = data.getUint16(2, Endian.big);
    final stringOffset = data.getUint16(4, Endian.big);

    // langID 常量（十进制）：
    // 0x0409=1033 en-US
    // 0x0804=2052 zh-CN（简体中文）
    // 0x0404=1028 zh-TW（繁体中文-台湾）
    // 0x0c04=3076 zh-HK（繁体中文-香港）
    // 0x1404=5124 zh-MO（繁体中文-澳门）
    // 0x1004=4100 zh-SG（简体中文-新加坡）
    const langEnUs = 1033;
    const langZhCn = 2052;
    const langZhTw = 1028;
    const langZhHk = 3076;
    const langZhMo = 5124;
    const langZhSg = 4100;

    // 收集所有相关 name record。
    // key = nameID_langID（均为十进制），value = 解码后的字符串。
    final names = <String, String>{};

    for (int i = 0; i < count; i++) {
      final recOff = 6 + i * 12;
      if (recOff + 12 > tableBytes.length) break;

      final platformID = data.getUint16(recOff, Endian.big);
      final languageID = data.getUint16(recOff + 4, Endian.big);
      final nameID = data.getUint16(recOff + 6, Endian.big);
      final strLength = data.getUint16(recOff + 8, Endian.big);
      final strOffset = data.getUint16(recOff + 10, Endian.big);

      // 支持 Windows 平台（platformID=3）及 Unicode 平台（platformID=0），UTF-16BE 编码。
      if (platformID != 3 && platformID != 0) continue;

      // 关注 nameID=1 (Family), 2 (Subfamily), 4 (Full Name), 16 (Typographic Family), 17 (Typographic Subfamily), 21 (WWS Family)。
      if (nameID != 1 &&
          nameID != 2 &&
          nameID != 4 &&
          nameID != 16 &&
          nameID != 17 &&
          nameID != 21) {
        continue;
      }

      final isZh = languageID == langZhCn ||
          languageID == langZhTw ||
          languageID == langZhHk ||
          languageID == langZhMo ||
          languageID == langZhSg;

      // 仅关注 en-US 与中文语言。
      if (languageID != langEnUs && !isZh && platformID != 0) continue;

      final absStrOff = stringOffset + strOffset;
      if (absStrOff + strLength > tableBytes.length) continue;

      final strBytes = tableBytes.sublist(absStrOff, absStrOff + strLength);
      final value = _decodeUtf16be(strBytes);

      // key 用十进制格式，与下方查找保持一致。
      final key = '${nameID}_$languageID';
      names.putIfAbsent(key, () => value);
    }

    // 方案 B：完整枚举各级具体字重（Light / Regular / Bold 等）。
    final styleEn = names['2_$langEnUs'] ?? 'Regular';
    final isRegular = styleEn.toLowerCase() == 'regular' ||
        styleEn.toLowerCase() == 'normal';
    final isItalic = styleEn.toLowerCase().contains('italic') ||
        styleEn.toLowerCase().contains('oblique');

    // 底层 DirectWrite 实际族名（用于 TextStyle.fontFamily 准确匹配系统字体）
    final actualFamily = names['1_$langEnUs'] ??
        names['16_$langEnUs'] ??
        names['1_$langZhCn'] ??
        '';

    if (actualFamily.isEmpty) return [];

    // 解析 family 唯一标识键：
    // 常规体优先取 nameID=1（族名），非常规体（如 Bold/Light）优先取 nameID=4（全名）或 nameID=1。
    String family = isRegular
        ? (names['1_$langEnUs'] ??
            names['4_$langEnUs'] ??
            actualFamily)
        : (names['4_$langEnUs'] ??
            names['1_$langEnUs'] ??
            actualFamily);

    // 解析 label（显示名，优先中文全名）：
    String label = isRegular
        ? (names['1_$langZhCn'] ??
            names['4_$langZhCn'] ??
            names['1_$langZhTw'] ??
            names['4_$langZhTw'] ??
            names['1_$langZhHk'] ??
            names['4_$langZhHk'] ??
            family)
        : (names['4_$langZhCn'] ??
            names['1_$langZhCn'] ??
            names['4_$langZhTw'] ??
            names['1_$langZhTw'] ??
            names['4_$langZhHk'] ??
            names['1_$langZhHk'] ??
            family);

    // 对于非 Regular 字重，若提取到的中文名称未包含字重后缀，则补充后缀
    if (!isRegular &&
        !label.toLowerCase().contains(styleEn.toLowerCase()) &&
        (names['1_$langZhCn'] == label || names['1_$langZhTw'] == label)) {
      if (names['4_$langZhCn'] != null && names['4_$langZhCn']!.isNotEmpty) {
        label = names['4_$langZhCn']!;
      } else {
        label = '$label $styleEn';
      }
    }

    // 针对 Windows 系统 UI 字体元数据未自带中文 UI 族名的情况补充友好别名
    if (family == 'Microsoft YaHei UI' &&
        (label == 'Microsoft YaHei UI' || label == 'Microsoft Yahei UI')) {
      label = '微软雅黑 UI';
    } else if (family == 'Microsoft YaHei UI Light' &&
        (label.contains('Microsoft YaHei UI Light') ||
            label.contains('Microsoft Yahei UI Light') ||
            label == 'Microsoft YaHei UI Light')) {
      label = '微软雅黑 UI Light';
    } else if (family == 'Microsoft YaHei UI Bold' &&
        (label.contains('Microsoft YaHei UI Bold') ||
            label.contains('Microsoft Yahei UI Bold') ||
            label == 'Microsoft YaHei UI Bold')) {
      label = '微软雅黑 UI Bold';
    } else if (family == 'Microsoft JhengHei UI' &&
        label.contains('Microsoft JhengHei UI')) {
      label = '微軟正黑體 UI';
    } else if (family == 'Microsoft JhengHei UI Light' &&
        label.contains('Microsoft JhengHei UI Light')) {
      label = '微軟正黑體 UI Light';
    } else if (family == 'Microsoft JhengHei UI Bold' &&
        label.contains('Microsoft JhengHei UI Bold')) {
      label = '微軟正黑體 UI Bold';
    }

    final weight = _resolveWeight(usWeightClass, styleEn);

    return [
      FontInfo(
        family: family,
        actualFamily: actualFamily,
        label: label,
        weight: weight,
        isItalic: isItalic,
      ),
    ];
  }

  /// 根据 OS/2 usWeightClass 及样式字符串解析 FontWeight。
  static FontWeight _resolveWeight(int usWeightClass, String styleEn) {
    final lower = styleEn.toLowerCase();
    if (lower.contains('black') || lower.contains('heavy')) return FontWeight.w900;
    if (lower.contains('extrabold') || lower.contains('ultra bold')) {
      return FontWeight.w800;
    }
    if (lower.contains('semibold') ||
        lower.contains('semi bold') ||
        lower.contains('demi')) {
      return FontWeight.w600;
    }
    if (lower.contains('bold')) return FontWeight.w700;
    if (lower.contains('medium')) return FontWeight.w500;
    if (lower.contains('light')) return FontWeight.w300;
    if (lower.contains('thin')) return FontWeight.w100;
    if (usWeightClass <= 150) return FontWeight.w100;
    if (usWeightClass <= 250) return FontWeight.w200;
    if (usWeightClass <= 350) return FontWeight.w300;
    if (usWeightClass <= 450) return FontWeight.w400;
    if (usWeightClass <= 550) return FontWeight.w500;
    if (usWeightClass <= 650) return FontWeight.w600;
    if (usWeightClass <= 750) return FontWeight.w700;
    if (usWeightClass <= 850) return FontWeight.w800;
    return FontWeight.w900;
  }

  /// 从 RandomAccessFile 精确读取 [count] 字节。
  static Future<Uint8List> _readExact(RandomAccessFile raf, int count) async {
    final builder = BytesBuilder();
    var remaining = count;
    while (remaining > 0) {
      final chunk = await raf.read(remaining);
      if (chunk.isEmpty) break;
      builder.add(chunk);
      remaining -= chunk.length;
    }
    return builder.toBytes();
  }

  /// 解码 UTF-16BE 字节为字符串，过滤 null 字符。
  static String _decodeUtf16be(List<int> bytes) {
    final sb = StringBuffer();
    for (int i = 0; i + 1 < bytes.length; i += 2) {
      final codeUnit = (bytes[i] << 8) | bytes[i + 1];
      if (codeUnit == 0) continue; // 跳过 null 字符。
      sb.writeCharCode(codeUnit);
    }
    return sb.toString().trim();
  }
}
