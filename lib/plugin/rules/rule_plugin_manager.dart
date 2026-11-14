import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:winwin/core/log/app_logger.dart';
import 'package:winwin/models/video/rec_video_item.dart';
import 'package:winwin/plugin/api/plugin_manager.dart';
import 'package:winwin/plugin/api/plugin_state_store.dart';
import 'package:winwin/plugin/canvas_danmaku/models/danmaku_content_item.dart';

import 'json_rule_plugin.dart';
import 'rule_engine.dart';
import 'rule_target_adapter.dart';

/// 已安装的规则插件快照。
@immutable
class LoadedRulePlugin {
  const LoadedRulePlugin({
    required this.plugin,
    required this.enabled,
    required this.sourcePath,
  });

  final JsonRulePlugin plugin;
  final bool enabled;
  final String sourcePath;

  LoadedRulePlugin copyWith({bool? enabled, String? sourcePath}) =>
      LoadedRulePlugin(
        plugin: plugin,
        enabled: enabled ?? this.enabled,
        sourcePath: sourcePath ?? this.sourcePath,
      );
}

/// 内置可安装规则包（随安装包分发，安装时写入用户插件目录）。
class BundledRulePlugin {
  const BundledRulePlugin({
    required this.assetPath,
    required this.title,
    required this.subtitle,
  });

  final String assetPath;
  final String title;
  final String subtitle;
}

const List<BundledRulePlugin> bundledRulePlugins = [
  BundledRulePlugin(
    assetPath: 'assets/plugins/keyword_filter.json',
    title: '标题关键词过滤',
    subtitle: '过滤标题包含广告、恰饭、震惊体等关键词的视频',
  ),
  BundledRulePlugin(
    assetPath: 'assets/plugins/advanced_filter.json',
    title: '高级过滤器',
    subtitle: 'AND/OR 复合条件：时长、播放量、UP 主、标题正则组合',
  ),
  BundledRulePlugin(
    assetPath: 'assets/plugins/short_video_filter.json',
    title: '短视频过滤',
    subtitle: '隐藏时长小于 60 秒的视频',
  ),
  BundledRulePlugin(
    assetPath: 'assets/plugins/danmaku_cleaner.json',
    title: '弹幕净化',
    subtitle: '过滤刷屏弹幕，高亮同传/翻译弹幕',
  ),
];

/// 规则插件管理器（对应 BiliPai `JsonPluginManager`）。
///
/// 职责：
/// - 从用户目录加载已安装的 `*.json` 规则包；
/// - 本地 / 链接预览与安装、卸载、启停、命中统计；
/// - 向推荐流与弹幕渲染提供过滤 / 高亮结果。
class RulePluginManager {
  RulePluginManager({
    required this.store,
    Future<Directory> Function()? directoryProvider,
  }) : _directoryProvider = directoryProvider ?? _defaultDirectory;

  static RulePluginManager? _instance;

  static RulePluginManager? get maybeInstance => _instance;

  static RulePluginManager get instance {
    final current = _instance;
    if (current == null) {
      throw StateError('RulePluginManager.initialize() has not been called');
    }
    return current;
  }

