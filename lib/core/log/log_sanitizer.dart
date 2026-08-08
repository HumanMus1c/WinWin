import 'package:flutter/foundation.dart';

/// 隐私脱敏：在日志落盘前对敏感信息做正则替换。
///
/// 设计参照 BiliPai LogCollector.sanitizeMessage：
/// - 脱敏延后到落盘时执行，主路径零成本（内存缓冲与控制台输出不经脱敏）。
/// - 覆盖 B 站场景常见的 PII：Cookie/Token/用户标识/IP/MAC/路径/视频内容标识。
class LogSanitizer {
  LogSanitizer._();

  /// 规则表（pattern → replacement）。
  /// 顺序敏感：先匹配长模式再匹配短模式，避免前一条规则破坏后一条的输入。
  //
  // 注意：正则中用 \x22(") \x27(') 代替引号字面量，避免 Dart raw string
  // 定界符冲突（raw string 中 \' 和 \" 都会提前结束字符串）。
  static final List<MapEntry<RegExp, String>> _rules = [
    // 1. Cookie 整体（kv 列表形式）— 保留键名，值脱敏
    MapEntry(
      RegExp(r'(SESSDATA|bili_jct|buvid3|buvid4|b_nut|DedeUserID)[=\s:]+([^\s;,\x22\x27]+)'),
      r'$1=***REDACTED***',
    ),
    // 2. access_token / sign / csrf / Authorization Bearer
    MapEntry(
      RegExp(r'(access_token|sign|csrf|Authorization[\x22\x27]?\s*[:=]\s*[\x22\x27]?Bearer\s+)([A-Za-z0-9%_\-\.]+)'),
      r'$1***REDACTED***',
    ),
    // 3. 手机号（11 位）
    MapEntry(RegExp(r'\b1[3-9]\d{9}\b'), '***PHONE***'),
    // 4. 邮箱
    MapEntry(RegExp(r'\b[\w.+-]+@[\w-]+\.[\w.-]+\b'), '***EMAIL***'),
    // 5. IPv4
    MapEntry(RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b'), '***IP***'),
    // 6. IPv6（简化匹配）
    MapEntry(RegExp(r'\b(?:[A-Fa-f0-9]{1,4}:){2,7}[A-Fa-f0-9]{1,4}\b'), '***IP***'),
    // 7. MAC 地址
    MapEntry(RegExp(r'\b(?:[A-Fa-f0-9]{2}:){5}[A-Fa-f0-9]{2}\b'), '***MAC***'),
    // 8. 本地文件路径（Windows/Unix）— 脱敏路径但保留文件名便于排查
    MapEntry(
      RegExp(r'([A-Za-z]:[\\/](?:[^\\/:\*\?"<>\|\r\n]+[\\/])+)([^\\/:\*\?"<>\|\r\n]+)'),
      r'***PATH***/$2',
    ),
    MapEntry(
      RegExp(r'(/(?:[^/:\*\?"<>\|\r\n]+/)+)([^/:\*\?"<>\|\r\n]+)'),
      r'***PATH***/$2',
    ),
    // 9. BV 号（B 站视频标识，BV 后 10 位字母数字）
    MapEntry(RegExp(r'\bBV[0-9A-Za-z]{10}\b'), '***BV***'),
    // 10. cid / aid / room_id / season_id / ep_id（带前缀的数字标识）
    MapEntry(
      RegExp(r'\b(cid|aid|room_id|season_id|ep_id|mid|uid)[\x22\x27]?\s*[:=]\s*[\x22\x27]?(\d+)'),
      r'$1=***ID***',
    ),
  ];

  /// 对单条日志消息执行脱敏。
  ///
  /// 主路径不调用此方法；仅 [LogCollector] 落盘前调用。
  static String sanitize(String message) {
    var result = message;
    for (final rule in _rules) {
      result = result.replaceAll(rule.key, rule.value);
    }
    return result;
  }

  /// 调试用：在 debug 模式验证脱敏规则是否命中（不影响 release）。
  static void selfTest() {
    if (!kDebugMode) return;
    const samples = <String>[
      'SESSDATA=abc%2Cdef-12345, bili_jct=xyz789',
      'access_token=abc123_token&sign=deadbeef',
      'phone: 13800138000 email: test@example.com',
      'ip 192.168.1.1 and 2001:db8::1 mac 00:11:22:33:44:55',
      'path C:\\Users\\admin\\videos\\test.mp4 and /home/admin/logs/x.txt',
      'bvid: BV1xx411c7mD cid=12345 mid=67890',
    ];
    for (final s in samples) {
      debugPrint('[sanitizer] "${sanitize(s)}"');
    }
  }
}
