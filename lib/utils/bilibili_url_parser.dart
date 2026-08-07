import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;

/// B 站 URL 解析器 — 从 BiliPai BilibiliUrlParser.kt 移植。
///
/// 支持解析：BV 号、AV 号、视频路径、动态 ID、opus/t.bilibili.com 链接、
/// b23.tv 短链、bilibili:// 自定义 scheme、完整 web URL。
class BilibiliUrlParseResult {
  final String? bvid;
  final int? aid;
  final String? dynamicId;

  const BilibiliUrlParseResult({
    this.bvid,
    this.aid,
    this.dynamicId,
  });

  bool get isValid => bvid != null || aid != null || dynamicId != null;

  /// 返回视频标识（优先 BV，其次 AV）。
  String? get videoId {
    if (bvid != null) return bvid;
    if (aid != null) return 'av$aid';
    return null;
  }

  /// 返回动态目标 ID。
  String? get dynamicTargetId => dynamicId;

  @override
  String toString() =>
      'BilibiliUrlParseResult(bvid: $bvid, aid: $aid, dynamicId: $dynamicId)';
}

abstract final class BilibiliUrlParser {
  // 动态 ID 最小值阈值：≥ 1e17 判定为动态 ID 而非视频 aid
  static const int _likelyDynamicIdMinValue = 100000000000000000;

  static final _bvRegex = RegExp(r'BV([a-zA-Z0-9]{10})', caseSensitive: false);
  static final _avRegex = RegExp(r'av(\d+)', caseSensitive: false);
  static final _videoAidPathRegex =
      RegExp(r'/video/(\d+)(?:[/?#]|$)', caseSensitive: false);
  static final _opusDynamicRegex =
      RegExp(r'/(opus|dynamic)/(\d+)', caseSensitive: false);
  static final _tBilibiliDynamicRegex =
      RegExp(r't\.bilibili\.com/(\d+)', caseSensitive: false);

  /// 从任意文本中提取 B 站视频/动态标识。
  ///
  /// 优先级：BV 号 → AV 号 → /video/{aid} 路径 → opus/t.bilibili 动态 ID。
  static BilibiliUrlParseResult parse(String input) {
    if (input.isEmpty) return const BilibiliUrlParseResult();

    // BV 号
    final bvMatch = _bvRegex.firstMatch(input);
    if (bvMatch != null) {
      return BilibiliUrlParseResult(bvid: 'BV${bvMatch.group(1)}');
    }

    // AV 号
    final avMatch = _avRegex.firstMatch(input);
    if (avMatch != null) {
      final aid = int.tryParse(avMatch.group(1)!);
      if (aid != null) {
        if (aid >= _likelyDynamicIdMinValue) {
          return BilibiliUrlParseResult(dynamicId: aid.toString());
        }
        return BilibiliUrlParseResult(aid: aid);
      }
    }

    // /video/{aid} 路径
    final pathMatch = _videoAidPathRegex.firstMatch(input);
    if (pathMatch != null) {
      final aid = int.tryParse(pathMatch.group(1)!);
      if (aid != null) {
        if (aid >= _likelyDynamicIdMinValue) {
          return BilibiliUrlParseResult(dynamicId: aid.toString());
        }
        return BilibiliUrlParseResult(aid: aid);
      }
    }

    // opus/dynamic ID
    final opusMatch = _opusDynamicRegex.firstMatch(input);
    if (opusMatch != null) {
      return BilibiliUrlParseResult(dynamicId: opusMatch.group(2));
    }

    // t.bilibili.com/{dynamicId}
    final tMatch = _tBilibiliDynamicRegex.firstMatch(input);
    if (tMatch != null) {
      return BilibiliUrlParseResult(dynamicId: tMatch.group(1));
    }

    return const BilibiliUrlParseResult();
  }

