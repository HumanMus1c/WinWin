import 'dart:convert';

import 'package:winwin/core/log/app_logger.dart';

/// 把 HTTP 响应体安全解析为 JSON `Map`（全站统一入口 / 单一实现）。
///
/// ## 背景
///
/// B站接口在**风控 / 限流 / 接口异常**时可能返回**非 JSON** 响应体（HTML 错误页、
/// 空体、`text/plain` 字符串）。此时裸 `res.data as Map<String, dynamic>` 会抛
/// `type 'String' is not a subtype of type 'Map<String, dynamic>' in type cast`，
/// 被外层 `catch` 吞成「加载失败」——用户不可感知根因
/// （2026-10-16/17 `MemberSpace: topPhoto` 实测，见
/// `docs/用户空间背景图cast缺陷修复复盘-2026-10-17.md`）。
///
/// ## 统一降级口径
///
/// - `Map` → 原样返回（保持引用，happy path 零拷贝）；
/// - `String` → 尝试 `jsonDecode`（兼容 content-type 未标 JSON 的 JSON 文本）；
/// - 其余（含解析失败）→ 记 `warn`（含 `runtimeType`，保留可诊断线索）并返回**空 Map**。
///
/// ## 调用约定
///
/// 返回空 Map 时，调用方惯用的 `data['code'] == 0` 判定自然为假 → 落入既有的
/// 失败 / 默认分支，给出友好错误而非抛异常。**不要**依赖本函数抛错来区分失败。
Map<String, dynamic> asJsonMap(dynamic body) {
  if (body is Map<String, dynamic>) return body;
  if (body is Map) return Map<String, dynamic>.from(body);
  if (body is String && body.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // 非 JSON 文本（如风控 HTML），走下方降级。
    }
  }
  AppLogger.w(
    'Http',
    '响应体非 JSON Map（runtimeType=${body.runtimeType}），按接口失败处理',
  );
  return const <String, dynamic>{};
}