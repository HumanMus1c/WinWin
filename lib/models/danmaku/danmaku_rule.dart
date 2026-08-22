import 'package:winwin/grpc/bilibili/community/service/dm/v1.pb.dart';

/// 弹幕屏蔽规则类型（与 B 站 `/x/dm/filter/user` 接口约定一致）。
///
/// - [keyword]：关键词（type=0），子串匹配。
/// - [regex]：正则（type=1），上传时用 `/.../` 包裹，本地存储剥离后编译。
/// - [uid]：用户（type=2），上传时把 mid 转成 midHash（CRC32 hex）。
enum DmBlockType {
  keyword('关键词', 0),
  regex('正则', 1),
  uid('用户', 2),
  ;

  final String label;
  final int serverType;
  const DmBlockType(this.label, this.serverType);
}

/// 单条屏蔽规则（与 B 站服务端结构对应）。
class SimpleRule {
  final int id;
  final int type;
  final String filter;

  const SimpleRule({required this.id, required this.type, required this.filter});

  factory SimpleRule.fromJson(Map<String, dynamic> json) => SimpleRule(
        id: json['id'] as int? ?? 0,
        type: json['type'] as int? ?? 0,
        filter: json['filter'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'id': id, 'type': type, 'filter': filter};

  @override
  String toString() => 'SimpleRule(id=$id, type=$type, filter="$filter")';
}

/// 弹幕过滤执行器（移植自 PiliPlus `lib/models/user/danmaku_rule.dart`）。
///
/// 在「弹幕入桶前」执行：命中则不入桶，不进入渲染层。
/// 三重短路判断（OR）：用户屏蔽 → 关键词 → 正则。
///
/// - 用户屏蔽匹配的是 `DanmakuElem.midHash`（CRC32 hex），非原始 uid。
/// - 关键词为子串包含（大小写敏感）。
/// - 正则大小写不敏感。
class RuleFilter {
  final List<String> dmFilterString;
  final List<RegExp> dmRegExp;
  final Set<String> dmUid;

  /// 规则总数（0 表示无规则，调用方可短路跳过）。
  final int count;

  const RuleFilter._({
    required this.dmFilterString,
    required this.dmRegExp,
    required this.dmUid,
    required this.count,
  });

  /// 空过滤器（无任何规则，[remove] 永远返回 false）。
  factory RuleFilter.empty() =>
      const RuleFilter._(dmFilterString: [], dmRegExp: [], dmUid: {}, count: 0);

  /// 从三类规则列表构造（顺序：[keyword, regex, uid]）。
  ///
  /// 正则规则按 PiliPlus 约定用 `/.../` 包裹，构造时剥离首尾 `/`。
  factory RuleFilter.fromRules(List<List<SimpleRule>> rules) {
    final keywords = <String>[];
    final regexes = <RegExp>[];
    final uids = <String>{};
    if (rules.isNotEmpty) {
      for (final r in rules[0]) {
        if (r.filter.isNotEmpty) keywords.add(r.filter);
      }
    }
    if (rules.length > 1) {
      for (final r in rules[1]) {
        final body = _stripRegexSlash(r.filter);
        if (body.isEmpty) continue;
        try {
          regexes.add(RegExp(body, caseSensitive: false));
        } catch (_) {
          // 非法正则直接跳过，避免污染整个过滤器。
        }
      }
    }
    if (rules.length > 2) {
      for (final r in rules[2]) {
        if (r.filter.isNotEmpty) uids.add(r.filter);
      }
    }
    return RuleFilter._(
      dmFilterString: keywords,
      dmRegExp: regexes,
      dmUid: uids,
      count: keywords.length + regexes.length + uids.length,
    );
  }

  /// 从持久化的 JSON 重建。
  factory RuleFilter.fromJson(List<dynamic>? json) {
    if (json == null || json.length < 3) return RuleFilter.empty();
    final rules = <List<SimpleRule>>[];
    for (final group in json) {
      if (group is List) {
        rules.add(
          group
              .whereType<Map>()
              .map((e) => SimpleRule.fromJson(e.cast<String, dynamic>()))
              .toList(growable: false),
        );
      } else {
        rules.add(const []);
      }
    }
    while (rules.length < 3) {
      rules.add(const []);
    }
    return RuleFilter.fromRules(rules);
  }

  /// 序列化为 JSON（用于 Hive 持久化）。
  List<List<Map<String, dynamic>>> toJson() => [
        [for (final s in dmFilterString) SimpleRule(id: 0, type: 0, filter: s).toJson()],
        [
          for (final r in dmRegExp)
            SimpleRule(id: 0, type: 1, filter: '/${r.pattern}/').toJson(),
        ],
        [for (final u in dmUid) SimpleRule(id: 0, type: 2, filter: u).toJson()],
      ];

  /// 命中过滤返回 true（该弹幕应被屏蔽）。
  ///
  /// 短路顺序：uid → 关键词 → 正则。
  bool remove(DanmakuElem elem) {
    return dmUid.contains(elem.midHash) ||
        dmFilterString.any((i) => elem.content.contains(i)) ||
        dmRegExp.any((i) => i.hasMatch(elem.content));
  }

  static String _stripRegexSlash(String s) {
    if (s.length >= 2 && s.startsWith('/') && s.endsWith('/')) {
      return s.substring(1, s.length - 1);
    }
    return s;
  }
}
