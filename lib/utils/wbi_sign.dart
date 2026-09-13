// Wbi签名 用于生成 REST API 请求中的 w_rid 和 wts 字段
// https://github.com/SocialSisterYi/bilibili-API-collect/blob/master/docs/misc/sign/wbi.md
import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive.dart';
import 'package:winwin/core/log/api_blackbox.dart';
import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/core/storage/storage_key.dart';
import 'package:winwin/http/api.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/utils/utils.dart';

abstract final class WbiSign {
  static Box get _localCache => GStorage.localCache;

  static final RegExp _chrFilter = RegExp(r"[!\'\(\)\*]");
  static const _mixinKeyEncTab = <int>[
    46,
    47,
    18,
    2,
    53,
    8,
    23,
    32,
    15,
    50,
    10,
    31,
    58,
    3,
    45,
    35,
    27,
    43,
    5,
    49,
    33,
    9,
    42,
    19,
    29,
    28,
    14,
    39,
    12,
    38,
    41,
    13,
  ];

  static Future<String>? _future;

  // 对 imgKey 和 subKey 进行字符顺序打乱编码
  static String getMixinKey(String orig) {
    return String.fromCharCodes(_mixinKeyEncTab.map(orig.codeUnitAt));
  }

  // 为请求参数进行 wbi 签名
  static void encWbi(Map<String, Object> params, String mixinKey) {
    params['wts'] = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // 按照 key 重排参数
    final List<String> keys = params.keys.toList()..sort();
    final queryStr = keys
        .map(
          (i) =>
              '${Uri.encodeComponent(i)}=${Uri.encodeComponent(params[i].toString().replaceAll(_chrFilter, ''))}',
        )
        .join('&');
    params['w_rid'] = md5
        .convert(utf8.encode(queryStr + mixinKey))
        .toString(); // 计算 w_rid
  }

  static Future<String> _getWbiKeys() async {
    try {
      ApiBlackbox.log('WbiSign', 'Fetching fresh Wbi keys from Api.userInfo');
      final resp = await Request().get<dynamic>(Api.userInfo);
      final data = resp.data;
      if (data is! Map<String, dynamic>) {
        ApiBlackbox.log('WbiSign', 'Failed to get Wbi keys: response is not Map (${data.runtimeType})');
        return '';
      }
      final wbiUrls = data['data']?['wbi_img'];
      if (wbiUrls == null) {
        ApiBlackbox.log('WbiSign', 'Failed to get Wbi keys: wbi_img is null');
        return '';
      }

      final mixinKey = getMixinKey(
        Utils.getFileName(wbiUrls['img_url']?.toString() ?? '', fileExt: false) +
            Utils.getFileName(wbiUrls['sub_url']?.toString() ?? '', fileExt: false),
      );

      ApiBlackbox.log('WbiSign', 'Successfully generated mixinKey (length=${mixinKey.length})');
      await _localCache.put(LocalCacheKey.mixinKey, mixinKey);
      return mixinKey;
    } catch (e) {
      ApiBlackbox.log('WbiSign', 'Exception getting Wbi keys: $e');
      return '';
    }
  }

  static FutureOr<String> getWbiKeys() {
    final nowDate = DateTime.now();
    final cachedTimestamp =
        _localCache.get(LocalCacheKey.timeStamp, defaultValue: 0) as int;
    if (DateTime.fromMillisecondsSinceEpoch(cachedTimestamp).day ==
        nowDate.day) {
      final String? mixinKey =
          _localCache.get(LocalCacheKey.mixinKey) as String?;
      if (mixinKey != null && mixinKey.isNotEmpty) return mixinKey;
      return _future ??= _getWbiKeys();
    } else {
      return _future = _localCache
          .put(LocalCacheKey.timeStamp, nowDate.millisecondsSinceEpoch)
          .then((_) => _getWbiKeys());
    }
  }

  static Future<Map<String, Object>> makSign(
    Map<String, Object> params,
  ) async {
    // params 为需要加密的请求参数
    final String mixinKey = await getWbiKeys();
    encWbi(params, mixinKey);
    ApiBlackbox.log('WbiSign', 'makSign generated w_rid=${params['w_rid']}, wts=${params['wts']}');
    return params;
  }
}
