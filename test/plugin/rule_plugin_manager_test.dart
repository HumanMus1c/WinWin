import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:winwin/models/video/rec_video_item.dart';
import 'package:winwin/plugin/canvas_danmaku/models/danmaku_content_item.dart';
import 'package:winwin/plugin/rules/rule_plugin_manager.dart';

import 'fake_plugin_state_store.dart';

RcmdVideoItemModel _video({required String title, required int duration}) {
  return RcmdVideoItemModel.fromJson({
    'title': title,
    'duration': duration,
    'bvid': 'BV1xx',
    'goto': 'av',
    'owner': {'mid': 1, 'name': 'UP'},
    'stat': {'view': 10000, 'like': 500},
  });
}

String _feedJson() => jsonEncode({
      'id': 'rule_short',
      'name': '短视频过滤',
      'type': 'feed',
      'rules': [
        {'field': 'duration', 'op': 'lt', 'value': 60, 'action': 'hide'},
      ],
    });

String _danmakuJson() => jsonEncode({
      'id': 'rule_danmaku',
      'name': '弹幕净化',
      'type': 'danmaku',
      'rules': [
        {
          'field': 'content',
          'op': 'regex',
          'value': '^[哈]{5,}\$',
          'action': 'hide',
        },
        {
          'field': 'content',
          'op': 'startsWith',
          'value': '【',
          'action': 'highlight',
          'style': {'color': '#FFD700', 'bold': true},
        },
      ],
    });

void main() {
  late Directory tempDir;
  late FakePluginStateStore store;
  late RulePluginManager manager;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('winwin_plugin_test_');
    store = FakePluginStateStore();
    manager = RulePluginManager(
      store: store,
      directoryProvider: () async => tempDir,
    );
    await manager.load();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('安装后落盘、启用并参与过滤', () async {
    final plugin = manager.previewText(_feedJson());
    await manager.install(plugin, source: 'test');

    expect(manager.plugins.value.single.plugin.id, 'rule_short');
    expect(manager.plugins.value.single.enabled, isTrue);
    expect(store.ruleEnabled['rule_short'], isTrue);
    expect(
      await File('${tempDir.path}/rule_short.json').exists(),
      isTrue,
    );

    final filtered = manager.filterFeed([
      _video(title: '短片', duration: 30),
      _video(title: '长片', duration: 120),
    ]);
    expect(filtered.length, 1);
    expect(filtered.single.title, '长片');
    expect(manager.statsOf('rule_short'), 1);
  });

  test('停用后不过滤，重新加载保持状态', () async {
    await manager.install(manager.previewText(_feedJson()));

    await manager.setEnabled('rule_short', false);
    expect(store.ruleEnabled['rule_short'], isFalse);
    expect(
      manager
          .filterFeed([
            _video(title: '短片', duration: 30),
          ])
          .length,
      1,
    );

    final reloaded = RulePluginManager(
      store: store,
      directoryProvider: () async => tempDir,
    );
    await reloaded.load();
    expect(reloaded.plugins.value.single.plugin.id, 'rule_short');
    expect(reloaded.plugins.value.single.enabled, isFalse);
  });

  test('删除插件会清理文件与状态', () async {
    await manager.install(manager.previewText(_feedJson()));
    await manager.remove('rule_short');

    expect(manager.plugins.value, isEmpty);
    expect(store.ruleEnabled.containsKey('rule_short'), isFalse);
    expect(
      await File('${tempDir.path}/rule_short.json').exists(),
      isFalse,
    );
  });

  test('弹幕规则隐藏与高亮', () async {
    await manager.install(manager.previewText(_danmakuJson()));

    final hidden = DanmakuContentItem<Object?>('哈哈哈哈哈哈');
    expect(manager.shouldHideDanmaku(hidden), isTrue);

    final highlighted = DanmakuContentItem<Object?>('【翻译】Hello');
    expect(manager.shouldHideDanmaku(highlighted), isFalse);
    final style = manager.danmakuHighlight(highlighted);
    expect(style, isNotNull);
    expect(style!.argb, 0xFFFFD700);
    expect(style.bold, isTrue);
  });

  test('非法 JSON / 超大内容被拒绝', () {
    expect(
      () => manager.previewText('{not json'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => manager.previewText(''),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => manager.previewText('{"id":"x"}'),
      throwsA(isA<FormatException>()),
    );
  });

  test('重置统计', () async {
    await manager.install(manager.previewText(_feedJson()));
    manager.filterFeed([
      _video(title: '短片', duration: 30),
    ]);
    expect(manager.statsOf('rule_short'), 1);

    await manager.resetStats('rule_short');
    expect(manager.statsOf('rule_short'), 0);
    expect(store.statsByPlugin['rule_short'], 0);
  });
}
