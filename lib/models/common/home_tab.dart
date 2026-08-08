/// 首页子 Tab 枚举（PiliPlus 风格）。
///
/// 参照 PiliPlus 的 `HomeTabType`：首页顶部分类标签，支持用户重排。
/// 当前内置默认顺序；后续可接入 `SettingBoxKey.tabBarSort` 持久化用户自定义顺序。
enum HomeTabType {
  recommend('推荐'),
  follow('关注'),
  hot('热门'),
  bangumi('番剧');

  final String label;
  const HomeTabType(this.label);

  /// 默认显示顺序（可被用户重排覆盖）。
  static const List<HomeTabType> defaultOrder = [
    recommend,
    follow,
    hot,
    bangumi,
  ];
}
