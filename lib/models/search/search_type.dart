/// 搜索类型枚举。
///
/// 移植自 PiliPlus 的 `SearchType`，仅保留 WinWin 桌面端需要的分类。
enum SearchType {
  video('视频'),
  mediaBangumi('番剧'),
  mediaFt('影视'),
  liveRoom('直播'),
  biliUser('用户'),
  article('专栏'),
  ;

  final String label;
  const SearchType(this.label);

  /// 用于 API 请求的 search_type 参数值。
  String get name => switch (this) {
        .video => 'video',
        .mediaBangumi => 'media_bangumi',
        .mediaFt => 'media_ft',
        .liveRoom => 'live_room',
        .biliUser => 'bili_user',
        .article => 'article',
      };
}
