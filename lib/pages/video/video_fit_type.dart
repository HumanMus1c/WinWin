import 'package:material_ui/material_ui.dart' show BoxFit;

/// 视频「画面比例 / 缩放模式」枚举。
///
/// **移植自上游 PiliPlus** `lib/plugin/pl_player/models/video_fit_type.dart`
/// （commit 65d5bf8）。上游通过 `FittedBox(fit: boxFit) → SizedBox(视频尺寸或按
/// aspectRatio 归一化的尺寸) → Texture` 的组合实现各档位；本文件仅承载该模型，
/// 渲染在页面内按同一组合复刻。
///
/// 语义：
/// - [fill] 拉伸：把视频拉伸铺满播放区（会变形）；
/// - [contain] 自动：按视频源真实比例等比装入播放区（不变形，留黑边）；
/// - [cover] 裁剪：等比放大铺满播放区并裁掉溢出部分；
/// - [fitWidth] 等宽 / [fitHeight] 等高：按单边对齐；
/// - [none] 原始：按视频像素原始尺寸显示，不缩放；
/// - [scaleDown] 限制：等比缩小但不放大；
/// - [ratio_4x3] / [ratio_16x9]：把视频显示框强制为该比例（视频随之拉伸）。
enum VideoFitType {
  fill('拉伸', boxFit: BoxFit.fill),
  contain('自动', boxFit: BoxFit.contain),
  cover('裁剪', boxFit: BoxFit.cover),
  fitWidth('等宽', boxFit: BoxFit.fitWidth),
  fitHeight('等高', boxFit: BoxFit.fitHeight),
  none('原始', boxFit: BoxFit.none),
  scaleDown('限制', boxFit: BoxFit.scaleDown),
  ratio_4x3('4:3', aspectRatio: 4 / 3),
  ratio_16x9('16:9', aspectRatio: 16 / 9),
  ;

  final String desc;
  final BoxFit boxFit;

  /// 非空时把视频显示框宽度改为 `视频高 × aspectRatio`（即强制该显示比例）。
  final double? aspectRatio;

  const VideoFitType(
    this.desc, {
    this.boxFit = BoxFit.contain,
    this.aspectRatio,
  });
}