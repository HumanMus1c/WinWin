import 'package:flutter_test/flutter_test.dart';

import 'package:winwin/plugin/rules/json_rule_plugin.dart';

void main() {
  group('JsonRulePlugin 解析', () {
    test('旧格式规则', () {
      final plugin = JsonRulePlugin.fromJson({
        'id': 'demo_plugin',
        'name': '演示插件',
        'description': '描述',
        'version': '1.2.0',
        'author': 'tester',
        'type': 'feed',
        'rules': [
          {
            'field': 'title',
            'op': 'contains',
            'value': '广告',
            'action': 'hide',
          },
        ],
      });

      expect(plugin.id, 'demo_plugin');
      expect(plugin.name, '演示插件');
      expect(plugin.isFeed, isTrue);
      expect(plugin.rules.length, 1);
      expect(plugin.rules.first.condition, isA<SimpleRuleCondition>());
    });

    test('复合条件与高亮样式', () {
      final plugin = JsonRulePlugin.fromJson({
        'id': 'danmaku_demo',
        'name': '弹幕演示',
        'type': 'danmaku',
        'rules': [
          {
            'condition': {
              'or': [
                {'field': 'content', 'op': 'contains', 'value': '剧透'},
                {'field': 'content', 'op': 'regex', 'value': '^[哈]{5,}\$'},
              ],
            },
            'action': 'highlight',
            'style': {'color': '#FFD700', 'bold': true, 'scale': 1.2},
          },
        ],
      });

      expect(plugin.isDanmaku, isTrue);
      final rule = plugin.rules.first;
      expect(rule.condition, isA<OrRuleCondition>());
      expect(rule.style?.argb, 0xFFFFD700);
      expect(rule.style?.bold, isTrue);
      expect(rule.style?.scale, 1.2);
    });

    test('toJson 往返保持字段', () {
      final plugin = JsonRulePlugin.fromJson({
        'id': 'roundtrip',
        'name': '往返',
        'type': 'feed',
        'rules': [
          {
            'condition': {
              'and': [
                {'field': 'duration', 'op': 'lt', 'value': 60},
                {'field': 'title', 'op': 'contains', 'value': '搬运'},
              ],
            },
            'action': 'hide',
          },
        ],
      });
      final again = JsonRulePlugin.fromJson(plugin.toJson());
      expect(again.id, plugin.id);
      expect(again.rules.length, 1);
      expect(again.rules.first.condition, isA<AndRuleCondition>());
    });

    test('非法 id / type / rules 抛出带原因的异常', () {
      expect(
        () => JsonRulePlugin.fromJson({
          'id': '含中文',
          'name': 'x',
          'type': 'feed',
          'rules': [
            {'field': 'title', 'op': 'eq', 'value': 'x', 'action': 'hide'},
          ],
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => JsonRulePlugin.fromJson({
          'id': 'valid_id',
          'name': 'x',
          'type': 'unknown',
          'rules': [
            {'field': 'title', 'op': 'eq', 'value': 'x', 'action': 'hide'},
          ],
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => JsonRulePlugin.fromJson({
          'id': 'valid_id',
          'name': 'x',
          'type': 'feed',
          'rules': const [],
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('非法正则与非法颜色在导入时被拒绝', () {
      expect(
        () => JsonRulePlugin.fromJson({
          'id': 'bad_regex',
          'name': 'x',
          'type': 'feed',
          'rules': [
            {'field': 'title', 'op': 'regex', 'value': '[', 'action': 'hide'},
          ],
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => JsonRulePlugin.fromJson({
          'id': 'bad_color',
          'name': 'x',
          'type': 'danmaku',
          'rules': [
            {
              'field': 'content',
              'op': 'contains',
              'value': 'x',
              'action': 'highlight',
              'style': {'color': 'red'},
            },
          ],
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
