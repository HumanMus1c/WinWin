import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

/// 账户密钥凭证加密解密工具。
///
/// PiliPlus 将 accessKey / cookie 明文存于 Hive，本类在 WinWin 上增加一层
/// 对称加密，避免凭证在磁盘上以明文落盘。
///
/// 算法：基于机器绑定密钥的 HMAC-SHA256 密钥流 XOR（流加密）。
/// - 密钥派生：machineKey（固定常量，桌面端无可靠机器 ID API 时的兜底）
///   经 PBKDF2-like 多轮 HMAC 收敛为 32 字节主密钥。
/// - 加密：对明文按 64 字节分块，每块用 `HMAC(masterKey, nonce || counter)`
///   生成密钥流后 XOR；密文 = base64( nonce || ciphertext )。
/// - 解密：逆向。nonce 随机，每次加密结果不同。
///
/// 安全性说明：本方案抵御普通磁盘直接读取；不抵御拥有内存调试能力的攻击者。
/// 如需更强保护可后续接入 Windows DPAPI（flutter_secure_storage）。
abstract final class CredentialCrypto {
  /// 机器绑定密钥（WinWin Desktop 专用盐）。
  /// 与应用绑定，不同应用无法直接复用。
  static final List<int> _machineSalt = utf8.encode(
    'WinWin::2026::bili::credential::v1',
  );

  /// 派生主密钥（32 字节）。固定输出，无随机性，确保加解密一致。
  static final List<int> _masterKey = _deriveKey(_machineSalt);

  static List<int> _deriveKey(List<int> salt) {
    // 多轮 HMAC 收敛，提升暴力破解成本。
    List<int> key = utf8.encode('winwin-desk');
    for (var i = 0; i < 8; i++) {
      key = Hmac(sha256, key).convert(salt).bytes;
    }
    return key;
  }

  /// 生成密钥流块（64 字节）。
  static Uint8List _keystream(List<int> masterKey, Uint8List nonce, int counter) {
    final input = BytesBuilder()
      ..add(nonce)
      ..add(_int32(counter));
    return Uint8List.fromList(
      Hmac(sha256, masterKey).convert(input.toBytes()).bytes,
    );
  }

  static List<int> _int32(int v) => [
        (v >> 24) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 8) & 0xFF,
        v & 0xFF,
      ];

  /// 加密字符串，返回 base64 编码的密文（含 nonce 前缀）。
  static String encrypt(String plaintext) {
    if (plaintext.isEmpty) return '';
    final plain = utf8.encode(plaintext);
    final nonce = Uint8List.fromList(
      _uuid.v4obj().toBytes(),
    );
    final cipher = Uint8List(plain.length);
    final blocks = (plain.length + 63) ~/ 64;
    for (var b = 0; b < blocks; b++) {
      final ks = _keystream(_masterKey, nonce, b);
      final start = b * 64;
      final end = (start + 64 > plain.length) ? plain.length : start + 64;
      for (var i = start; i < end; i++) {
        cipher[i] = plain[i] ^ ks[i - start];
      }
    }
    final out = BytesBuilder()..add(nonce)..add(cipher);
    return base64.encode(out.toBytes());
  }

  /// 解密 base64 密文，返回明文字符串。失败返回空串。
  static String decrypt(String ciphertext) {
    if (ciphertext.isEmpty) return '';
    try {
      final raw = base64.decode(ciphertext);
      if (raw.length < 16) return '';
      final nonce = Uint8List.fromList(raw.sublist(0, 16));
      final cipher = raw.sublist(16);
      final plain = Uint8List(cipher.length);
      final blocks = (cipher.length + 63) ~/ 64;
      for (var b = 0; b < blocks; b++) {
        final ks = _keystream(_masterKey, nonce, b);
        final start = b * 64;
        final end = (start + 64 > cipher.length) ? cipher.length : start + 64;
        for (var i = start; i < end; i++) {
          plain[i] = cipher[i] ^ ks[i - start];
        }
      }
      return utf8.decode(plain);
    } catch (_) {
      return '';
    }
  }

  static int _randomByte() => DateTime.now().microsecondsSinceEpoch & 0xFF;

  static final _uuid = const Uuid();
}
