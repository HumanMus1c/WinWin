import 'package:winwin/models/danmaku/danmaku_rule.dart';

/// `/x/dm/filter/user` 返回的云端屏蔽规则聚合模型。
///
/// B 站把三类规则分别放在 `rule`（关键词）/`rule1`（正则）/`rule2`（用户）
/// 字段下，每类元素结构为 `{id, type, filter}`。
class DanmakuBlockDataModel {
  final List<SimpleRule> rule;
  final List<SimpleRule> rule1;
  final List<SimpleRule> rule2;

  /// 聚合为 [RuleFilter.fromRules] 所需的三元列表（顺序：keyword/regex/uid）。
  List<List<SimpleRule>> get rules => [rule, rule1, rule2];

  const DanmakuBlockDataModel({
    this.rule = const [],
    this.rule1 = const [],
    this.rule2 = const [],
  });

  factory DanmakuBlockDataModel.fromJson(Map<String, dynamic> json) {
    List<SimpleRule> parseList(dynamic raw) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => SimpleRule.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false);
    }

    return DanmakuBlockDataModel(
      rule: parseList(json['rule']),
      rule1: parseList(json['rule1']),
      rule2: parseList(json['rule2']),
    );
  }
}
