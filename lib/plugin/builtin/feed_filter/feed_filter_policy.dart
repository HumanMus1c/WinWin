import 'package:winwin/models/video/rec_video_item.dart';

/// 推荐流来源（用于「仅对首页 / 热门 / 排行 / 搜索生效」开关）。
enum FeedKind { recommend, popular, rank, search, generic }

/// 推荐流过滤配置（默认值对齐 BiliPai `BiliPaiFeedFilterConfig`）。
class FeedFilterConfig {
  const FeedFilterConfig({
    this.minDurationForRcmd = 0,
    this.minPlayForRcmd = 0,
    this.minLikeRatioForRecommend = 0,
    this.banWordForRecommend = '',
    this.banWordForZone = '',
    this.recommendBlockedMids = const {},
    this.whitelistMids = const {},
    this.exemptFilterForFollowed = true,
    this.applyToHotVideos = false,
    this.applyToRankVideos = false,
    this.applyToSearch = false,
  });

  final int minDurationForRcmd;
  final int minPlayForRcmd;
  final int minLikeRatioForRecommend;
  final String banWordForRecommend;
  final String banWordForZone;
  final Map<int, String> recommendBlockedMids;
  final Map<int, String> whitelistMids;
  final bool exemptFilterForFollowed;
  final bool applyToHotVideos;
  final bool applyToRankVideos;
  final bool applyToSearch;

  factory FeedFilterConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const FeedFilterConfig();
    return FeedFilterConfig(
      minDurationForRcmd: _readInt(json['minDurationForRcmd']),
      minPlayForRcmd: _readInt(json['minPlayForRcmd']),
      minLikeRatioForRecommend: _readInt(json['minLikeRatioForRecommend']),
      banWordForRecommend: json['banWordForRecommend']?.toString() ?? '',
      banWordForZone: json['banWordForZone']?.toString() ?? '',
      recommendBlockedMids: _readMids(json['recommendBlockedMids']),
      whitelistMids: _readMids(json['whitelistMids']),
      exemptFilterForFollowed: json['exemptFilterForFollowed'] != false,
      applyToHotVideos: json['applyToHotVideos'] == true,
      applyToRankVideos: json['applyToRankVideos'] == true,
      applyToSearch: json['applyToSearch'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'minDurationForRcmd': minDurationForRcmd,
        'minPlayForRcmd': minPlayForRcmd,
        'minLikeRatioForRecommend': minLikeRatioForRecommend,
        'banWordForRecommend': banWordForRecommend,
        'banWordForZone': banWordForZone,
        'recommendBlockedMids': {
          for (final entry in recommendBlockedMids.entries)
            '${entry.key}': entry.value,
        },
        'whitelistMids': {
          for (final entry in whitelistMids.entries)
            '${entry.key}': entry.value,
        },
        'exemptFilterForFollowed': exemptFilterForFollowed,
        'applyToHotVideos': applyToHotVideos,
        'applyToRankVideos': applyToRankVideos,
        'applyToSearch': applyToSearch,
      };

  FeedFilterConfig copyWith({
    int? minDurationForRcmd,
    int? minPlayForRcmd,
    int? minLikeRatioForRecommend,
    String? banWordForRecommend,
    String? banWordForZone,
    Map<int, String>? recommendBlockedMids,
    Map<int, String>? whitelistMids,
    bool? exemptFilterForFollowed,
    bool? applyToHotVideos,
    bool? applyToRankVideos,
    bool? applyToSearch,
  }) =>
      FeedFilterConfig(
        minDurationForRcmd:
            minDurationForRcmd ?? this.minDurationForRcmd,
        minPlayForRcmd: minPlayForRcmd ?? this.minPlayForRcmd,
        minLikeRatioForRecommend:
            minLikeRatioForRecommend ?? this.minLikeRatioForRecommend,
        banWordForRecommend:
            banWordForRecommend ?? this.banWordForRecommend,
        banWordForZone: banWordForZone ?? this.banWordForZone,
        recommendBlockedMids:
            recommendBlockedMids ?? this.recommendBlockedMids,
        whitelistMids: whitelistMids ?? this.whitelistMids,
        exemptFilterForFollowed:
            exemptFilterForFollowed ?? this.exemptFilterForFollowed,
        applyToHotVideos: applyToHotVideos ?? this.applyToHotVideos,
        applyToRankVideos: applyToRankVideos ?? this.applyToRankVideos,
        applyToSearch: applyToSearch ?? this.applyToSearch,
      );

  static int _readInt(Object? value) {
    if (value is int) return value < 0 ? 0 : value;
    if (value is num) return value.toInt().clamp(0, 1 << 31);
    return int.tryParse(value?.toString() ?? '')?.clamp(0, 1 << 31) ?? 0;
  }

  static Map<int, String> _readMids(Object? value) {
    if (value is! Map) return const {};
    final result = <int, String>{};
    for (final entry in value.entries) {
      final mid = int.tryParse(entry.key.toString());
      if (mid != null && mid > 0) result[mid] = entry.value.toString();
    }
    return result;
  }
}

/// 推荐流过滤纯函数（对应 BiliPai `shouldShowFeedItem`）。
abstract final class FeedFilterPolicy {
  /// 换行分隔、trim、去空；含 `|` 且不以 `(` 开头的项包成 `(item)`；
  /// 最后用 `|` 连接（对齐 BiliPai `parseBanWordToRegex`）。
  static RegExp? parseBanWordToRegex(String stored) {
    final items = stored
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((line) =>
            line.contains('|') && !line.startsWith('(') ? '($line)' : line)
        .toList(growable: false);
    if (items.isEmpty) return null;
    try {
      return RegExp(items.join('|'), caseSensitive: false);
    } catch (_) {
      return null;
    }
  }

