import 'package:flutter/foundation.dart';
import 'package:winwin/core/storage/storage.dart';

/// 搜索后交互过的 UP 主 / 用户数据模型。
class SearchHistoryUser {
  final int mid;
  final String name;
  final String face;
  final int timestamp;

  const SearchHistoryUser({
    required this.mid,
    required this.name,
    required this.face,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'mid': mid,
        'name': name,
        'face': face,
        'timestamp': timestamp,
      };

  factory SearchHistoryUser.fromJson(Map<String, dynamic> json) =>
      SearchHistoryUser(
        mid: json['mid'] as int? ?? 0,
        name: json['name'] as String? ?? '',
        face: json['face'] as String? ?? '',
        timestamp: json['timestamp'] as int? ?? 0,
      );
}

/// 搜索历史交互用户管理服务（单例）。
class SearchHistoryService extends ChangeNotifier {
  SearchHistoryService._() {
    _load();
  }

  static final SearchHistoryService _instance = SearchHistoryService._();
  factory SearchHistoryService() => _instance;

  static const String _storageKey = 'searchHistoryUsers';
  List<SearchHistoryUser> _users = [];

  List<SearchHistoryUser> get users => List.unmodifiable(_users);

  void _load() {
    final rawList = GStorage.localCache.get(_storageKey);
    if (rawList is List) {
      _users = rawList
          .map((e) {
            if (e is Map) {
              return SearchHistoryUser.fromJson(e.cast<String, dynamic>());
            }
            return null;
          })
          .whereType<SearchHistoryUser>()
          .toList();
    }
  }

  /// 记录搜索后观看稿件的作者或直接访问空间的用户。
  void addVisitedUser({
    required int mid,
    required String name,
    required String face,
  }) {
    if (mid <= 0 || name.trim().isEmpty) return;
    _users.removeWhere((u) => u.mid == mid);
    _users.insert(
      0,
      SearchHistoryUser(
        mid: mid,
        name: name.trim(),
        face: face.trim(),
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (_users.length > 20) {
      _users = _users.sublist(0, 20);
    }
    _persist();
    notifyListeners();
  }

  /// 移除单个用户。
  void removeVisitedUser(int mid) {
    _users.removeWhere((u) => u.mid == mid);
    _persist();
    notifyListeners();
  }

  /// 清空所有交互用户记录。
  void clearVisitedUsers() {
    if (_users.isNotEmpty) {
      _users.clear();
      _persist();
      notifyListeners();
    }
  }

  void _persist() {
    GStorage.localCache.put(
      _storageKey,
      _users.map((u) => u.toJson()).toList(),
    );
  }
}
