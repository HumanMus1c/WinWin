import 'dart:collection';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/core/log/app_logger.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/grpc/bilibili/community/service/dm/v1.pb.dart';
import 'package:winwin/http/danmaku.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/models/danmaku/danmaku_rule.dart';
import 'package:winwin/pages/danmaku/danmaku_options.dart';
import 'package:winwin/plugin/canvas_danmaku/canvas_danmaku.dart';
import 'package:winwin/utils/crc32.dart';
import 'package:winwin/utils/danmaku_utils.dart';

/// 弹幕数据控制器（移植自 PiliPlus `lib/pages/danmaku/controller.dart`）。
///
/// 职责：
/// - 按段（每段 6 分钟）懒加载弹幕，HTTP protobuf 拉取后本地分桶。
/// - 入桶前过滤：合并去重（同 content 累加 count）+ RuleFilter（关键词/正则/uid）。
/// - 出桶（[getCurrentDanmaku]）时做渲染前过滤：智能云屏蔽（weight）、
///   彩色屏蔽、会员彩色弹幕标记。
/// - 检测 UP 关闭弹幕（`DmSegMobileReply.state == 1`）。
/// - 提供本地发送弹幕回显（[addLocal]）。
class WinWinDanmakuController {
  WinWinDanmakuController({required this.cid});

  final int cid;

  /// 本地发送弹幕的回显（发送成功后置入，弹幕视图监听后上屏）。
  final ValueNotifier<DanmakuContentItem<DanmakuElem>?> localEcho =
      ValueNotifier(null);

  /// 按 0.1s（100ms）分桶存储弹幕，key = progress ~/ 100。
  final Map<int, List<DanmakuElem>> _dmSegMap = HashMap<int, List<DanmakuElem>>();

  /// 已请求的段号集合（0-based），防重复拉取。
  final Set<int> _requestedSeg = HashSet<int>();

  /// 合并去重缓存：content → 已存在的弹幕（仅非自己的弹幕参与合并）。
  final Map<String, DanmakuElem> _uniques = HashMap<String, DanmakuElem>();

  /// 服务端是否关闭了该视频的弹幕（UP 关闭）。
  bool _closed = false;
  bool get danmakuClosed => _closed;

  /// 当前账号的 midHash（用于标记自己的弹幕）。未登录时为 null。
  String? get _selfMidHash {
    final mid = Accounts.main.mid;
    return mid > 0 ? Crc32.midHash(mid) : null;
  }

  /// 当前过滤规则。空过滤器时短路跳过。
  RuleFilter _filters = RuleFilter.empty();
  RuleFilter get filters => _filters;

  /// 段长度：6 分钟 = 360000ms（B 站约定）。
  static const int segmentLength = 60 * 6 * 1000;

  /// 进度 → 段号（0-based）。
  static int calcSegment(int progress) => progress ~/ segmentLength;

  bool _disposed = false;

  /// 更新过滤规则（屏蔽页修改后调用）。
  void setFilters(RuleFilter filters) {
    _filters = filters;
  }

  /// 从持久化存储重建过滤规则（启动时调用）。
  void loadFilters() {
    final json = Pref.danmakuFilterRule;
    if (json is List) {
      _filters = RuleFilter.fromJson(json);
    } else {
      _filters = RuleFilter.empty();
    }
  }

  /// 预载：仅初始化过滤器。实际分段按进度懒加载。
  Future<void> preload() async {
    _closed = false;
    loadFilters();
  }

  /// 拉取指定段（0-based 段号），成功后分桶存储。
  ///
  /// 注意：B 站接口 segment_index 为 1-based，调用时 +1。
  Future<void> queryDanmaku(int segmentIndex) async {
    if (_disposed || _requestedSeg.contains(segmentIndex)) return;
    _requestedSeg.add(segmentIndex);
    final res = await DanmakuHttp.getDanmakuSegment(
      cid: cid,
      segmentIndex: segmentIndex + 1,
    );
    if (_disposed) return;
    switch (res) {
      case Success(:final response):
        // state == 1：UP 关闭了该视频弹幕。
        if (response.state == 1) {
          _closed = true;
        }
        handleDanmaku(response.elems);
        AppLogger.d('DanmakuCtrl', 'segment $segmentIndex loaded: ${response.elems.length} elems, closed=$_closed');
      case Error():
        // 失败时移除标记，允许后续重试。
        _requestedSeg.remove(segmentIndex);
        AppLogger.w('DanmakuCtrl', 'segment $segmentIndex fetch failed: ${res.errMsg}');
      case Loading():
        break;
    }
  }

