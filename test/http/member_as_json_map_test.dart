import 'package:flutter_test/flutter_test.dart';

import 'package:winwin/http/member.dart';

void main() {
  // 回归背景：2026-10-16/17 `MemberSpace: topPhoto 加载失败`，
  // 错误 = `获取背景图失败：type 'String' is not a subtype of type 'Map<String, dynamic>' in type cast`。
  // 根因：`/x/space/top/photo` 在风控 / 异常时返回**非 JSON** 响应体，客户端裸
  // `res.data as Map<String, dynamic>` 抛 TypeError。修复后统一走 `MemberHttp.asJsonMap`。
  group('MemberHttp.asJsonMap（响应体安全解析）', () {
    test('Map 输入：原样返回同一实例', () {
      final map = <String, dynamic>{
        'code': 0,
        'data': {'img_url': 'x'},
      };
      expect(identical(MemberHttp.asJsonMap(map), map), isTrue);
    });

    test('JSON 字符串：解码为 Map（兼容 content-type 未标 JSON 的文本响应）', () {
      final r = MemberHttp.asJsonMap('{"code":0,"data":{"img_url":"x"}}');
      expect(r['code'], 0);
      expect((r['data'] as Map)['img_url'], 'x');
    });

    test('非 JSON 文本（风控 HTML）：返回空 Map，不再抛 cast 类型错误', () {
      expect(() => MemberHttp.asJsonMap('<html>412</html>'), returnsNormally);
      expect(MemberHttp.asJsonMap('<html>412</html>'), isEmpty);
    });

    test('空串 / null / 数字 / 列表：一律降级为空 Map', () {
      expect(MemberHttp.asJsonMap(''), isEmpty);
      expect(MemberHttp.asJsonMap('   '), isEmpty);
      expect(MemberHttp.asJsonMap(null), isEmpty);
      expect(MemberHttp.asJsonMap(123), isEmpty);
      expect(MemberHttp.asJsonMap(<int>[1, 2]), isEmpty);
    });

    test('回归：原崩溃输入（String 响应体）不再抛异常', () {
      expect(
        () => MemberHttp.asJsonMap('not-a-json-body'),
        returnsNormally,
      );
      expect(MemberHttp.asJsonMap('not-a-json-body'), isEmpty);
    });
  });
}