import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/core/storage/storage_key.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/models/video/play_info.dart';

/// 字幕 AI 偏好策略（对应 SettingBoxKey.subtitlePreferenceV2）。
enum SubtitlePreference {
  /// 关闭字幕。
  off(0),
  /// 显示所有字幕（含 AI）。
  on(1),
  /// 仅显示非 AI 字幕。
  withoutAi(2),
  /// 优先非 AI，无则用 AI。
  auto(3);

  final int value;
  const SubtitlePreference(this.value);

  static SubtitlePreference fromValue(int? value) {
    return SubtitlePreference.values.firstWhere(
      (e) => e.value == value,
      orElse: () => SubtitlePreference.auto,
    );
  }

  static SubtitlePreference get current => fromValue(
        GStorage.setting.get(SettingBoxKey.subtitlePreferenceV2,
            defaultValue: 3) as int?,
      );
}

/// 字幕控制器（Phase 4.4）。
///
/// 负责字幕的加载、解析、缓存、当前行查找。
///
/// B站字幕格式为自定义 JSON：
/// ```json
/// {"body": [{"from": 0.0, "to": 3.0, "content": "字幕内容"}]}
/// ```
/// 同时兼容标准 WebVTT 和 SRT 格式（用于本地字幕加载）。
class SubtitleController extends ChangeNotifier {
  SubtitleController({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// 可选字幕列表（来自 playInfo）。
  List<SubtitleItem> _available = const [];
  List<SubtitleItem> get available => _available;

  /// 当前选中的字幕（null = 未选中）。
  SubtitleItem? _current;
  SubtitleItem? get current => _current;

  /// 已加载的字幕行（按时间排序）。
  List<SubtitleCue> _cues = const [];
  List<SubtitleCue> get cues => _cues;

  /// 是否已加载。
  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// 字幕 URL → 已解析 cue 列表 的内存缓存。
  static final Map<String, List<SubtitleCue>> _cache = {};

  /// 设置可用字幕列表（来自 playInfo 接口）。
  /// 根据 [SubtitlePreference] 和用户开关状态自动选择默认字幕。
  void setAvailable(List<SubtitleItem> subtitles) {
    _available = subtitles;
    // 如果用户手动关闭了字幕，保持关闭状态
    if (!Pref.subtitleEnabled) {
      _current = null;
    } else {
      _current = _selectByPreference(subtitles);
    }
    _cues = const [];
    _loaded = false;
    notifyListeners();
  }

  /// 根据 AI 偏好从字幕列表中选择默认字幕。
  SubtitleItem? _selectByPreference(List<SubtitleItem> subtitles) {
    if (subtitles.isEmpty) return null;
    final pref = SubtitlePreference.current;
    if (pref == SubtitlePreference.off) return null;

    // 优先中文字幕。
    final zh = subtitles.where((s) => s.lan.startsWith('zh')).toList();
    final pool = zh.isNotEmpty ? zh : subtitles;

    switch (pref) {
      case SubtitlePreference.off:
        return null;
      case SubtitlePreference.on:
        // 所有字幕都可用，优先非 AI 的中文。
        final nonAi = pool.where((s) => !s.isAi).toList();
        return nonAi.isNotEmpty ? nonAi.first : pool.first;
      case SubtitlePreference.withoutAi:
        // 仅非 AI。
        final nonAi = pool.where((s) => !s.isAi).toList();
        return nonAi.isNotEmpty ? nonAi.first : null;
      case SubtitlePreference.auto:
        // 优先非 AI，无则用 AI。
        final nonAi = pool.where((s) => !s.isAi).toList();
        return nonAi.isNotEmpty ? nonAi.first : pool.first;
    }
  }

  /// 切换到指定字幕（null = 关闭字幕）。
  /// 会同步更新用户开关状态到持久化存储。
  Future<void> select(SubtitleItem? item) async {
    _current = item;
    _cues = const [];
    _loaded = false;
    // 记忆用户的手动开关状态
    Pref.subtitleEnabled = item != null;
    notifyListeners();
    if (item != null) {
      await loadSubtitle(item);
    }
  }

  /// 加载字幕内容（从 URL 拉取 + 解析 + 缓存）。
  Future<void> loadSubtitle(SubtitleItem item) async {
    final url = item.fullUrl;
    if (url.isEmpty) return;
    // 先查内存缓存。
    final cached = _cache[url];
    if (cached != null) {
      _cues = cached;
      _loaded = true;
      notifyListeners();
      return;
    }
    try {
      final res = await _dio.get<dynamic>(url);
      final data = res.data;
      List<SubtitleCue> parsed;
      if (data is String) {
        parsed = _parseContent(data);
      } else if (data is Map) {
        parsed = _parseBiliJson(data.cast<String, dynamic>());
      } else {
        parsed = const [];
      }
      _cache[url] = parsed;
      _cues = parsed;
      _loaded = true;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('Subtitle load failed: $e');
    }
  }

  /// 加载本地字幕文件内容（支持 .vtt / .srt / .json / .ass）。
  Future<void> loadLocalContent(String content, String filename) async {
    final ext = filename.split('.').last.toLowerCase();
    List<SubtitleCue> parsed;
    switch (ext) {
      case 'json':
        try {
          final json = jsonDecode(content) as Map<String, dynamic>;
          parsed = _parseBiliJson(json);
        } catch (_) {
          parsed = _parseContent(content);
        }
        break;
      case 'ass':
        // ASS 格式暂不支持完整解析，降级为按行分割。
        parsed = _parseSrt(content);
        break;
      default:
        parsed = _parseContent(content);
    }
    _cues = parsed;
    _loaded = true;
    _current = SubtitleItem(
      id: -1,
      lan: 'local',
      lanDoc: filename,
      subtitleUrl: '',
      aiType: 0,
    );
    notifyListeners();
  }

  /// 查找当前播放位置对应的字幕行。
  SubtitleCue? currentCue(Duration position) {
    if (!_loaded || _cues.isEmpty) return null;
    for (final cue in _cues) {
      if (cue.contains(position)) return cue;
    }
    return null;
  }

  /// 导出字幕为指定格式。
  /// [format]: 'vtt' / 'srt' / 'json'
  String export(String format) {
    switch (format.toLowerCase()) {
      case 'vtt':
        return _exportVtt();
      case 'srt':
        return _exportSrt();
      case 'json':
        return _exportJson();
      default:
        return _exportVtt();
    }
  }

  /// 清空状态（切换视频时调用）。
  void clear() {
    _available = const [];
    _current = null;
    _cues = const [];
    _loaded = false;
    notifyListeners();
  }

  // ── 解析 ──

  /// 解析 B站自定义 JSON 字幕格式。
  List<SubtitleCue> _parseBiliJson(Map<String, dynamic> json) {
    final body = json['body'];
    if (body is! List) return const [];
    return body
        .whereType<Map>()
        .map((e) {
          final from = _asDouble(e['from']) ?? 0;
          final to = _asDouble(e['to']) ?? 0;
          final content = e['content']?.toString() ?? '';
          return SubtitleCue(
            start: Duration(milliseconds: (from * 1000).round()),
            end: Duration(milliseconds: (to * 1000).round()),
            text: content,
          );
        })
        .where((c) => c.end > c.start)
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
  }

  /// 自动识别格式（VTT / SRT）并解析。
  List<SubtitleCue> _parseContent(String content) {
    final trimmed = content.trim();
    if (trimmed.startsWith('WEBVTT')) {
      return _parseVtt(trimmed);
    }
    return _parseSrt(trimmed);
  }

  /// 解析标准 WebVTT 格式。
  List<SubtitleCue> _parseVtt(String content) {
    final cues = <SubtitleCue>[];
    final blocks = content
        .replaceAll('\r\n', '\n')
        .split('\n\n')
        .where((b) => b.trim().isNotEmpty);

    for (final block in blocks) {
      final lines = block.split('\n');
      // 查找时间行（格式：00:00:00.000 --> 00:00:03.000）
      int timeLineIdx = -1;
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].contains('-->')) {
          timeLineIdx = i;
          break;
        }
      }
      if (timeLineIdx < 0) continue;

      final timeParts = lines[timeLineIdx].split('-->');
      if (timeParts.length != 2) continue;
      final start = _parseVttTime(timeParts[0].trim());
      final end = _parseVttTime(timeParts[1].trim().split(' ').first);
      if (start == null || end == null) continue;

      final text = lines.sublist(timeLineIdx + 1).join('\n').trim();
      if (text.isNotEmpty) {
        cues.add(SubtitleCue(start: start, end: end, text: text));
      }
    }
    return cues..sort((a, b) => a.start.compareTo(b.start));
  }

  /// 解析 SRT 格式。
  List<SubtitleCue> _parseSrt(String content) {
    final cues = <SubtitleCue>[];
    final blocks = content
        .replaceAll('\r\n', '\n')
        .split('\n\n')
        .where((b) => b.trim().isNotEmpty);

    for (final block in blocks) {
      final lines = block.split('\n').where((l) => l.trim().isNotEmpty).toList();
      if (lines.length < 2) continue;

      // 第一行可能是序号，第二行是时间，也可能第一行就是时间。
      int timeLineIdx = 0;
      if (!lines[0].contains('-->')) {
        timeLineIdx = 1;
      }
      if (timeLineIdx >= lines.length) continue;
      if (!lines[timeLineIdx].contains('-->')) continue;

      final timeParts = lines[timeLineIdx].split('-->');
      if (timeParts.length != 2) continue;
      final start = _parseSrtTime(timeParts[0].trim());
      final end = _parseSrtTime(timeParts[1].trim().split(' ').first);
      if (start == null || end == null) continue;

      final text = lines.sublist(timeLineIdx + 1).join('\n').trim();
      if (text.isNotEmpty) {
        cues.add(SubtitleCue(start: start, end: end, text: text));
      }
    }
    return cues..sort((a, b) => a.start.compareTo(b.start));
  }

  Duration? _parseVttTime(String s) {
    // 格式：HH:MM:SS.mmm 或 MM:SS.mmm
    final parts = s.split(':');
    if (parts.length == 3) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      final secParts = parts[2].split('.');
      final sec = int.tryParse(secParts[0]) ?? 0;
      final ms = secParts.length > 1 ? int.tryParse(secParts[1]) ?? 0 : 0;
      return Duration(hours: h, minutes: m, seconds: sec, milliseconds: ms);
    } else if (parts.length == 2) {
      final m = int.tryParse(parts[0]) ?? 0;
      final secParts = parts[1].split('.');
      final sec = int.tryParse(secParts[0]) ?? 0;
      final ms = secParts.length > 1 ? int.tryParse(secParts[1]) ?? 0 : 0;
      return Duration(minutes: m, seconds: sec, milliseconds: ms);
    }
    return null;
  }

  Duration? _parseSrtTime(String s) {
    // 格式：HH:MM:SS,mmm（逗号分隔毫秒）
    final s2 = s.replaceAll(',', '.');
    return _parseVttTime(s2);
  }

  // ── 导出 ──

  String _exportVtt() {
    final sb = StringBuffer('WEBVTT\n\n');
    for (final cue in _cues) {
      sb.write(cue.toVtt());
      sb.write('\n');
    }
    return sb.toString();
  }

  String _exportSrt() {
    final sb = StringBuffer();
    for (int i = 0; i < _cues.length; i++) {
      sb.write(_cues[i].toSrt(i));
      sb.write('\n');
    }
    return sb.toString();
  }

  String _exportJson() {
    final body = _cues.map((c) {
      return {
        'from': c.start.inMilliseconds / 1000.0,
        'to': c.end.inMilliseconds / 1000.0,
        'content': c.text,
      };
    }).toList();
    return const JsonEncoder.withIndent('  ').convert({'body': body});
  }
}

double? _asDouble(Object? value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