  /// 处理弹幕列表：标记自己、合并去重、规则过滤、入桶。
  void handleDanmaku(List<DanmakuElem> elems) {
    if (_disposed || elems.isEmpty) return;
    final selfHash = _selfMidHash;
    final shouldMerge = DanmakuOptions.mergeDanmaku;
    final shouldFilter = _filters.count > 0;
    for (final e in elems) {
      // 标记自己的弹幕（仅登录时）。
      if (selfHash != null) {
        e.isSelf = e.midHash == selfHash;
      }
      // 非自己的弹幕才参与合并 / 过滤。
      if (!e.isSelf) {
        if (shouldMerge) {
          final existing = _uniques[e.content];
          if (existing != null) {
            // 合并：累加 count，不入桶。
            existing.count = existing.count + 1;
            continue;
          }
          _uniques[e.content] = e;
        }
        if (shouldFilter && _filters.remove(e)) {
          continue;
        }
      }
      // 入桶：按 0.1s 分桶。
      final int pos = e.progress ~/ 100;
      (_dmSegMap[pos] ??= <DanmakuElem>[]).add(e);
    }
  }

  /// 取 [progressMs] 附近应上屏的弹幕（已做渲染前过滤）。
  ///
  /// 若该段未加载，触发异步拉取并返回空列表（下一帧再取）。
  List<DanmakuContentItem<DanmakuElem>> getCurrentDanmaku(int progressMs) {
    if (_disposed || _closed) return const [];
    final seg = calcSegment(progressMs);
    if (!_requestedSeg.contains(seg)) {
      // 异步拉取，不阻塞当前帧。
      queryDanmaku(seg);
      return const [];
    }
    final bucket = _dmSegMap[progressMs ~/ 100];
    if (bucket == null || bucket.isEmpty) return const [];
    return _applyRenderFilters(bucket);
  }

  /// 渲染前过滤：weight / 彩色屏蔽 / 会员彩色标记。
  ///
  /// 返回可直接交给引擎的 [DanmakuContentItem] 列表。
  List<DanmakuContentItem<DanmakuElem>> _applyRenderFilters(
      List<DanmakuElem> bucket) {
    final weight = DanmakuOptions.weight;
    final blockColorful = DanmakuOptions.blockColorful;
    final showVip = DanmakuOptions.showVipDanmaku;
    final result = <DanmakuContentItem<DanmakuElem>>[];
    for (final e in bucket) {
      // 智能云屏蔽：权重低于阈值的弹幕跳过。
      if (weight > 0 && e.weight < weight) continue;
      final isVipColor = e.colorful == DmColorfulType.VipGradualColor;
      // 彩色屏蔽：强制白色；否则取弹幕原色。
      final color = blockColorful
          ? const Color(0xFFFFFFFF)
          : DmUtils.decimalToColor(e.color);
      // 高级弹幕（mode 7）目前按滚动简化处理（高级弹幕需要特殊解析，
      // 后续可接入 SpecialDanmakuContentItem.fromList）。
      result.add(
        DanmakuContentItem<DanmakuElem>(
          e.content,
          color: color,
          type: DmUtils.getPosition(e.mode),
          selfSend: e.isSelf,
          isColorful: showVip && isVipColor,
          count: e.count > 1 ? e.count : null,
          extra: e,
        ),
      );
    }
    return result;
  }

  /// 本地发送弹幕回显（mode：1/2/3=滚动，4=底部，5=顶部）。
  ///
  /// 发送成功后调用，立即上屏无需等待服务端重新拉取。
  void addLocal({
    required String text,
    required int mode,
    int color = 0xFFFFFF,
  }) {
    final elem = DanmakuElem()
      ..content = text
      ..mode = mode
      ..color = color & 0xFFFFFF
      ..isSelf = true;
    localEcho.value = DanmakuContentItem<DanmakuElem>(
      text,
      color: DmUtils.decimalToColor(color),
      type: DmUtils.getPosition(mode),
      selfSend: true,
      extra: elem,
    );
  }

  void dispose() {
    _disposed = true;
    _dmSegMap.clear();
    _requestedSeg.clear();
    _uniques.clear();
    localEcho.dispose();
  }
}
