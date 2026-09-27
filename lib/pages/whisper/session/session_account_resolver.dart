import 'dart:async';

import 'package:winwin/http/follow.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/msg.dart';

/// 会话用户信息解析器（移植自 BiliPai `InboxUserInfoResolver` + `InboxViewModel`）。
///
/// `get_sessions` 对普通用户会话（session_type=1）通常不带 account_info，
/// 导致列表头像/昵称空白。本类在列表加载后按 talker_id 批量拉取用户卡片
/// （account/v1/user/cards），未命中的逐个用用户名片接口兜底，
/// 结果写回会话 Map 的 `account_info` 并进程内缓存，供列表与聊天页复用。
abstract final class SessionAccountResolver {
  /// 进程内缓存：talker_id → {name, face}（face 已归一化为 https）。
  static final Map<int, ({String name, String face})> _cache = {};

  /// 特别关注缓存：talker_id → 是否特别关注。
  static final Map<int, bool> _specialCache = {};

  /// 特别关注 mid 全集缓存（来自 /x/relation/tag?tagid=-10，null=未拉取）。
  static Set<int>? _specialMids;

  /// 缓存容量上限：会话用户/特别关注缓存随浏览历史单调增长，需淘汰最久未插入项。
  static const int _maxAccountCache = 500;
  static const int _maxSpecialCache = 500;

  static void _putAccount(int mid, String name, String face) {
    _cache[mid] = (name: name, face: face);
    while (_cache.length > _maxAccountCache) {
      _cache.remove(_cache.keys.first);
    }
  }

  static void _putSpecial(int mid, bool value) {
    _specialCache[mid] = value;
    while (_specialCache.length > _maxSpecialCache) {
      _specialCache.remove(_specialCache.keys.first);
    }
  }

  /// 头像 URL 归一化：`//` 协议相对地址补 https，http 升级为 https。
  static String normalizeAvatarUrl(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return '';
    if (value.startsWith('//')) return 'https:$value';
    if (value.startsWith('http://')) return value.replaceFirst('http://', 'https://');
    return value;
  }

  /// 解析会话显示昵称：缓存 → account_info → 兜底 `用户{mid}`。
  static String displayName(Map<String, dynamic> session) {
    final talkerId = (session['talker_id'] as num?)?.toInt() ?? 0;
    final cached = _cache[talkerId];
    final cachedName = cached?.name.trim();
    if (cachedName != null && cachedName.isNotEmpty) return cachedName;

    final account = session['account_info'] as Map?;
    final name = account?['name']?.toString().trim();
    if (name != null && name.isNotEmpty) return name;

    final groupName = session['group_name']?.toString().trim();
    if (groupName != null && groupName.isNotEmpty) return groupName;
    return talkerId > 0 ? '用户$talkerId' : '未知会话';
  }

  /// 解析会话头像：缓存 → account_info（pic_url/face）→ group_cover。
  static String displayAvatar(Map<String, dynamic> session) {
    final talkerId = (session['talker_id'] as num?)?.toInt() ?? 0;
    final cachedFace = normalizeAvatarUrl(_cache[talkerId]?.face);
    if (cachedFace.isNotEmpty) return cachedFace;

    final account = session['account_info'] as Map?;
    final picUrl = normalizeAvatarUrl(account?['pic_url']?.toString());
    if (picUrl.isNotEmpty) return picUrl;
    final face = normalizeAvatarUrl(account?['face']?.toString());
    if (face.isNotEmpty) return face;
    return normalizeAvatarUrl(session['group_cover']?.toString());
  }

  /// 异步补全 [sessions] 中缺失的用户信息。
  ///
  /// 仅处理 session_type=1 且 account_info 不完整（昵称或头像缺失）的会话；
  /// 命中缓存的直接写回。返回 true 表示会话数据有更新，调用方应 setState。
  static Future<bool> fillSessionAccounts(List<Map<String, dynamic>> sessions) async {
    if (sessions.isEmpty) return false;

    // 1. 先用缓存即时填充
    var updated = false;
    final pending = <int>[];
    for (final s in sessions) {
      if (!_needFetch(s)) continue;
      final talkerId = (s['talker_id'] as num?)?.toInt() ?? 0;
      final cached = _cache[talkerId];
      if (cached != null && _isComplete(cached.name, cached.face)) {
        _applyAccount(s, cached.name, cached.face);
        updated = true;
      } else if (talkerId > 0 && !pending.contains(talkerId)) {
        pending.add(talkerId);
      }
    }
    if (pending.isEmpty) return updated;

    // 2. 批量拉取（每批 20 个 uid）
    for (var i = 0; i < pending.length; i += 20) {
      final batch = pending.sublist(i, (i + 20).clamp(0, pending.length));
      final res = await MsgHttp.sessionAccountCards(uids: batch);
      if (res case Success(:final response)) {
        for (final card in response) {
          final mid = (card['mid'] as num?)?.toInt() ?? 0;
          if (mid <= 0) continue;
          final name = card['name']?.toString() ?? '';
          final face = normalizeAvatarUrl(card['face']?.toString());
          if (name.isEmpty && face.isEmpty) continue;
          _putAccount(mid, name, face);
        }
      }
    }

    // 3. 批量接口未命中的逐个用用户名片兜底（对齐 BiliPai 的 card 接口兜底）
    for (final mid in pending) {
      final cached = _cache[mid];
      if (cached != null && _isComplete(cached.name, cached.face)) continue;
      final res = await MsgHttp.userCard(mid: mid);
      if (res case Success(:final response)) {
        final name = response['name']?.toString() ?? '';
        final face = normalizeAvatarUrl(response['face']?.toString());
        if (name.isNotEmpty || face.isNotEmpty) {
          _putAccount(mid, name, face);
        }
      }
    }

    // 4. 写回会话
    for (final s in sessions) {
      if (!_needFetch(s)) continue;
      final talkerId = (s['talker_id'] as num?)?.toInt() ?? 0;
      final cached = _cache[talkerId];
      if (cached != null && _isComplete(cached.name, cached.face)) {
        _applyAccount(s, cached.name, cached.face);
        updated = true;
      }
    }
    return updated;
  }

