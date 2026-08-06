import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'package:winwin/core/account/account.dart';
import 'package:winwin/models/common/account_type.dart';
import 'package:winwin/utils/credential_crypto.dart';
import 'package:winwin/utils/utils.dart';

/// Adapter so [DefaultCookieJar] can be persisted by Hive CE.
///
/// 凭证加密：cookie 内容通过 [CredentialCrypto] 加密后落盘，避免明文存储。
class BiliCookieJarAdapter extends TypeAdapter<DefaultCookieJar> {
  @override
  final int typeId = 4;

  @override
  DefaultCookieJar read(BinaryReader reader) {
    final raw = reader.readString();
    if (raw.isEmpty) return BiliCookieJarHelper.fromJson(<String, dynamic>{});
    // 优先尝试解密；若为旧版明文数据则直接解码（向后兼容）。
    String json;
    final decrypted = CredentialCrypto.decrypt(raw);
    if (decrypted.isNotEmpty) {
      json = decrypted;
    } else {
      json = raw;
    }
    return BiliCookieJarHelper.fromJson(jsonDecode(json));
  }

  @override
  void write(BinaryWriter writer, DefaultCookieJar obj) {
    final json = jsonEncode(BiliCookieJarHelper.toJson(obj));
    writer.writeString(CredentialCrypto.encrypt(json));
  }
}

/// Adapter so [LoginAccount] can be persisted by Hive CE.
///
/// 凭证加密：accessKey / refresh / cookie 全部通过 [CredentialCrypto] 加密
/// 后落盘。读取时自动解密，向后兼容旧版明文数据。
class LoginAccountAdapter extends TypeAdapter<LoginAccount> {
  @override
  final int typeId = 9;

  @override
  LoginAccount read(BinaryReader reader) {
    final raw = reader.readString();
    // 优先尝试解密；若为旧版明文则直接解码。
    String json;
    final decrypted = CredentialCrypto.decrypt(raw);
    if (decrypted.isNotEmpty) {
      json = decrypted;
    } else {
      json = raw;
    }
    return LoginAccount.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  @override
  void write(BinaryWriter writer, LoginAccount obj) {
    final json = jsonEncode(obj.toJson());
    writer.writeString(CredentialCrypto.encrypt(json));
  }
}

/// Adapter so [Set<AccountType>] can be persisted by Hive CE.
class AccountTypeSetAdapter extends TypeAdapter<Set<AccountType>> {
  @override
  final int typeId = 10;

  @override
  Set<AccountType> read(BinaryReader reader) {
    final list = reader.readIntList();
    return list.map((i) => AccountType.values[i]).toSet();
  }

  @override
  void write(BinaryWriter writer, Set<AccountType> obj) {
    writer.writeIntList(obj.map((e) => e.index).toList());
  }
}

abstract final class GStorage {
  static late final Box<dynamic> localCache;
  static late final Box<dynamic> setting;
  static late final Box<dynamic> video;

  /// Lazy-initialized Hive directory path.
  static String? _hivePath;

  static Future<String> _hiveDirPath() async {
    if (_hivePath != null) return _hivePath!;
    final supportDir = await getApplicationSupportDirectory();
    _hivePath = path.join(supportDir.path, 'hive');
    return _hivePath!;
  }

  static Future<void> init() async {
    final hivePath = await _hiveDirPath();
    Hive.init(hivePath);
    regAdapter();

    await Future.wait([
      // 本地缓存
      Hive.openBox(
        'localCache',
        compactionStrategy: (int entries, int deletedEntries) {
          return deletedEntries > 4;
        },
      ).then((res) => localCache = res),
      // 设置
      Hive.openBox('setting').then((res) => setting = res),
      // 视频设置
      Hive.openBox('video').then((res) => video = res),
    ]);
  }

  static void regAdapter() {
    Hive
      ..registerAdapter(BiliCookieJarAdapter())
      ..registerAdapter(LoginAccountAdapter())
      ..registerAdapter(AccountTypeSetAdapter());
  }

  static Future<List<void>> compact() {
    return Future.wait([
      localCache.compact(),
      setting.compact(),
      video.compact(),
    ]);
  }

  static Future<List<void>> close() {
    return Future.wait([
      localCache.close(),
      setting.close(),
      video.close(),
    ]);
  }

  static Future<List<void>> clear() {
    return Future.wait([
      localCache.clear(),
      setting.clear(),
      video.clear(),
    ]);
  }

  static String exportAllSettings() {
    return Utils.jsonEncoder.convert({
      setting.name: setting.toMap(),
      video.name: video.toMap(),
    });
  }

  static Future<void> importAllSettings(String data) =>
      importAllJsonSettings(jsonDecode(data));

  static Future<List<void>> importAllJsonSettings(Map<String, dynamic> map) {
    return Future.wait([
      setting.clear().then((_) => setting.putAll(map[setting.name])),
      video.clear().then((_) => video.putAll(map[video.name])),
    ]);
  }
}

/// Used by [LoginAccountAdapter] to serialise the cookie jar as JSON.
extension BiliCookieJarHelper on DefaultCookieJar {
  static Map<String, dynamic> toJson(DefaultCookieJar jar) {
    final cookies =
        jar.domainCookies['bilibili.com']?['/'] ?? const <String, dynamic>{};
    return {
      for (final entry in cookies.entries)
        entry.key: (entry.value as SerializableCookie).cookie.value,
    };
  }

  static DefaultCookieJar fromJson(Map<String, dynamic> json) {
    final jar = DefaultCookieJar(ignoreExpires: true);
    jar.domainCookies['bilibili.com'] = {
      '/': {
        for (final entry in json.entries)
          entry.key: SerializableCookie(
            Cookie(entry.key, entry.value.toString())
              ..domain = '.bilibili.com'
              ..httpOnly = false
              ..path = '/',
          ),
      },
    };
    return jar;
  }
}
