import 'dart:convert' show ascii;
import 'dart:typed_data' show Uint8List;

/// CRC32 实现（标准 zlib/IEEE 802.3 多项式 0xEDB88320）。
///
/// 用于计算 B 站弹幕的 `midHash`：服务端仅返回用户 mid 的 CRC32 十六进制
/// 形式（非原始 uid），因此「按用户屏蔽」需要把输入 uid 同样转成 midHash
/// 才能匹配。算法与 `archive` 包的 `getCrc32` 一致。
abstract final class Crc32 {
  static final List<int> _table = _buildTable();

  static List<int> _buildTable() {
    final table = List<int>.filled(256, 0);
    for (int n = 0; n < 256; n++) {
      int c = n;
      for (int k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
      }
      table[n] = c;
    }
    return table;
  }

  /// 计算给定字节序列的 CRC32（返回无符号 32 位 int）。
  static int get(List<int> data) {
    int crc = 0xFFFFFFFF;
    for (final b in data) {
      crc = _table[(crc ^ b) & 0xFF] ^ (crc >>> 8);
    }
    return crc ^ 0xFFFFFFFF;
  }

  /// 计算字符串（ASCII）的 CRC32。
  static int getString(String s) => get(ascii.encode(s));

  /// 把用户 mid 转成 B 站弹幕 midHash（CRC32 的十六进制字符串）。
  ///
  /// 与服务端返回的 `DanmakuElem.midHash` 字段格式一致，用于「按用户屏蔽」
  /// 时的本地匹配。
  static String midHash(int mid) => getString(mid.toString()).toRadixString(16);
}

/// 便捷扩展：直接对 [Uint8List] 取 CRC32。
extension Crc32Bytes on Uint8List {
  int get crc32 => Crc32.get(this);
}