  /// 每行一个 UID；支持纯数字或「名称 (UID)」。
  static Map<int, String> parseUidMap(String text) {
    final result = <int, String>{};
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final match = RegExp(r'(\d+)').firstMatch(trimmed);
      final mid = match != null
          ? int.tryParse(match.group(1)!)
          : int.tryParse(trimmed);
      if (mid != null && mid > 0) result[mid] = trimmed;
    }
    return result;
  }

  static String uidMapToEditorText(Map<int, String> mids) {
    return [
      for (final entry in mids.entries)
        if (entry.value.isEmpty || entry.value == 'UID:${entry.key}')
          '${entry.key}'
        else
          '${entry.value} (${entry.key})',
    ].join('\n');
  }

  static bool shouldShow({
    required FeedFilterConfig config,
    required BaseRcmdVideoItemModel item,
    required FeedKind kind,
    RegExp? titleRegex,
    RegExp? zoneRegex,
  }) {
    final allowedByKind = switch (kind) {
      FeedKind.popular => config.applyToHotVideos,
      FeedKind.rank => config.applyToRankVideos,
      FeedKind.search => config.applyToSearch,
      _ => true,
    };
    if (!allowedByKind) return true;

    final mid = item.owner.mid ?? 0;
    if (mid > 0 && config.whitelistMids.containsKey(mid)) return true;

    if (kind == FeedKind.recommend &&
        item.isFollowed &&
        config.exemptFilterForFollowed) {
      return true;
    }

    // 番剧卡片没有同口径的播放/点赞统计，跳过统计类过滤。
    final hasVideoStatistics = item.goto != 'bangumi';
    final duration = item.duration;
    if (hasVideoStatistics &&
        duration > 0 &&
        config.minDurationForRcmd > 0 &&
        duration < config.minDurationForRcmd) {
      return false;
    }

    final view = item.stat.view;
    final like = item.stat.like;
    if (hasVideoStatistics && view != null) {
      if (config.minPlayForRcmd > 0 && view < config.minPlayForRcmd) {
        return false;
      }
      if (config.minLikeRatioForRecommend > 0 && like != null) {
        // 整数乘法，避免浮点误差。
        if (like * 100 < config.minLikeRatioForRecommend * view) {
          return false;
        }
      }
    }

    final title = item.title;
    if (titleRegex != null && title != null && titleRegex.hasMatch(title)) {
      return false;
    }

    if (mid > 0 && config.recommendBlockedMids.containsKey(mid)) {
      return false;
    }

    final tname = item.tname;
    if (tname != null &&
        tname.isNotEmpty &&
        zoneRegex != null &&
        zoneRegex.hasMatch(tname)) {
      return false;
    }

    return true;
  }
}
