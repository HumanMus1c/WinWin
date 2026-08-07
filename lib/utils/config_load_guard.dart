/// 配置加载守卫 — 从 BiliPai VideoEnhancementConfigLoadGuard.kt 移植。
///
/// 解决竞态：磁盘旧配置可能覆盖进程内用户刚修改的配置。
/// 一旦 [markLocalChange] 被调用，[shouldApplyLoadedConfig] 永久返回 false。
///
/// 语义：进程内一次性翻转开关，不可重置。
class ConfigLoadGuard {
  bool _hasLocalChanges = false;

  /// 用户在本进程修改了配置后调用。
  void markLocalChange() => _hasLocalChanges = true;

  /// 是否应该应用从存储加载的配置。
  ///
  /// 返回 false 表示进程内已有更新，应忽略磁盘加载的值。
  bool shouldApplyLoadedConfig() => !_hasLocalChanges;
}
