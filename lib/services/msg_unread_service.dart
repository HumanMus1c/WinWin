import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:winwin/core/account/account_service.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/msg.dart';

/// 消息未读计数服务。
///
/// 管理四类互动入口（回复/艾特/点赞/系统）的未读数，
/// 计算四者总和并广播通知，供导航栏与消息页展示未读气泡。
class MsgUnreadService extends ChangeNotifier {
  MsgUnreadService._() {
    AccountService().addListener(_onAccountChanged);
  }

  static final MsgUnreadService _instance = MsgUnreadService._();
  factory MsgUnreadService() => _instance;

  int _reply = 0;
  int _at = 0;
  int _like = 0;
  int _system = 0;

  int get reply => _reply;
  int get at => _at;
  int get like => _like;
  int get system => _system;

  /// 四类互动未读气泡数的总和。
  int get totalInteractiveUnread => _reply + _at + _like + _system;

  void _onAccountChanged() {
    if (AccountService().isLogin) {
      unawaited(fetchUnread());
    } else {
      reset();
    }
  }

  /// 拉取未读数。
  Future<void> fetchUnread() async {
    if (!AccountService().isLogin) {
      reset();
      return;
    }
    try {
      final res = await MsgHttp.msgFeedUnread();
      if (res case Success(:final response)) {
        _reply = (response['reply'] as num?)?.toInt() ?? 0;
        _at = (response['at'] as num?)?.toInt() ?? 0;
        _like = (response['like'] as num?)?.toInt() ?? 0;
        _system = (response['system'] as num?)?.toInt() ?? 0;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// 乐观清零某类互动未读数。
  void clearKey(String key) {
    var changed = false;
    switch (key) {
      case 'reply':
        if (_reply > 0) {
          _reply = 0;
          changed = true;
        }
      case 'at':
        if (_at > 0) {
          _at = 0;
          changed = true;
        }
      case 'like':
        if (_like > 0) {
          _like = 0;
          changed = true;
        }
      case 'system':
        if (_system > 0) {
          _system = 0;
          changed = true;
        }
    }
    if (changed) {
      notifyListeners();
    }
  }

  /// 重置为 0。
  void reset() {
    if (_reply != 0 || _at != 0 || _like != 0 || _system != 0) {
      _reply = 0;
      _at = 0;
      _like = 0;
      _system = 0;
      notifyListeners();
    }
  }
}
