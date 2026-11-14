import 'package:flutter_test/flutter_test.dart';

import 'package:winwin/plugin/api/app_plugin.dart';
import 'package:winwin/plugin/api/builtin_plugin_registry.dart';
import 'package:winwin/plugin/api/plugin_capability.dart';

import 'fake_plugin_state_store.dart';

class _TestPlugin extends BuiltinPlugin {
  _TestPlugin({
    required this.id,
    this.defaultEnabled = false,
    this.failOnEnable = false,
  });

  @override
  final String id;

  final bool failOnEnable;

  @override
  final bool defaultEnabled;

  final List<String> lifecycle = [];

  @override
  String get name => id;

  @override
  String get description => 'test';

  @override
  String get version => '1.0.0';

  @override
  Set<PluginCapability> get capabilities => const {};

  @override
  Future<void> onEnable() async {
    if (failOnEnable) throw StateError('enable failed');
    lifecycle.add('enable');
  }

  @override
  Future<void> onDisable() async {
    lifecycle.add('disable');
  }
}

void main() {
  late FakePluginStateStore store;
  late BuiltinPluginRegistry registry;
  final failures = <String>[];

  setUp(() {
    store = FakePluginStateStore();
    failures.clear();
    registry = BuiltinPluginRegistry(
      store: store,
      onFailure: (pluginId, error, stackTrace) => failures.add(pluginId),
    );
  });

  test('默认关闭的插件注册时不调用生命周期', () async {
    final plugin = _TestPlugin(id: 'a');
    await registry.register(plugin);

    expect(registry.plugins.value.single.enabled, isFalse);
    expect(plugin.lifecycle, isEmpty);
    expect(store.enabled['a'], isNull);
  });

  test('默认启用的插件注册时执行 onEnable 并持久化', () async {
    final plugin = _TestPlugin(id: 'a', defaultEnabled: true);
    await registry.register(plugin);

    expect(registry.plugins.value.single.enabled, isTrue);
    expect(plugin.lifecycle, ['enable']);
  });

  test('启用/禁用只执行一次生命周期', () async {
    final plugin = _TestPlugin(id: 'a');
    await registry.register(plugin);

    expect(await registry.setEnabled('a', true), isTrue);
    expect(await registry.setEnabled('a', true), isTrue);
    expect(plugin.lifecycle, ['enable']);
    expect(store.enabled['a'], isTrue);

    expect(await registry.setEnabled('a', false), isTrue);
    expect(plugin.lifecycle, ['enable', 'disable']);
    expect(store.enabled['a'], isFalse);
  });

  test('onEnable 失败时回滚为禁用并上报', () async {
    final plugin = _TestPlugin(
      id: 'a',
      defaultEnabled: true,
      failOnEnable: true,
    );
    await registry.register(plugin);

    expect(registry.plugins.value.single.enabled, isFalse);
    expect(plugin.lifecycle, ['disable']);
    expect(failures, ['a']);
  });

  test('未注册插件的启停请求在注册时生效', () async {
    expect(await registry.setEnabled('a', true), isTrue);
    expect(store.enabled['a'], isTrue);

    final plugin = _TestPlugin(id: 'a');
    await registry.register(plugin);

    expect(registry.plugins.value.single.enabled, isTrue);
    expect(plugin.lifecycle, ['enable']);
  });

  test('awaitPluginReady 在注册完成后返回', () async {
    final plugin = _TestPlugin(id: 'a');
    final ready = registry.awaitPluginReady('a');
    await registry.register(plugin);
    await ready;
    expect(registry.infoOf('a'), isNotNull);
  });

  test('重复注册同一 id 被忽略', () async {
    await registry.register(_TestPlugin(id: 'a'));
    await registry.register(_TestPlugin(id: 'a'));
    expect(registry.plugins.value.length, 1);
  });
}
