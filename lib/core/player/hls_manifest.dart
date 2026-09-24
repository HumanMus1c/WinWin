import 'dart:io';
import 'dart:typed_data';

import 'package:winwin/services/logger.dart';

/// 合成 HLS 单一源清单（方案 A：按 sidx 分段；单段形态兜底）。
///
/// 背景（docs/播放器Seek音画同步-单源清单方案复盘-2026-09-24.md）：
/// mdk 的「主视频 + 外挂音轨」是两条独立播放图，seek 必然跑偏；必须把
/// 两条 CDN URL 合成**一个源**。mdk 自带 ffmpeg-9.dll 未编译 dash 解复用器
/// （缺 libxml2），因此走 hls 解复用器 + 合成主清单。
///
/// 分段粒度决定 seek 可靠性：把「整条 m4s」当作 1 个分段时，seek 只能靠内部
/// demuxer 做段内字节定位，实测约一半失败（demuxer 停在 seek 前位置）；
/// 因此本实现 Range 读取文件头解析 ISO BMFF 的 `moov`/`sidx`，按 sidx 引用
/// 切成真正的 HLS 分段（`EXT-X-MAP` 初始化段 + `EXT-X-BYTERANGE` 分段），
/// 让 seek 走 HLS 原生的「选段 + 段内定位」。
///
/// 清单文件经 `http://127.0.0.1:<随机端口>` 暴露给 mdk（Windows 绝对路径在
/// hls/dash 的解复用器协议白名单下会被误判，实测 "No such file or directory"）。
abstract final class HlsManifest {
  static HttpServer? _server;
  static String? _baseUrl;

  /// 解析 sidx 失败或结构异常时返回 null（调用方回退单段形态）。
  static Future<String?> publishSegmented({
    required String name,
    required String videoUrl,
    required String audioUrl,
    required Map<String, String> headers,
    required double durationSec,
    int? bandwidth,
    String? codecs,
    int maxHeadBytes = 4 << 20,
  }) async {
    final v = await _Sidx.parse(videoUrl, headers, maxHeadBytes);
    final a = await _Sidx.parse(audioUrl, headers, maxHeadBytes);
    if (v == null || a == null) return null;
    final expectedMs = (durationSec * 1000).round();
    // sidx 总时长应与 API 给出的时长接近（容差 20%），否则视作索引异常
    if (v.totalMs <= 0 || a.totalMs <= 0) return null;
    if (expectedMs > 0 &&
        (v.totalMs - expectedMs).abs() > expectedMs * 0.2 &&
        (a.totalMs - expectedMs).abs() > expectedMs * 0.2) {
      return null;
    }
    final runtime = await LoggerUtils.getRuntimeLogsPath();
    final dir = runtime.parent.path;
    File('$dir/$name.vid.m3u8')
        .writeAsStringSync(_variant(a: v, url: videoUrl), flush: true);
    File('$dir/$name.aud.m3u8')
        .writeAsStringSync(_variant(a: a, url: audioUrl), flush: true);
    File('$dir/$name.m3u8').writeAsStringSync(
      _master('$name.vid.m3u8', '$name.aud.m3u8', bandwidth, codecs),
      flush: true,
    );
    final base = await _ensureServer(dir);
    if (base == null) return null;
    return '$base/$name.m3u8';
  }

  /// 兜底：整条 m4s 当作 1 个分段（sidx 不可用时使用）。
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
        .writeAsStringSync(_singleSegment(videoUrl, sec, target), flush: true);
    File('$dir/$name.aud.m3u8')
        .writeAsStringSync(_singleSegment(audioUrl, sec, target), flush: true);
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

  static String _singleSegment(String url, String durationSec, int targetSec) {
    return '#EXTM3U\n'
        '#EXT-X-VERSION:6\n'
        '#EXT-X-TARGETDURATION:$targetSec\n'
        '#EXT-X-PLAYLIST-TYPE:VOD\n'
        '#EXTINF:$durationSec,\n'
        '$url\n'
        '#EXT-X-ENDLIST\n';
  }

