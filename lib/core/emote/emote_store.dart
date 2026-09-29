import 'package:flutter/foundation.dart';

import 'package:winwin/core/log/app_logger.dart';
import 'package:winwin/http/reply.dart';
import 'package:winwin/models/common/emote_package.dart';

/// 官方表情数据源（2026-09-29）：表情面板与评论渲染共用的会话级缓存。
///
/// 三级数据源（按序尝试，任一成功即止）：
/// ① 登录面板接口 `/x/emote/user/panel/web`（用户全部可用分包，PiliPlus 同源）；
/// ② 免登录包明细 `/x/emote/package?ids=1`（小黄脸全量，游客/接口降级可用）；
/// ③ 均为空 → 由调用方回退内置静态表 `BilibiliEmotes`。
///
/// 特性：内存缓存、在途去重（单飞）、失败静默（仅日志留痕）且失败后 30s 内不重试。
class EmoteStore extends ChangeNotifier {
  EmoteStore._();

  static final EmoteStore instance = EmoteStore._();

  static const int _fallbackPackageId = 1; // 小黄脸
  static const Duration _retryCooldown = Duration(seconds: 30);

  List<EmotePackage> _packages = const [];
  Future<void>? _inflight;
  DateTime? _lastFailAt;
  Map<String, String>? _codeToUrl;

  /// 服务端分包（空表示不可用，调用方回退静态表）。
  List<EmotePackage> get packages => _packages;

  bool get available => _packages.isNotEmpty;

  /// 幂等加载（已加载或加载中直接复用；失败后 30s 内不重试）。
  void ensureLoaded() {
    if (_packages.isNotEmpty || _inflight != null) return;
    final last = _lastFailAt;
    if (last != null && DateTime.now().difference(last) < _retryCooldown) {
      return;
    }
    _inflight = _load();
  }

  Future<void> _load() async {
    try {
      final primary = await ReplyHttp.getEmoteList();
      var result = primary.dataOrNull;
      if (result == null || result.isEmpty) {
        // 游客（packages 为 null）/ 面板接口失败：免登录包明细兜底。
        final fallback = await ReplyHttp.getEmotePackagesByIds(
          const [_fallbackPackageId],
        );
        result = fallback.dataOrNull;
      }
      if (result == null || result.isEmpty) {
        _lastFailAt = DateTime.now();
        AppLogger.w('EmoteStore', 'emote load empty, fallback to built-in');
        return;
      }
      _packages = result;
      _codeToUrl = null;
      var total = 0;
      for (final p in result) {
        total += p.emote.length;
      }
      AppLogger.w(
        'EmoteStore',
        'emote loaded packages=${result.length} emotes=$total',
      );
      notifyListeners();
    } catch (e) {
      _lastFailAt = DateTime.now();
      AppLogger.w('EmoteStore', 'emote load failed: $e');
    } finally {
      _inflight = null;
    }
  }

  /// 表情码 → 图片 URL（跨包首个命中；供评论渲染回退链使用）。
  String? urlOf(String code) {
    if (_packages.isEmpty) return null;
    final map = _codeToUrl ??= _buildCodeMap();
    return map[code];
  }

  Map<String, String> _buildCodeMap() {
    final map = <String, String>{};
    for (final p in _packages) {
      for (final e in p.emote) {
        if (e.text.isNotEmpty && e.url.isNotEmpty) {
          map.putIfAbsent(e.text, () => e.url);
        }
      }
    }
    return map;
  }
}
