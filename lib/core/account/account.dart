import 'dart:io' show Cookie;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:hive_ce/hive.dart';

import 'package:winwin/common/constants.dart' show Constants;
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/core/grpc/grpc_headers.dart';
import 'package:winwin/models/common/account_type.dart';
import 'package:winwin/utils/id_utils.dart';

sealed class Account {
  Map<String, dynamic>? toJson() => null;

  Future<void>? onChange() => null;

  Set<AccountType> get type => const {};

  bool get activated => false;

  set activated(bool value) => throw UnimplementedError();

  String? get accessKey => throw UnimplementedError();

  DefaultCookieJar get cookieJar => throw UnimplementedError();

  String get csrf => throw UnimplementedError();

  Future<void> delete() => throw UnimplementedError();

  Map<String, String> get headers => throw UnimplementedError();

  Map<String, String> get grpcHeaders => throw UnimplementedError();

  bool get isLogin => throw UnimplementedError();

  int get mid => throw UnimplementedError();

  String? get refresh => throw UnimplementedError();

  const Account();
}

class LoginAccount extends Account {
  @override
  final bool isLogin = true;
  @override
  final DefaultCookieJar cookieJar;
  @override
  final String? accessKey;
  @override
  final String? refresh;
  @override
  final Set<AccountType> type;

  @override
  bool activated = false;

  @override
  late final int mid = int.parse(_midStr);

  @override
  late final Map<String, String> headers = {
    ...Constants.baseHeaders,
    'x-bili-mid': _midStr,
    'x-bili-aurora-eid': IdUtils.genAuroraEid(mid),
  };

  @override
  late final Map<String, String> grpcHeaders = GrpcHeaders.build(accessKey);

  @override
  late final String csrf = cookieJar
      .domainCookies['bilibili.com']!['/']!['bili_jct']!.cookie.value;

  /// 直接从 domainCookies 映射中提取关键鉴权 cookie，绕过
  /// cookie_jar 的 loadForRequest 域名匹配（移植自 BiliPai
  /// AppSessionCookieJar.loadForRequest 的注入式方案）。
  ///
  /// TV QR 登录返回的 cookie 存入 jar 后，loadForRequest 的域名
  /// 匹配可能不稳定（导致 web nav 返回 isLogin=false）。此 getter
  /// 直接从 domainCookies['bilibili.com']['/'] 读取，确保关键
  /// cookie 始终被正确注入到每个请求中。
  List<Cookie> get keyCookies {
    final domainMap = cookieJar.domainCookies['bilibili.com']?['/'];
    if (domainMap == null) return const [];
    const names = [
      'SESSDATA',
      'bili_jct',
      'DedeUserID',
      'DedeUserID__ckMd5',
      'buvid3',
    ];
    final result = <Cookie>[];
    for (final name in names) {
      final sc = domainMap[name];
      if (sc != null) {
        result.add(sc.cookie);
      }
    }
    return result;
  }

  bool _hasDelete = false;

  @override
  Future<void> delete() {
    assert(_hasDelete = true);
    return Future.wait([cookieJar.deleteAll(), _box.delete(_midStr)]);
  }

  @override
  Future<void> onChange() {
    assert(!_hasDelete);
    return _box.put(_midStr, this);
  }

  @override
  Map<String, dynamic>? toJson() => {
    'cookies': BiliCookieJarHelper.toJson(cookieJar),
    'accessKey': accessKey,
    'refresh': refresh,
    'type': type.map((i) => i.index).toList(),
  };

  late final String _midStr = cookieJar
      .domainCookies['bilibili.com']!['/']!['DedeUserID']!
      .cookie
      .value;

  late final Box<LoginAccount> _box = Accounts.account;

  LoginAccount(
    this.cookieJar,
    this.accessKey,
    this.refresh, [
    Set<AccountType>? type,
  ]) : type = type ?? {} {
    cookieJar.setBuvid3();
  }

  factory LoginAccount.fromJson(Map<String, dynamic> json) {
    final jar = BiliCookieJarHelper.fromJson(
      (json['cookies'] as Map).cast<String, dynamic>(),
    );
    return LoginAccount(
      jar,
      json['accessKey'] as String?,
      json['refresh'] as String?,
      (json['type'] as Iterable?)
          ?.map((i) => AccountType.values[i as int])
          .toSet(),
    );
  }

  @override
  int get hashCode => mid.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is LoginAccount && mid == other.mid);
}

class AnonymousAccount extends Account {
  @override
  final bool isLogin = false;
  @override
  final DefaultCookieJar cookieJar = DefaultCookieJar()..setBuvid3();
  @override
  final String? accessKey = null;
  @override
  final String? refresh = null;
  @override
  final Set<AccountType> type = {};
  @override
  final int mid = 0;
  @override
  final String csrf = '';
  @override
  final Map<String, String> headers = Constants.baseHeaders;

  @override
  final Map<String, String> grpcHeaders = GrpcHeaders.build();

  @override
  bool activated = false;

  @override
  Future<void> delete() {
    return cookieJar.deleteAll().whenComplete(cookieJar.setBuvid3);
  }

  static final _instance = AnonymousAccount._();

  AnonymousAccount._();

  factory AnonymousAccount() => _instance;

  @override
  int get hashCode => cookieJar.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AnonymousAccount && cookieJar == other.cookieJar);
}

extension BiliCookie on Cookie {
  void setBiliDomain([String domain = '.bilibili.com']) {
    this.domain = domain;
    httpOnly = false;
    path = '/';
  }
}

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
            Cookie(entry.key, entry.value.toString())..setBiliDomain(),
          ),
      },
    };
    return jar;
  }

  List<Cookie> toList() =>
      domainCookies['bilibili.com']?['/']?.entries
          .map((i) => i.value.cookie)
          .toList() ??
      [];

  /// 从登录接口返回的 cookie 列表（[{name, value}, ...]）构造 jar。
  static DefaultCookieJar fromList(List cookies) {
    final jar = DefaultCookieJar(ignoreExpires: true);
    jar.domainCookies['bilibili.com'] = {
      '/': {
        for (final i in cookies)
          (i as Map)['name'] as String: SerializableCookie(
            Cookie(i['name'] as String, i['value'] as String)
              ..setBiliDomain(),
          ),
      },
    };
    return jar;
  }

  void setBuvid3() {
    (domainCookies['bilibili.com'] ??= {
      '/': {},
    })['/']!['buvid3'] ??= SerializableCookie(
      Cookie('buvid3', IdUtils.genBuvid3())..setBiliDomain(),
    );
  }
}

final class NoAccount extends Account {
  const NoAccount();
}
