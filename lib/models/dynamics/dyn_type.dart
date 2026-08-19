/// 动态类型与 Major 类型常量（对齐 B 站 Web 端 API）。
abstract final class DynType {
  /// 视频稿件动态。
  static const String av = 'DYNAMIC_TYPE_AV';
  /// 转发/转载动态。
  static const String forward = 'DYNAMIC_TYPE_FORWARD';
  /// 图文动态。
  static const String draw = 'DYNAMIC_TYPE_DRAW';
  /// 专栏动态（旧版专栏）。
  static const String article = 'DYNAMIC_TYPE_ARTICLE';
  /// 纯文字动态。
  static const String word = 'DYNAMIC_TYPE_WORD';
  /// 直播推荐动态。
  static const String liveRcmd = 'DYNAMIC_TYPE_LIVE_RCMD';
  /// 课程动态。
  static const String courses = 'DYNAMIC_TYPE_COURSES_SEASON';
  /// 追番/剧集动态。
  static const String pgc = 'DYNAMIC_TYPE_PGC';
  /// 剧集联合动态。
  static const String pgcUnion = 'DYNAMIC_TYPE_PGC_UNION';
}

/// 动态 Major 主要内容类型常量。
abstract final class DynMajorType {
  static const String archive = 'MAJOR_TYPE_ARCHIVE';
  static const String draw = 'MAJOR_TYPE_DRAW';
  static const String article = 'MAJOR_TYPE_ARTICLE';
  static const String opus = 'MAJOR_TYPE_OPUS';
  static const String liveRcmd = 'MAJOR_TYPE_LIVE_RCMD';
  static const String pgc = 'MAJOR_TYPE_PGC';
  static const String pgcUnion = 'MAJOR_TYPE_PGC_UNION';
  static const String courses = 'MAJOR_TYPE_COURSES';
  static const String none = 'MAJOR_TYPE_NONE';
}