  static Future<Directory> _defaultDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'plugins', 'rules'));
  }

  static Future<RulePluginManager> initialize({
    PluginStateStore? store,
    Future<Directory> Function()? directoryProvider,
  }) async {
    final current = _instance;
    if (current != null) return current;
    final manager = RulePluginManager(
      store: store ?? PluginManager.instance.store,
      directoryProvider: directoryProvider,
    );
    _instance = manager;
    await manager.load();
    AppLogger.w('RulePluginManager', 'initialized (${manager.plugins.value.length} plugins)');
    return manager;
  }

  final PluginStateStore store;
  final Future<Directory> Function() _directoryProvider;
  final RuleEngine engine = RuleEngine();

  final ValueNotifier<List<LoadedRulePlugin>> plugins =
      ValueNotifier<List<LoadedRulePlugin>>(const []);

  final ValueNotifier<Map<String, int>> stats =
      ValueNotifier<Map<String, int>>(const {});

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      validateStatus: (status) => status != null && status >= 200 && status < 300,
    ),
  );

  static const int _maxPackageBytes = 256 * 1024;

  final Map<String, int> _pendingStats = {};
  Timer? _statsFlushTimer;

  Future<Directory> _ensureDirectory() async {
    final dir = await _directoryProvider();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> load() async {
    final dir = await _ensureDirectory();
    final loaded = <LoadedRulePlugin>[];
    final statsMap = <String, int>{};
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.json')) {
        continue;
      }
      try {
        final text = await entity.readAsString();
        final plugin = JsonRulePlugin.fromJson(
          jsonDecode(_stripBom(text)) as Map<String, dynamic>,
        );
        final enabled = store.ruleEnabledOrNull(plugin.id) ?? true;
        loaded.add(
          LoadedRulePlugin(
            plugin: plugin,
            enabled: enabled,
            sourcePath: entity.path,
          ),
        );
        statsMap[plugin.id] = store.ruleStats(plugin.id);
      } catch (error) {
        AppLogger.w(
          'RulePluginManager',
          'skip invalid plugin ${p.basename(entity.path)}: $error',
        );
      }
    }
    loaded.sort((a, b) => a.plugin.name.compareTo(b.plugin.name));
    plugins.value = List<LoadedRulePlugin>.unmodifiable(loaded);
    stats.value = Map<String, int>.unmodifiable(statsMap);
  }

  /// 解析一段 JSON 文本（安装前预览）。
  JsonRulePlugin previewText(String text, {String source = ''}) {
    final trimmed = _stripBom(text).trim();
    if (trimmed.isEmpty) {
      throw const FormatException('插件内容为空');
    }
    if (utf8.encode(trimmed).length > _maxPackageBytes) {
      throw const FormatException('插件包超过 256 KB 上限');
    }
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map) {
      throw const FormatException('插件根节点必须是 JSON 对象');
    }
    return JsonRulePlugin.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<JsonRulePlugin> previewBytes(Uint8List bytes) async {
    if (bytes.length > _maxPackageBytes) {
      throw const FormatException('插件包超过 256 KB 上限');
    }
    return previewText(utf8.decode(bytes, allowMalformed: true));
  }

  /// 从 http/https 链接拉取并解析（不落盘）。
  Future<JsonRulePlugin> previewUrl(String rawUrl) async {
    final uri = _validateUrl(rawUrl);
    final response = await _dio.get<String>(
      uri.toString(),
      options: Options(responseType: ResponseType.plain),
    );
    final body = response.data;
    if (body == null || body.isEmpty) {
      throw const FormatException('链接内容为空');
    }
    return previewText(body, source: uri.toString());
  }

  /// 安装（或覆盖同 id 插件）。
  Future<void> install(
    JsonRulePlugin plugin, {
    String? source,
    bool enabled = true,
  }) async {
    final dir = await _ensureDirectory();
    final file = File(p.join(dir.path, '${plugin.id}.json'));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(plugin.toJson()),
      flush: true,
    );
    await store.setRuleEnabled(plugin.id, enabled);

    final next = List<LoadedRulePlugin>.of(plugins.value);
    final index = next.indexWhere((item) => item.plugin.id == plugin.id);
    final loaded = LoadedRulePlugin(
      plugin: plugin,
      enabled: enabled,
      sourcePath: file.path,
    );
    if (index >= 0) {
      next[index] = loaded;
    } else {
      next.add(loaded);
    }
    next.sort((a, b) => a.plugin.name.compareTo(b.plugin.name));
    plugins.value = List<LoadedRulePlugin>.unmodifiable(next);
    _setStat(plugin.id, stats.value[plugin.id] ?? 0);
    AppLogger.w(
      'RulePluginManager',
      'installed ${plugin.id} (source=${source ?? 'local'})',
    );
  }

  /// 安装随包分发的规则包。
  Future<JsonRulePlugin> installBundled(BundledRulePlugin bundled) async {
    final text = await rootBundle.loadString(bundled.assetPath);
    final plugin = previewText(text, source: bundled.assetPath);
    await install(plugin, source: bundled.assetPath);
    return plugin;
  }

  Future<void> remove(String pluginId) async {
    LoadedRulePlugin? current;
    for (final item in plugins.value) {
      if (item.plugin.id == pluginId) {
        current = item;
        break;
      }
    }
    if (current == null) return;
    try {
      final file = File(current.sourcePath);
      if (await file.exists()) await file.delete();
    } catch (error) {
      AppLogger.w('RulePluginManager', 'delete plugin file failed: $error');
    }
    await store.removeRuleState(pluginId);
    plugins.value = List<LoadedRulePlugin>.unmodifiable(
      plugins.value.where((item) => item.plugin.id != pluginId),
    );
    final nextStats = Map<String, int>.of(stats.value)..remove(pluginId);
    stats.value = Map<String, int>.unmodifiable(nextStats);
    AppLogger.w('RulePluginManager', 'removed $pluginId');
  }

  Future<bool> setEnabled(String pluginId, bool enabled) async {
    final index =
        plugins.value.indexWhere((item) => item.plugin.id == pluginId);
    if (index < 0) return false;
    try {
      await store.setRuleEnabled(pluginId, enabled);
    } catch (error, stackTrace) {
      AppLogger.e(
        'RulePluginManager',
        'persist enabled state failed: $pluginId',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
    final next = List<LoadedRulePlugin>.of(plugins.value);
    next[index] = next[index].copyWith(enabled: enabled);
    plugins.value = List<LoadedRulePlugin>.unmodifiable(next);
    AppLogger.w('RulePluginManager', 'setEnabled $pluginId=$enabled');
    return true;
  }

  bool isBundledInstalled(BundledRulePlugin bundled) {
    return plugins.value.any(
      (item) => bundled.assetPath.endsWith('${item.plugin.id}.json'),
    );
  }

  /// 推荐流过滤；返回新列表（无启用插件时原样返回）。
  List<BaseRcmdVideoItemModel> filterFeed(
    List<BaseRcmdVideoItemModel> items,
  ) {
    final enabled = plugins.value
        .where((item) => item.enabled && item.plugin.isFeed)
        .toList(growable: false);
    if (enabled.isEmpty || items.isEmpty) return items;

    final result = <BaseRcmdVideoItemModel>[];
    final removedBy = <String, int>{};
    for (final item in items) {
      String? hiddenBy;
      for (final loaded in enabled) {
        final hide = engine.shouldHide(
          loaded.plugin.rules,
          (field) => RuleTargetAdapter.video(item, field),
        );
        if (hide) {
          hiddenBy = loaded.plugin.name;
          _bumpStat(loaded.plugin.id);
          break;
        }
      }
      if (hiddenBy == null) {
        result.add(item);
      } else {
        removedBy[hiddenBy] = (removedBy[hiddenBy] ?? 0) + 1;
      }
    }

    final removed = items.length - result.length;
    if (removed > 0) {
      final names = removedBy.keys.join('、');
      PluginManager.maybeInstance?.emitHint(
        '已过滤 $removed 条推荐（$names）',
        cooldown: const Duration(seconds: 10),
      );
    }
    return result;
  }

  bool shouldHideDanmaku(DanmakuContentItem<Object?> item) {
    final enabled = plugins.value
        .where((loaded) => loaded.enabled && loaded.plugin.isDanmaku)
        .toList(growable: false);
    for (final loaded in enabled) {
      final hide = engine.shouldHide(
        loaded.plugin.rules,
        (field) => RuleTargetAdapter.danmaku(item, field),
      );
      if (hide) {
        _bumpStat(loaded.plugin.id);
        return true;
      }
    }
    return false;
  }

  DanmakuHighlightStyle? danmakuHighlight(DanmakuContentItem<Object?> item) {
    final enabled = plugins.value
        .where((loaded) => loaded.enabled && loaded.plugin.isDanmaku)
        .toList(growable: false);
    for (final loaded in enabled) {
      final style = engine.highlightStyle(
        loaded.plugin.rules,
        (field) => RuleTargetAdapter.danmaku(item, field),
      );
      if (style != null) {
        _bumpStat(loaded.plugin.id);
        return style;
      }
    }
    return null;
  }

  int statsOf(String pluginId) => stats.value[pluginId] ?? 0;

  Future<void> resetStats([String? pluginId]) async {
    final next = Map<String, int>.of(stats.value);
    if (pluginId == null) {
      next.clear();
      for (final loaded in plugins.value) {
        await store.setRuleStats(loaded.plugin.id, 0);
      }
    } else {
      next[pluginId] = 0;
      await store.setRuleStats(pluginId, 0);
    }
    stats.value = Map<String, int>.unmodifiable(next);
  }

  void _bumpStat(String pluginId) {
    final current = stats.value[pluginId] ?? 0;
    final next = Map<String, int>.of(stats.value)..[pluginId] = current + 1;
    stats.value = Map<String, int>.unmodifiable(next);
    _pendingStats[pluginId] = current + 1;
    _statsFlushTimer ??= Timer(const Duration(seconds: 2), _flushStats);
  }

  void _flushStats() {
    _statsFlushTimer?.cancel();
    _statsFlushTimer = null;
    if (_pendingStats.isEmpty) return;
    final pending = Map<String, int>.of(_pendingStats);
    _pendingStats.clear();
    for (final entry in pending.entries) {
      unawaited(store.setRuleStats(entry.key, entry.value));
    }
  }

  void _setStat(String pluginId, int value) {
    final next = Map<String, int>.of(stats.value)..[pluginId] = value;
    stats.value = Map<String, int>.unmodifiable(next);
  }

  Uri _validateUrl(String rawUrl) {
    final normalized = rawUrl.trim();
    if (normalized.isEmpty) throw const FormatException('请输入链接地址');
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw const FormatException('请输入有效的 http/https 地址');
    }
    return uri;
  }

  static String _stripBom(String text) {
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
      return text.substring(1);
    }
    return text;
  }
}
