// Ported from BiliPai (Kotlin) -> WinWin (Dart)
// Original: com/android/purebilibili/domain/SponsorBlockUseCase.kt
//
// SponsorBlock 段落加载、位置检查、自动跳过逻辑。
//
// B 站 SponsorBlock 数据走 bsbsb.top 镜像（非官方 sponsor.ajay.app），
// 支持 bvid 查询。段落类型与官方 SponsorBlock 对齐（sponsor/selfpromo/...）。
//
// 接入方式：
//   [WinWinPlayerController] 在 load() 完成后调用 [fetchSegments] 加载段落，
//   position 轮询中调用 [findActiveSegment] 检查当前位置是否在可跳过段落内，
//   命中则 seek 到段落结尾实现自动跳过。

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:winwin/common/constants.dart';
import 'package:winwin/http/constants.dart';
import 'package:winwin/http/loading_state.dart';

/// SponsorBlock 段落类型（与官方 SponsorBlock 对齐）。
enum SponsorBlockCategory {
  /// 赞助商广告（up 主接的商单）。
  sponsor,
  /// 自我推广（up 主推广自己的频道/其他视频）。
  selfPromo,
  /// 无意义的互动提醒（点赞/订阅/关注提示）。
  interaction,
  /// 片头/片尾。
  intro,
  outro,
  /// 纯音乐段（无配音）。
  musicOfftopic,
  /// 预览/ Recap（前情提要）。
  preview,
  /// 填充内容（无意义的拖时长）。
  filler,
  /// 未知类型。
  unknown;

  /// 从字符串解析。
  static SponsorBlockCategory fromString(String? value) {
    switch (value) {
      case 'sponsor':
        return SponsorBlockCategory.sponsor;
      case 'selfpromo':
        return SponsorBlockCategory.selfPromo;
      case 'interaction':
        return SponsorBlockCategory.interaction;
      case 'intro':
        return SponsorBlockCategory.intro;
      case 'outro':
        return SponsorBlockCategory.outro;
      case 'music_offtopic':
        return SponsorBlockCategory.musicOfftopic;
      case 'preview':
        return SponsorBlockCategory.preview;
      case 'filler':
        return SponsorBlockCategory.filler;
      default:
        return SponsorBlockCategory.unknown;
    }
  }

  /// SponsorBlock 社区 API 的类别名（提交/查询时使用）。
  String get wireName {
    switch (this) {
      case SponsorBlockCategory.sponsor:
        return 'sponsor';
      case SponsorBlockCategory.selfPromo:
        return 'selfpromo';
      case SponsorBlockCategory.interaction:
        return 'interaction';
      case SponsorBlockCategory.intro:
        return 'intro';
      case SponsorBlockCategory.outro:
        return 'outro';
      case SponsorBlockCategory.musicOfftopic:
        return 'music_offtopic';
      case SponsorBlockCategory.preview:
        return 'preview';
      case SponsorBlockCategory.filler:
        return 'filler';
      case SponsorBlockCategory.unknown:
        return 'sponsor';
    }
  }

  /// 是否默认启用自动跳过。
  ///
  /// sponsor / selfPromo / interaction 默认跳过；
  /// intro / outro / preview / filler 默认不跳过（用户可选开启）；
  /// musicOfftopic 默认不跳过（对音乐视频用户有用）。
  bool get defaultSkipEnabled {
    switch (this) {
      case SponsorBlockCategory.sponsor:
      case SponsorBlockCategory.selfPromo:
      case SponsorBlockCategory.interaction:
        return true;
      default:
        return false;
    }
  }

  /// 中文显示名称。
  String get label {
    switch (this) {
      case SponsorBlockCategory.sponsor:
        return '赞助广告';
      case SponsorBlockCategory.selfPromo:
        return '自我推广';
      case SponsorBlockCategory.interaction:
        return '互动提醒';
      case SponsorBlockCategory.intro:
        return '片头';
      case SponsorBlockCategory.outro:
        return '片尾';
      case SponsorBlockCategory.musicOfftopic:
        return '纯音乐段';
      case SponsorBlockCategory.preview:
        return '前情提要';
      case SponsorBlockCategory.filler:
        return '填充内容';
      case SponsorBlockCategory.unknown:
        return '未知';
    }
  }
}

/// SponsorBlock 段落。
class SponsorBlockSegment {
  /// 段落开始时间（秒）。
  final double start;
  /// 段落结束时间（秒）。
  final double end;
  /// 段落类型。
  final SponsorBlockCategory category;
  /// 段落唯一标识（用于投票/提交）。
  final String uuid;