  /// 解析完整深度链接（bilibili:// 或 https:// 链接）。
  static BilibiliUrlParseResult parseDeepLink(String rawUri) {
    if (rawUri.isEmpty) return const BilibiliUrlParseResult();

    final uri = Uri.tryParse(rawUri);
    if (uri == null) return parse(rawUri);

    final scheme = uri.scheme.toLowerCase();

    // 自定义 scheme: bilibili:// 或 bili://
    if (scheme == 'bilibili' || scheme == 'bili') {
      return _parseCustomScheme(uri);
    }

    // b23.tv 短链
    if (uri.host == 'b23.tv') {
      // 先从 path 尝试解析
      final pathResult = parse(uri.toString());
      if (pathResult.isValid) return pathResult;
      // path 无法解析时需异步跟随重定向，这里返回空结果
      return const BilibiliUrlParseResult();
    }

    // bilibili.com 域名
    if (uri.host.contains('bilibili.com')) {
      // 先从 path 尝试解析
      final pathResult = parse(uri.toString());
      if (pathResult.isValid) return pathResult;

      // 尝试 wrapped url（url/jump_url/target_url/web_url/origin_url query 参数）
      final wrappedUrl = _extractWrappedUrl(uri);
      if (wrappedUrl != null) {
        return parseDeepLink(wrappedUrl);
      }
    }

    // 其他 host 尝试 wrapped url
    final wrappedUrl = _extractWrappedUrl(uri);
    if (wrappedUrl != null) {
      return parseDeepLink(wrappedUrl);
    }

    return parse(rawUri);
  }

  /// 异步解析 b23.tv 短链，HTTP HEAD 跟随 3xx 重定向取 Location。
  static Future<String?> resolveShortUrl(String shortUrl) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final request = await client.headUrl(Uri.parse(shortUrl));
      request.followRedirects = false;
      final response = await request.close();
      final location = response.headers.value(HttpHeaders.locationHeader);
      client.close(force: true);
      return location;
    } catch (e) {
      debugPrint('resolveShortUrl error: $e');
      return null;
    }
  }

  /// 从文本中提取所有 URL。
  static List<String> extractUrls(String text) {
    final urlRegex = RegExp(
      r'https?://[^\s<>"{}|\\^`\[\]]+',
      caseSensitive: false,
    );
    return urlRegex
        .allMatches(text)
        .map((m) => m.group(0)!)
        .toList();
  }

  static BilibiliUrlParseResult _parseCustomScheme(Uri uri) {
    final host = uri.host.toLowerCase();

    // bilibili://video/{aid} 或 bilibili://video?bvid=xxx
    if (host == 'video') {
      // 从路径提取 aid
      if (uri.pathSegments.isNotEmpty) {
        final aid = int.tryParse(uri.pathSegments.first);
        if (aid != null) {
          return BilibiliUrlParseResult(aid: aid);
        }
      }
      // 从 query 提取 bvid/aid
      final bvid = uri.queryParameters['bvid'];
      if (bvid != null) return BilibiliUrlParseResult(bvid: bvid);
      final aidStr = uri.queryParameters['aid'];
      if (aidStr != null) {
        final aid = int.tryParse(aidStr);
        if (aid != null) return BilibiliUrlParseResult(aid: aid);
      }
      return const BilibiliUrlParseResult();
    }

    // bilibili://opus/{id} 或 bilibili://dynamic/{id}
    if (host == 'opus' || host == 'dynamic') {
      if (uri.pathSegments.isNotEmpty) {
        return BilibiliUrlParseResult(dynamicId: uri.pathSegments.first);
      }
      return const BilibiliUrlParseResult();
    }

    // bilibili://root 或 bilibili://main — 尝试从 query 解析
    final bvid = uri.queryParameters['bvid'];
    if (bvid != null) return BilibiliUrlParseResult(bvid: bvid);
    final aidStr = uri.queryParameters['aid'];
    if (aidStr != null) {
      final aid = int.tryParse(aidStr);
      if (aid != null) {
        if (aid >= _likelyDynamicIdMinValue) {
          return BilibiliUrlParseResult(dynamicId: aid.toString());
        }
        return BilibiliUrlParseResult(aid: aid);
      }
    }

    return const BilibiliUrlParseResult();
  }

  /// 从 query 参数中提取 wrapped url（url/jump_url/target_url/web_url/origin_url）。
  static String? _extractWrappedUrl(Uri uri) {
    const wrappedKeys = [
      'url',
      'jump_url',
      'target_url',
      'web_url',
      'origin_url',
    ];
    for (final key in wrappedKeys) {
      final value = uri.queryParameters[key];
      if (value != null && value.isNotEmpty) {
        // wrapped url 可能被 URL 编码
        final decoded = Uri.decodeComponent(value);
        if (decoded.startsWith('http://') ||
            decoded.startsWith('https://') ||
            decoded.startsWith('bilibili://')) {
          return decoded;
        }
      }
    }
    return null;
  }
}
