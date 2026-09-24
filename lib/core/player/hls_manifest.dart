import 'dart:io';

import 'package:winwin/services/logger.dart';

/// 合成 HLS 主清单：把 B 站 DASH 的视频/音频两条 CDN URL 合成一个「单一源」，
/// 交给 FFmpeg 的 hls 解复用器后音视频落在**同一个 AVFormatContext**里
/// （一条 timeline、一次 seek 同时作用于两轨），规避 mdk 外挂音轨不跟随 seek
/// 的架构问题（上游 fvp issue #355：分离外挂音轨 ≠ 内嵌音轨）。
///
/// 为什么用 hls 而不是 dash：mdk 自带的 `ffmpeg-9.dll` 未编译 dash 解复用器
/// （缺 libxml2，实测 DLL 内无 "Dynamic Adaptive Streaming" 与 libxml 符号），
/// 而 hls 解复用器存在且不需要 libxml。
///
/// 清单形状（本地实测 ffmpeg 4.2 + 9.x 均支持）：
/// - 主清单：`EXT-X-MEDIA:TYPE=AUDIO` 声明音轨组 + `EXT-X-STREAM-INF` 指向视频变体；
/// - 变体清单：每个只含 1 个分段（整条 m4s），`EXTINF` = 全片时长。
///
/// 清单文件通过本地 `127.0.0.1` HTTP 服务暴露：Windows 绝对路径在 hls/dash
/// 解复用器的协议白名单下会被误判（实测 "No such file or directory"），
/// 改走 http 后相对 URI 解析、协议白名单、Referer 透传都与线上路径一致。
abstract final class HlsManifest {
  static HttpServer? _server;
  static String? _baseUrl;

  /// 写入三份清单并返回主清单的可播放 URL（失败返回 null）。
  static Future<String?> publish({
    required String name,
    required String videoUrl,
    required String audioUrl,
    required double durationSec,
    int? bandwidth,
    String? codecs,
  }) async {
    if (durationSec <= 0) return null;
    final runtime = await LoggerUtils.getRuntimeLogsPath();
    final dir = runtime.parent.path;
    final sec = durationSec.toStringAsFixed(3);
    final target = durationSec.ceil().clamp(1, 1 << 30);
    File('$dir/$name.vid.m3u8')
        .writeAsStringSync(_media(videoUrl, sec, target), flush: true);
    File('$dir/$name.aud.m3u8')
        .writeAsStringSync(_media(audioUrl, sec, target), flush: true);
    File('$dir/$name.m3u8').writeAsStringSync(
      _master('$name.vid.m3u8', '$name.aud.m3u8', bandwidth, codecs),
      flush: true,
    );
    final base = await _ensureServer(dir);
    if (base == null) return null;
    return '$base/$name.m3u8';
  }

  static String _master(
    String videoPlaylist,
    String audioPlaylist,
    int? bandwidth,
    String? codecs,
  ) {
    final bw = bandwidth ?? 2000000;
    return '#EXTM3U\n'
        '#EXT-X-VERSION:6\n'
        '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="audio",'
        'DEFAULT=YES,AUTOSELECT=YES,URI="$audioPlaylist"\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=$bw'
        '${codecs != null && codecs.isNotEmpty ? ',CODECS="$codecs"' : ''}'
        ',AUDIO="aud"\n'
        '$videoPlaylist\n';
  }

  static String _media(String url, String durationSec, int targetSec) {
    return '#EXTM3U\n'
        '#EXT-X-VERSION:6\n'
        '#EXT-X-TARGETDURATION:$targetSec\n'
        '#EXT-X-PLAYLIST-TYPE:VOD\n'
        '#EXTINF:$durationSec,\n'
        '$url\n'
        '#EXT-X-ENDLIST\n';
  }

  static Future<String?> _ensureServer(String dir) async {
    final existing = _baseUrl;
    if (_server != null && existing != null) return existing;
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _server = server;
      _baseUrl = 'http://127.0.0.1:${server.port}';
      server.listen((req) async {
        try {
          final seg = req.uri.pathSegments;
          final name = seg.isEmpty ? '' : seg.last;
          final f = File('$dir/$name');
          if (name.isEmpty || !f.existsSync()) {
            req.response.statusCode = HttpStatus.notFound;
          } else {
            req.response.headers.contentType =
                ContentType.parse('application/vnd.apple.mpegurl');
            req.response.add(f.readAsBytesSync());
          }
        } catch (_) {}
        try {
          await req.response.close();
        } catch (_) {}
      });
      return _baseUrl;
    } catch (_) {
      return null;
    }
  }
}