  const SponsorBlockSegment({
    required this.start,
    required this.end,
    required this.category,
    required this.uuid,
  });

  /// 段落时长（秒）。
  double get duration => end - start;

  /// 判断 [positionSec] 是否在段落内。
  bool contains(double positionSec) {
    return positionSec >= start && positionSec < end;
  }

  factory SponsorBlockSegment.fromJson(List<dynamic> json) {
    // bsbsb.top 返回数组：[start, end, category, uuid]
    // 与官方 SponsorBlock 的对象格式不同。
    return SponsorBlockSegment(
      start: _asDouble(json.elementAt(0)) ?? 0,
      end: _asDouble(json.elementAt(1)) ?? 0,
      category: SponsorBlockCategory.fromString(
        json.elementAt(2)?.toString(),
      ),
      uuid: json.elementAt(3)?.toString() ?? '',
    );
  }
}

/// 社区片段提交结果。
class SponsorBlockSubmitResult {
  const SponsorBlockSubmitResult.success() : error = null;

  const SponsorBlockSubmitResult.failure(this.error);

  final String? error;

  bool get isSuccess => error == null;
}

/// SponsorBlock 用例：段落加载、位置检查、自动跳过决策。
class SponsorBlockUseCase {
  SponsorBlockUseCase({Dio? dio}) : _dio = dio ?? _createDio();

  final Dio _dio;

  static final Future<PackageInfo> _packageInfo =
      PackageInfo.fromPlatform();

  /// 社区 API 请求头（对齐 BiliPai / PiliPlus 的来源标识）。
  Future<Map<String, String>> _communityHeaders() async {
    String version = '1.0.0';
    try {
      version = (await _packageInfo).version;
    } catch (_) {}
    return {
      'origin': Constants.appName,
      'x-ext-version': version,
      'User-Agent': '${Constants.appName}/$version',
    };
  }

  /// 已加载的段落列表（按 start 排序）。
  List<SponsorBlockSegment> _segments = const [];
  List<SponsorBlockSegment> get segments => _segments;

  /// 各类型是否启用自动跳过（默认用 [SponsorBlockCategory.defaultSkipEnabled]）。
  final Map<SponsorBlockCategory, bool> _skipEnabled = {
    for (final c in SponsorBlockCategory.values) c: c.defaultSkipEnabled,
  };

  /// 上次跳过的段落（避免同一秒重复触发 seek）。
  SponsorBlockSegment? _lastSkipped;

  static Dio _createDio() {
    return Dio(
      BaseOptions(
        baseUrl: HttpString.sponsorBlockBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        validateStatus: (_) => true,
      ),
    );
  }

  /// 设置某类段落的自动跳过开关。
  void setSkipEnabled(SponsorBlockCategory category, bool enabled) {
    _skipEnabled[category] = enabled;
  }

  /// 查询某类段落是否启用自动跳过。
  bool isSkipEnabled(SponsorBlockCategory category) {
    return _skipEnabled[category] ?? category.defaultSkipEnabled;
  }

