import 'package:winwin/http/api.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/video.dart';
import 'package:winwin/models/video/play_url.dart';

/// 下载 HTTP（移植自 PiliPlus `lib/http/download.dart`）。
///
/// Phase 5 下载系统的前置 HTTP 模块：封装 playurl 请求 → 下载流选择逻辑。
///
/// 返回 [DownloadMediaInfo] 结构，包含视频流/音频流的 CDN URL、
/// 画质/编码信息、referer/userAgent 等下载所需的全部元数据。
///
/// 与 PiliPlus 的差异：
/// - 不引入 BiliDownloadEntryInfo / Type1File / Type2File 等完整模型链
/// - 不依赖 VideoUtils.selectCodec / getCdnUrl（Phase 5 下载系统实施时补齐）
/// - 简化为直接返回 PlayUrlModel，由下载服务层按需选取流
abstract final class DownloadHttp {
  static const String referer = 'https://www.bilibili.com/';
  static const String userAgent = 'Bilibili Freedoooooom/MarkII';

  /// 获取视频下载流信息。
  ///
  /// - [bvid]/[avid]/[cid]：视频标识。
  /// - [preferQuality]：期望画质（qn），默认 80（480P）。
  ///
  /// 成功返回 [DownloadMediaInfo]，含 DASH 视频流列表和音频流列表。
  /// 调用方根据 [DownloadMediaInfo.dash] 自行选择流并拼接 CDN URL。
  static Future<LoadingState<DownloadMediaInfo>> getVideoUrl({
    String? bvid,
    int? avid,
    required int cid,
    int preferQuality = 80,
  }) async {
    final res = await VideoHttp.videoUrl(
      bvid: bvid,
      avid: avid,
      cid: cid,
      qn: preferQuality,
    );
    if (res case Success(:final response)) {
      return Success(DownloadMediaInfo.fromPlayUrl(response));
    } else {
      return Error(res.toString());
    }
  }
}

/// 下载媒体信息（从 PlayUrlModel 提取的关键字段）。
///
/// 下载服务层根据此信息选择具体的视频流/音频流并拼接 CDN URL。
class DownloadMediaInfo {
  /// 视频时长（秒）。
  final int? duration;

  /// DASH 视频流列表（按画质/编码排序）。
  final List<DownloadVideoStream> videoStreams;

  /// DASH 音频流列表（按音质排序）。
  final List<DownloadAudioStream> audioStreams;

  /// 当前画质。
  final int? quality;

  /// 支持的画质列表。
  final List<int>? acceptQuality;

  /// 支持的格式列表。
  final List<FormatItem>? supportFormats;

  /// DASH 流还是 DURL（MP4 分段）。
  final bool isDash;

  /// DURL 流（非 DASH 时使用）。
  final List<Durl>? durls;

  /// 下载请求头。
  final Map<String, String> headers;

  DownloadMediaInfo({
    this.duration,
    this.videoStreams = const [],
    this.audioStreams = const [],
    this.quality,
    this.acceptQuality,
    this.supportFormats,
    this.isDash = true,
    this.durls,
    this.headers = const {
      'Referer': 'https://www.bilibili.com/',
      'User-Agent': 'Bilibili Freedoooooom/MarkII',
    },
  });

  factory DownloadMediaInfo.fromPlayUrl(PlayUrlModel model) {
    final dash = model.dash;
    if (dash != null) {
      return DownloadMediaInfo(
        duration: dash.duration,
        videoStreams: (dash.video ?? [])
            .map((v) => DownloadVideoStream.fromDashVideo(v))
            .toList(),
        audioStreams: (dash.audio ?? [])
            .map((a) => DownloadAudioStream.fromDashAudio(a))
            .toList(),
        quality: model.quality,
        acceptQuality: model.acceptQuality,
        supportFormats: model.supportFormats,
        isDash: true,
      );
    } else {
      return DownloadMediaInfo(
        quality: model.quality,
        acceptQuality: model.acceptQuality,
        supportFormats: model.supportFormats,
        isDash: false,
        durls: model.durl,
      );
    }
  }
}

/// DASH 视频流。
class DownloadVideoStream {
  final int id;
  final int codecid;
  final int? bandwidth;
  final int? width;
  final int? height;
  final String? frameRate;
  final int quality;
  final String? codecs;
  final List<String> urls;

  DownloadVideoStream({
    required this.id,
    required this.codecid,
    this.bandwidth,
    this.width,
    this.height,
    this.frameRate,
    required this.quality,
    this.codecs,
    this.urls = const [],
  });

  factory DownloadVideoStream.fromDashVideo(DashVideo v) {
    return DownloadVideoStream(
      id: v.id ?? 0,
      codecid: v.codecid ?? 0,
      bandwidth: v.bandwidth,
      width: v.width,
      height: v.height,
      frameRate: v.frameRate,
      quality: v.id ?? 0,
      codecs: v.codecs,
      urls: v.playUrls,
    );
  }
}

/// DASH 音频流。
class DownloadAudioStream {
  final int id;
  final int codecid;
  final int? bandwidth;
  final String? frameRate;
  final int? width;
  final int? height;
  final List<String> urls;

  DownloadAudioStream({
    required this.id,
    required this.codecid,
    this.bandwidth,
    this.frameRate,
    this.width,
    this.height,
    this.urls = const [],
  });

  factory DownloadAudioStream.fromDashAudio(DashAudio a) {
    return DownloadAudioStream(
      id: a.id ?? 0,
      codecid: a.codecid ?? 0,
      bandwidth: a.bandwidth,
      frameRate: a.frameRate,
      width: a.width,
      height: a.height,
      urls: a.playUrls,
    );
  }
}