  /// 按 sidx 引用生成分段变体清单（EXT-X-MAP + 逐段 EXT-X-BYTERANGE）。
  static String _variant({required _Sidx a, required String url}) {
    final b = StringBuffer()
      ..write('#EXTM3U\n')
      ..write('#EXT-X-VERSION:7\n')
      ..write('#EXT-X-TARGETDURATION:${a.targetDurationSec}\n')
      ..write('#EXT-X-MEDIA-SEQUENCE:0\n')
      ..write('#EXT-X-PLAYLIST-TYPE:VOD\n')
      ..write('#EXT-X-MAP:URI="$url",BYTERANGE="${a.initLength}@0"\n');
    for (final f in a.fragments) {
      b.write('#EXTINF:${(f.durationMs / 1000).toStringAsFixed(3)},\n');
      b.write('#EXT-X-BYTERANGE:${f.length}@${f.offset}\n');
      b.write('$url\n');
    }
    b.write('#EXT-X-ENDLIST\n');
    return b.toString();
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

/// sidx 解析结果：初始化段长度 + 分段（字节长度/偏移/时长）。
class _Sidx {
  _Sidx({
    required this.initLength,
    required this.fragments,
    required this.totalMs,
  });

  final int initLength;
  final List<_Frag> fragments;
  final int totalMs;

  int get targetDurationSec {
    var max = 0;
    for (final f in fragments) {
      final s = (f.durationMs / 1000).ceil();
      if (s > max) max = s;
    }
    return max <= 0 ? 1 : max;
  }

  static Future<_Sidx?> parse(
    String url,
    Map<String, String> headers,
    int maxHeadBytes,
  ) async {
    final data = await _fetchHead(url, headers, maxHeadBytes);
    if (data == null) return null;
    return _parse(data);
  }

  static Future<Uint8List?> _fetchHead(
    String url,
    Map<String, String> headers,
    int maxBytes,
  ) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      headers.forEach((k, v) => req.headers.set(k, v));
      req.headers.set('Range', 'bytes=0-${maxBytes - 1}');
      final res = await req.close();
      if (res.statusCode != 200 && res.statusCode != 206) return null;
      final out = BytesBuilder(copy: false);
      await for (final chunk in res) {
        out.add(chunk);
        if (out.length >= maxBytes) break;
      }
      return out.takeBytes();
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// 顶层 box 遍历：记录 moov 结束位置（init 段长度）并解析 sidx。
  static _Sidx? _parse(Uint8List d) {
    var off = 0;
    int? initLength;
    Uint8List? sidxPayload;
    int? sidxEnd;
    while (off + 8 <= d.length) {
      var size = _u32(d, off);
      final type = String.fromCharCodes(d, off + 4, off + 8);
      var header = 8;
      if (size == 1) {
        if (off + 16 > d.length) break;
        size = _u64(d, off + 8);
        header = 16;
      } else if (size == 0) {
        size = d.length - off;
      }
      if (size < header) break;
      final end = off + size;
      if (type == 'moov') {
        initLength = end;
      } else if (type == 'sidx') {
        if (end > d.length) break;
        sidxPayload = Uint8List.sublistView(d, off + header, end);
        sidxEnd = end;
      } else if (type == 'moof' || type == 'mdat') {
        break;
      }
      if (end > d.length) break;
      off = end;
    }
    if (initLength == null || sidxPayload == null || sidxEnd == null) {
      return null;
    }
    final parsed = _parseSidxPayload(sidxPayload);
    if (parsed == null) return null;
    final (timescale, firstOffset, refs) = parsed;
    final fragments = <_Frag>[];
    var offset = sidxEnd + firstOffset;
    var totalMs = 0;
    for (final r in refs) {
      if (r.$1 == 0) {
        final ms = timescale > 0
            ? (r.$3 * 1000 / timescale).round()
            : 0;
        fragments.add(_Frag(offset: offset, length: r.$2, durationMs: ms));
        totalMs += ms;
      }
      offset += r.$2;
    }
    if (fragments.isEmpty) return null;
    return _Sidx(
      initLength: initLength,
      fragments: fragments,
      totalMs: totalMs,
    );
  }

  /// sidx 负载：返回 (timescale, first_offset, [(refType, refSize, duration)])。
  static (int, int, List<(int, int, int)>)? _parseSidxPayload(Uint8List p) {
    if (p.length < 24) return null;
    final version = p[0];
    var i = 8; // version(1)+flags(3)+reference_ID(4)
    final timescale = _u32(p, i);
    i += 4;
    if (version == 0) {
      i += 4; // earliest_presentation_time
    } else {
      i += 8;
    }
    final firstOffset = version == 0 ? _u32(p, i) : _u64(p, i);
    i += version == 0 ? 4 : 8;
    if (i + 4 > p.length) return null;
    i += 2; // reserved
    final count = _u16(p, i);
    i += 2;
    final refs = <(int, int, int)>[];
    for (var n = 0; n < count; n++) {
      if (i + 12 > p.length) break;
      final w = _u32(p, i);
      final refType = (w >> 31) & 1;
      final refSize = w & 0x7FFFFFFF;
      final dur = _u32(p, i + 4);
      refs.add((refType, refSize, dur));
      i += 12;
    }
    if (refs.isEmpty) return null;
    return (timescale, firstOffset, refs);
  }

  static int _u16(Uint8List d, int i) => (d[i] << 8) | d[i + 1];

  static int _u32(Uint8List d, int i) =>
      (d[i] << 24) | (d[i + 1] << 16) | (d[i + 2] << 8) | d[i + 3];

  static int _u64(Uint8List d, int i) =>
      (_u32(d, i) << 32) | _u32(d, i + 4);
}

class _Frag {
  _Frag({
    required this.offset,
    required this.length,
    required this.durationMs,
  });

  final int offset;
  final int length;
  final int durationMs;
}
