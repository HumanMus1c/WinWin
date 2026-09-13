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
  final int? seasonId;
  final int? epId;
  final int? mediaId;
  final int? roomId;
  final int? articleId;

  const BilibiliUrlParseResult({
    this.bvid,
    this.aid,
    this.dynamicId,
    this.seasonId,
    this.epId,
    this.mediaId,
    this.roomId,
    this.articleId,
  });

  bool get isBangumi => seasonId != null || epId != null || mediaId != null;
  bool get isLive => roomId != null;
  bool get isArticle => articleId != null;

  bool get isValid =>
      bvid != null ||
      aid != null ||
      dynamicId != null ||
      isBangumi ||
      isLive ||
      isArticle;

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
      'BilibiliUrlParseResult(bvid: $bvid, aid: $aid, dynamicId: $dynamicId, seasonId: $seasonId, epId: $epId, mediaId: $mediaId, roomId: $roomId, articleId: $articleId)';
}

abstract final class BilibiliUrlParser {
  // 动态 ID 最小值阈值：≥ 1e17 判定为动态 ID 而非视频 aid
  static const int _likelyDynamicIdMinValue = 100000000000000000;

  static final _bvRegex = RegExp(r'BV([a-zA-Z0-9]{10})', caseSensitive: false);
  static final _avRegex = RegExp(r'av(\d+)', caseSensitive: false);
  static final _videoAidPathRegex =
      RegExp(r'/video/(\d+)(?:[/?#]|$)', caseSensitive: false);
  static final _epRegex =
      RegExp(r'(?:/bangumi/play/|/ep|^|\b)ep(\d+)', caseSensitive: false);
  static final _ssRegex =
      RegExp(r'(?:/bangumi/play/|/ss|^|\b)ss(\d+)', caseSensitive: false);
  static final _mdRegex =
      RegExp(r'(?:/bangumi/media/|/md|^|\b)md(\d+)', caseSensitive: false);
  static final _opusDynamicRegex =
      RegExp(r'/(opus|dynamic)/(\d+)', caseSensitive: false);
  static final _tBilibiliDynamicRegex =
      RegExp(r't\.bilibili\.com/(\d+)', caseSensitive: false);
  static final _liveRegex = RegExp(
    r'(?:live\.bilibili\.com/(?:h5/|blanc/)?|bilibili://live/)(\d+)',
    caseSensitive: false,
  );
  static final _cvRegex = RegExp(
    r'(?:/read/(?:cv)?)(\d+)',
    caseSensitive: false,
  );

  /// 从任意文本中提取 B 站视频/动态/直播/专栏标识。
  ///
  /// 优先级：BV 号 → AV 号 → /video/{aid} 路径 → opus/t.bilibili 动态 ID → 直播间 → 专栏。
  static BilibiliUrlParseResult parse(String input) {
    if (input.isEmpty) return const BilibiliUrlParseResult();

    // 直播间
    final liveMatch = _liveRegex.firstMatch(input);
    if (liveMatch != null) {
      final roomId = int.tryParse(liveMatch.group(1)!);
      if (roomId != null) {
        return BilibiliUrlParseResult(roomId: roomId);
      }
    }

    // 专栏文章 cv
    final cvMatch = _cvRegex.firstMatch(input);
    if (cvMatch != null) {
      final articleId = int.tryParse(cvMatch.group(1)!);
      if (articleId != null) {
        return BilibiliUrlParseResult(articleId: articleId);
      }
    }

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

    // ep 号 (番剧单集)
    final epMatch = _epRegex.firstMatch(input);
    if (epMatch != null) {
      final epId = int.tryParse(epMatch.group(1)!);
      if (epId != null) {
        return BilibiliUrlParseResult(epId: epId);
      }
    }

    // ss 号 (番剧季)
    final ssMatch = _ssRegex.firstMatch(input);
    if (ssMatch != null) {
      final seasonId = int.tryParse(ssMatch.group(1)!);
      if (seasonId != null) {
        return BilibiliUrlParseResult(seasonId: seasonId);
      }
    }

    // md 号 (番剧 media)
    final mdMatch = _mdRegex.firstMatch(input);
    if (mdMatch != null) {
      final mediaId = int.tryParse(mdMatch.group(1)!);
      if (mediaId != null) {
        return BilibiliUrlParseResult(mediaId: mediaId);
      }
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

    // bilibili://live/{roomId}
    if (host == 'live') {
      if (uri.pathSegments.isNotEmpty) {
        final roomId = int.tryParse(uri.pathSegments.first);
        if (roomId != null) return BilibiliUrlParseResult(roomId: roomId);
      }
      final roomIdStr = uri.queryParameters['room_id'] ??
          uri.queryParameters['roomId'];
      if (roomIdStr != null) {
        final roomId = int.tryParse(roomIdStr);
        if (roomId != null) return BilibiliUrlParseResult(roomId: roomId);
      }
      return const BilibiliUrlParseResult();
    }

    // bilibili://article/{id} 或 bilibili://read/{id}
    if (host == 'article' || host == 'read') {
      if (uri.pathSegments.isNotEmpty) {
        final cvStr = uri.pathSegments.first
            .replaceAll(RegExp(r'^cv', caseSensitive: false), '');
        final articleId = int.tryParse(cvStr);
        if (articleId != null) return BilibiliUrlParseResult(articleId: articleId);
      }
      final idStr = uri.queryParameters['id'] ??
          uri.queryParameters['article_id'];
      if (idStr != null) {
        final id = int.tryParse(idStr);
        if (id != null) return BilibiliUrlParseResult(articleId: id);
      }
      return const BilibiliUrlParseResult();
    }

    // bilibili://bangumi/season/{seasonId} 或 bilibili://pgc/...
    if (host == 'bangumi' || host == 'pgc' || host == 'season') {
      final seasonIdStr = uri.queryParameters['season_id'] ??
          uri.queryParameters['seasonId'];
      final epIdStr = uri.queryParameters['ep_id'] ??
          uri.queryParameters['epId'];
      final mediaIdStr = uri.queryParameters['media_id'] ??
          uri.queryParameters['mediaId'];
      int? seasonId = int.tryParse(seasonIdStr ?? '');
      int? epId = int.tryParse(epIdStr ?? '');
      int? mediaId = int.tryParse(mediaIdStr ?? '');

      for (final segment in uri.pathSegments) {
        if (segment.startsWith('ss')) {
          seasonId ??= int.tryParse(segment.substring(2));
        } else if (segment.startsWith('ep')) {
          epId ??= int.tryParse(segment.substring(2));
        } else if (segment.startsWith('md')) {
          mediaId ??= int.tryParse(segment.substring(2));
        } else if (int.tryParse(segment) != null) {
          seasonId ??= int.tryParse(segment);
        }
      }

      if (seasonId != null || epId != null || mediaId != null) {
        return BilibiliUrlParseResult(
          seasonId: seasonId,
          epId: epId,
          mediaId: mediaId,
        );
      }
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
    final seasonIdStr = uri.queryParameters['season_id'] ??
        uri.queryParameters['seasonId'];
    if (seasonIdStr != null) {
      final sId = int.tryParse(seasonIdStr);
      if (sId != null) return BilibiliUrlParseResult(seasonId: sId);
    }
    final epIdStr = uri.queryParameters['ep_id'] ??
        uri.queryParameters['epId'];
    if (epIdStr != null) {
      final eId = int.tryParse(epIdStr);
      if (eId != null) return BilibiliUrlParseResult(epId: eId);
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
