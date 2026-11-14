import 'package:flutter_test/flutter_test.dart';

import 'package:winwin/plugin/rules/json_rule_plugin.dart';
import 'package:winwin/plugin/rules/rule_engine.dart';

JsonRule _rule(RuleCondition condition, {String action = 'hide'}) =>
    JsonRule(condition: condition, action: action);

void main() {
  group('RuleEngine 基础操作符', () {
    final engine = RuleEngine();

    bool evaluate(SimpleRuleCondition condition, Map<String, Object?> fields) =>
        engine.evaluate(condition, (field) => fields[field]);

    test('eq / ne 支持字符串与数字', () {
      expect(
        evaluate(
          const SimpleRuleCondition(field: 'title', op: 'eq', value: '广告'),
          {'title': '广告'},
        ),
        isTrue,
      );
      expect(
        evaluate(
          const SimpleRuleCondition(field: 'duration', op: 'eq', value: 60),
          {'duration': 60},
        ),
        isTrue,
      );
      expect(
        evaluate(
          const SimpleRuleCondition(field: 'title', op: 'ne', value: '广告'),
          {'title': '广告'},
        ),
        isFalse,
      );
    });

    test('数值比较', () {
      const fields = {'duration': 30, 'view': 500};
      expect(
        evaluate(
          const SimpleRuleCondition(field: 'duration', op: 'lt', value: 60),
          fields,
        ),
        isTrue,
      );
      expect(
        evaluate(
          const SimpleRuleCondition(field: 'view', op: 'ge', value: 500),
          fields,
        ),
        isTrue,
      );
      expect(
        evaluate(
          const SimpleRuleCondition(field: 'view', op: 'gt', value: 500),
          fields,
        ),
        isFalse,
      );
    });

    test('contains / startsWith / endsWith 大小写不敏感', () {
      const fields = {'title': 'Bilibili 广告推广'};
      expect(
        evaluate(
          const SimpleRuleCondition(field: 'title', op: 'contains', value: '广告'),
          fields,
        ),
        isTrue,
      );
      expect(
        evaluate(
          const SimpleRuleCondition(
            field: 'title',
            op: 'startsWith',
            value: 'bilibili',
          ),
          fields,
        ),
        isTrue,
      );
      expect(
        evaluate(
          const SimpleRuleCondition(field: 'title', op: 'endsWith', value: '推广'),
          fields,
        ),
        isTrue,
      );
    });

    test('regex 与 in', () {
      expect(
        evaluate(
          const SimpleRuleCondition(
            field: 'title',
            op: 'regex',
            value: '震惊.*必看',
          ),
          {'title': '震惊！这十个技巧必看'},
        ),
        isTrue,
      );
      expect(
        evaluate(
          const SimpleRuleCondition(
            field: 'goto',
            op: 'in',
            value: ['bangumi', 'picture'],
          ),
          {'goto': 'bangumi'},
        ),
        isTrue,
      );
    });

    test('字段缺失或未知操作符返回 false', () {
      expect(
        evaluate(
          const SimpleRuleCondition(field: 'missing', op: 'eq', value: 1),
          const {},
        ),
        isFalse,
      );
      expect(
        evaluate(
          const SimpleRuleCondition(field: 'title', op: 'unknown', value: 'x'),
          {'title': 'x'},
        ),
        isFalse,
      );
    });
  });

  group('RuleEngine 复合条件与动作', () {
    final engine = RuleEngine();

    test('AND 全部满足才命中', () {
      const condition = AndRuleCondition([
        SimpleRuleCondition(field: 'duration', op: 'lt', value: 60),
        SimpleRuleCondition(field: 'title', op: 'contains', value: '搬运转载'),
      ]);
      expect(
        engine.shouldHide(
          [_rule(condition)],
          (field) => switch (field) {
            'duration' => 30,
            'title' => '搬运转载测试',
            _ => null,
          },
        ),
        isTrue,
      );
      expect(
        engine.shouldHide(
          [_rule(condition)],
          (field) => switch (field) {
            'duration' => 120,
            'title' => '搬运转载测试',
            _ => null,
          },
        ),
        isFalse,
      );
    });

    test('OR 任一满足即命中', () {
      const condition = OrRuleCondition([
        SimpleRuleCondition(field: 'owner.name', op: 'contains', value: '营销号'),
        SimpleRuleCondition(field: 'stat.view', op: 'lt', value: 1000),
      ]);
      expect(
        engine.shouldHide(
          [_rule(condition)],
          (field) => switch (field) {
            'owner.name' => '某营销号',
            'stat.view' => 100000,
            _ => null,
          },
        ),
        isTrue,
      );
    });

    test('highlight 返回第一条命中的样式', () {
      const rule = JsonRule(
        condition: SimpleRuleCondition(
          field: 'content',
          op: 'startsWith',
          value: '【',
        ),
        action: 'highlight',
        style: DanmakuHighlightStyle(
          colorValue: 0xFFD700,
          bold: true,
          scale: 1.2,
        ),
      );
      final style = engine.highlightStyle(
        [rule],
        (field) => field == 'content' ? '【翻译】Hello' : null,
      );
      expect(style, isNotNull);
      expect(style!.argb, 0xFFFFD700);
      expect(style.bold, isTrue);
      expect(style.scale, 1.2);
    });

    test('非法正则不抛异常，按不命中处理', () {
      expect(
        engine.shouldHide(
          [
            _rule(
              const SimpleRuleCondition(
                field: 'title',
                op: 'regex',
                value: '[',
              ),
            ),
          ],
          (field) => '任意标题',
        ),
        isFalse,
      );
    });
  });
}