  /// 加载视频的 SponsorBlock 段落。
  ///
  /// [bvid] 用于查询 bsbsb.top 镜像。失败时返回空列表（不阻断播放）。
  Future<LoadingState<List<SponsorBlockSegment>>> fetchSegments({
    required String bvid,
  }) async {
    if (bvid.isEmpty) return const Success(<SponsorBlockSegment>[]);
    try {
      // bsbsb.top 镜像端点：/api/skipSegments?bvid=<bvid>
      // 返回格式：[[start, end, category, uuid], ...]
      final res = await _dio.get<dynamic>(
        '/api/skipSegments',
        queryParameters: {'bvid': bvid},
      );
      final data = res.data;
      if (data is! List) {
        _segments = const <SponsorBlockSegment>[];
        return Success(_segments);
      }
      final parsed = data
          .whereType<List>()
          .map((e) => SponsorBlockSegment.fromJson(e))
          .where((s) => s.end > s.start && s.duration > 0.5)
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));
      _segments = parsed;
      _lastSkipped = null;
      return Success(parsed);
    } on DioException catch (e) {
      // 404 = 无段落（正常情况），不视为错误。
      if (e.response?.statusCode == 404) {
        _segments = const <SponsorBlockSegment>[];
        return Success(_segments);
      }
      return Error('SponsorBlock 加载失败：${e.message ?? e.type.name}');
    } catch (e) {
      return Error('SponsorBlock 加载失败：$e');
    }
  }

  /// 查找 [positionSec] 所在的可跳过段落。
  ///
  /// 返回第一个命中的、且启用了自动跳过的段落；无命中返回 null。
  /// 已跳过的段落（[ _lastSkipped]）不重复返回，避免 seek 后又被检测到。
  SponsorBlockSegment? findActiveSegment(double positionSec) {
    for (final segment in _segments) {
      if (!segment.contains(positionSec)) continue;
      if (!isSkipEnabled(segment.category)) continue;
      if (identical(segment, _lastSkipped)) continue;
      _lastSkipped = segment;
      return segment;
    }
    return null;
  }

  /// 判断 [positionSec] 是否在某个可跳过段落内（便捷方法）。
  bool shouldSkip(double positionSec) {
    return findActiveSegment(positionSec) != null;
  }

  /// 计算应跳转到的目标位置（段落结尾）。
  ///
  /// 返回 null 表示无需跳转。
  double? computeSkipTarget(double positionSec) {
    final segment = findActiveSegment(positionSec);
    if (segment == null) return null;
    return segment.end;
  }

  /// 清空段落（切换视频时调用）。
  void clear() {
    _segments = const <SponsorBlockSegment>[];
    _lastSkipped = null;
  }

  /// 向社区上报一个片段（提交前必须由用户确认）。
  ///
  /// 对齐 BiliPai `SponsorBlockRepository.submitSegments` 与
  /// PiliPlus `SponsorBlock.postSkipSegments` 的请求结构。
  Future<SponsorBlockSubmitResult> submitSegment({
    required String bvid,
    required int cid,
    required double videoDurationSeconds,
    required double startSeconds,
    required double endSeconds,
    required String category,
    required String actionType,
    required String userId,
  }) async {
    if (bvid.isEmpty || cid <= 0) {
      return const SponsorBlockSubmitResult.failure('视频标识无效');
    }
    if (startSeconds < 0 || endSeconds <= startSeconds) {
      return const SponsorBlockSubmitResult.failure('片段时间范围无效');
    }
    if (userId.isEmpty) {
      return const SponsorBlockSubmitResult.failure('社区用户 ID 无效');
    }

    try {
      final headers = await _communityHeaders();
      final version = headers['x-ext-version'] ?? '1.0.0';
      final res = await _dio.post<dynamic>(
        '/api/skipSegments',
        data: {
          'videoID': bvid,
          'cid': '$cid',
          'userID': userId,
          'videoDuration': videoDurationSeconds,
          'userAgent': '${Constants.appName}/$version',
          'segments': [
            {
              'segment': [startSeconds, endSeconds],
              'category': category,
              'actionType': actionType,
            },
          ],
        },
        options: Options(
          headers: headers,
          contentType: Headers.jsonContentType,
        ),
      );
      if (res.statusCode == 200) {
        return const SponsorBlockSubmitResult.success();
      }
      return SponsorBlockSubmitResult.failure(
        _statusError(res.statusCode, res.data),
      );
    } on DioException catch (error) {
      return SponsorBlockSubmitResult.failure(
        '上报失败：${error.message ?? error.type.name}',
      );
    } catch (error) {
      return SponsorBlockSubmitResult.failure('上报失败：$error');
    }
  }

  /// 对社区片段投票：1=有用，0=不准确。
  Future<String?> voteSegment({
    required String uuid,
    required int type,
    required String userId,
  }) async {
    if (uuid.isEmpty) return '片段标识无效';
    try {
      final res = await _dio.post<dynamic>(
        '/api/voteOnSponsorTime',
        data: {'UUID': uuid, 'userID': userId, 'type': type},
        options: Options(
          headers: await _communityHeaders(),
          contentType: Headers.jsonContentType,
        ),
      );
      if (res.statusCode == 200) return null;
      return _statusError(res.statusCode, res.data);
    } on DioException catch (error) {
      return '投票失败：${error.message ?? error.type.name}';
    } catch (error) {
      return '投票失败：$error';
    }
  }

  String _statusError(int? code, dynamic data) {
    final detail = data is String ? data.trim() : '';
    final message = switch (code) {
      400 => '参数错误',
      403 => '被自动审核机制拒绝',
      404 => '未找到数据',
      409 => '重复提交',
      429 => '提交太快，请稍后重试',
      500 => '服务器无法处理请求',
      _ => '服务器错误（HTTP $code）',
    };
    if (detail.isEmpty || detail.length > 120) return message;
    return '$message：$detail';
  }

  void dispose() {
    _dio.close();
  }
}

double? _asDouble(Object? value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