  /// 是否需要拉取：用户会话（session_type=1）且 account_info 不完整。
  static bool _needFetch(Map<String, dynamic> session) {
    final sessionType = (session['session_type'] as num?)?.toInt() ?? 1;
    if (sessionType != 1) return false;
    final talkerId = (session['talker_id'] as num?)?.toInt() ?? 0;
    if (talkerId <= 0) return false;
    final account = session['account_info'] as Map?;
    final name = account?['name']?.toString().trim() ?? '';
    final face = normalizeAvatarUrl(account?['pic_url']?.toString()).isNotEmpty
        ? normalizeAvatarUrl(account?['pic_url']?.toString())
        : normalizeAvatarUrl(account?['face']?.toString());
    return !_isComplete(name, face);
  }

  static bool _isComplete(String name, String face) =>
      name.trim().isNotEmpty && face.isNotEmpty;

  static void _applyAccount(Map<String, dynamic> session, String name, String face) {
    session['account_info'] = <String, dynamic>{
      'name': name,
      'face': face,
      'pic_url': face,
    };
  }

  /// 会话对方是否为特别关注（依赖 [fillSpecialFollows] 的缓存）。
  static bool isSpecialFollow(Map<String, dynamic> session) {
    final talkerId = (session['talker_id'] as num?)?.toInt() ?? 0;
    return _specialCache[talkerId] ?? false;
  }

  /// 拉取特别关注 mid 全集（/x/relation/tag?tagid=-10 分页拉全），进程内缓存。
  ///
  /// 请求失败返回 null，调用方可降级为逐个 /x/relation 查询。
  static Future<Set<int>?> fetchSpecialMids({bool refresh = false}) async {
    if (_specialMids != null && !refresh) return _specialMids;
    final mids = <int>{};
    var pn = 1;
    const ps = 50;
    while (pn <= 100) {
      // 上限兜底，防止异常 total 导致死循环
      final res = await FollowHttp.followGroupUsers(tagid: -10, pn: pn, ps: ps);
      if (res case Error()) return _specialMids;
      if (res case Success(:final response)) {
        final list = response['list'] as List;
        final total = (response['total'] as num?)?.toInt() ?? 0;
        for (final e in list) {
          final mid = e is Map ? (e['mid'] as num?)?.toInt() ?? 0 : 0;
          if (mid > 0) mids.add(mid);
        }
        if (list.length < ps || mids.length >= total) break;
        pn++;
      }
    }
    _specialMids = mids;
    for (final mid in mids) {
      _putSpecial(mid, true);
    }
    return mids;
  }

  /// 异步补全 [sessions] 对方的特别关注状态并进程内缓存。
  ///
  /// 优先用特别关注分组接口一次拉全（tagid=-10），失败时降级为
  /// /x/relation 逐个查询（每批并发 8 个）。返回 true 表示有新增
  /// 特别关注，调用方应 setState 刷新标签。
  static Future<bool> fillSpecialFollows(
      List<Map<String, dynamic>> sessions) async {
    final pending = <int>{};
    for (final s in sessions) {
      if (((s['session_type'] as num?)?.toInt() ?? 1) != 1) continue;
      final talkerId = (s['talker_id'] as num?)?.toInt() ?? 0;
      if (talkerId <= 0 || _specialCache.containsKey(talkerId)) continue;
      pending.add(talkerId);
    }

    // 1. 分组接口拉全：命中的直接标记，其余标记 false。
    final mids = await fetchSpecialMids();
    if (mids != null) {
      var updated = false;
      for (final mid in pending) {
        final special = mids.contains(mid);
        _putSpecial(mid, special);
        if (special) updated = true;
      }
      return updated;
    }

    // 2. 降级：逐个 /x/relation 查询。
    var updated = false;
    if (pending.isEmpty) return false;
    const batch = 8;
    final ids = pending.toList();
    for (var i = 0; i < ids.length; i += batch) {
      final chunk = ids.sublist(i, (i + batch).clamp(0, ids.length));
      final results = await Future.wait(
        chunk.map((mid) async {
          final res = await FollowHttp.relation(fid: mid);
          if (res case Success(:final response)) {
            final special = (response['special'] as num?)?.toInt() ?? 0;
            return (mid: mid, special: special == 1);
          }
          return null;
        }),
      );
      for (final r in results) {
        if (r == null) continue;
        _putSpecial(r.mid, r.special);
        if (r.special) updated = true;
      }
    }
    return updated;
  }
}
