import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// 系统字体信息。
///
/// [family] 是英文族名（来自 nameID=16 或 1，langID=0x0409），
/// 供 Flutter 的 `TextStyle(fontFamily:)` 解析使用。
/// [label] 是显示名称，优先取中文名（langID=0x0804），无则回退到 [family]。
class FontInfo {
  final String family;
  final String label;

  const FontInfo({required this.family, required this.label});

  @override
  String toString() => 'FontInfo($family)';
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
    for (int i = 0; i < numTables; i++) {
      final off = i * 16;
      if (off + 16 > dirBytes.length) break;
      final tag = String.fromCharCodes(dirBytes.sublist(off, off + 4));
      if (tag == 'name') {
        final dir = ByteData.sublistView(dirBytes);
        nameOffset = dir.getUint32(off + 8, Endian.big);
        nameLength = dir.getUint32(off + 12, Endian.big);
        break;
      }
    }

    if (nameOffset == null || nameLength == null || nameLength == 0) {
      return [];
    }

    return _parseNameTable(raf, baseOffset + nameOffset, nameLength);
  }

  /// 解析 name table，提取字体族名（英文 family + 中文 label）。
  static Future<List<FontInfo>> _parseNameTable(
      RandomAccessFile raf, int tableOffset, int tableLength) async {
    await raf.setPosition(tableOffset);
    final tableBytes = await _readExact(raf, tableLength);
    if (tableBytes.length < 6) return [];
    final data = ByteData.sublistView(tableBytes);

    final count = data.getUint16(2, Endian.big);
    final stringOffset = data.getUint16(4, Endian.big);

    // langID 常量（十进制：0x0409=1033 en-US，0x0804=2052 zh-CN）。
    const langEnUs = 1033;
    const langZhCn = 2052;

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

      // 仅取 Windows 平台（platformID=3），其下所有 encoding 均为 UTF-16BE。
      if (platformID != 3) continue;

      // 仅关注 nameID=1 (Family), 4 (Full Name), 16 (Typographic Family)。
      if (nameID != 1 && nameID != 4 && nameID != 16) continue;

      // 仅关注 en-US 和 zh-CN。
      if (languageID != langEnUs && languageID != langZhCn) continue;

      final absStrOff = stringOffset + strOffset;
      if (absStrOff + strLength > tableBytes.length) continue;

      final strBytes = tableBytes.sublist(absStrOff, absStrOff + strLength);
      // platformID=3 下所有 encoding 均为 UTF-16BE。
      final value = _decodeUtf16be(strBytes);

      // key 用十进制格式，与下方查找保持一致。
      final key = '${nameID}_$languageID';
      names.putIfAbsent(key, () => value);
    }

    // 解析 family（英文，供 Flutter 解析）。
    // 优先级：nameID=16(en) > 1(en) > 4(en) > 16(zh) > 1(zh) > 4(zh)
    final family = names['16_$langEnUs'] ??
        names['1_$langEnUs'] ??
        names['4_$langEnUs'] ??
        names['16_$langZhCn'] ??
        names['1_$langZhCn'] ??
        names['4_$langZhCn'];

    if (family == null || family.isEmpty) return [];

    // 解析 label（显示名，优先中文）。
    final label = names['16_$langZhCn'] ??
        names['1_$langZhCn'] ??
        names['4_$langZhCn'] ??
        names['16_$langEnUs'] ??
        names['1_$langEnUs'] ??
        names['4_$langEnUs'] ??
        family;

    return [FontInfo(family: family, label: label)];
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
