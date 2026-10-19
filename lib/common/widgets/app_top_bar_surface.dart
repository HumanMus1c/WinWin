import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/theme/style.dart';

/// App 顶部**合并栏**毛玻璃容器的材质单一来源。
///
/// 供「浮于滚动内容之上」的页面顶栏复用：首页（搜索框 + 分类器合并栏）与
/// 消息中心（互动入口 + 分类栏合并栏）共用同一材质 —— `cs.surface` ×
/// [surfaceAlpha] 半透明底 + backdrop 模糊 [blurSigma] + 外壳圆角
/// `chrome.containerRadius`，外距 `Style.lg × Style.sm`。
///
/// ## 为何抽出（对齐根因）
///
/// 抽出前两页各写一份，且**不同源**：
/// - 首页 `_HomeHeader`：`cs.surface` α0.72 + 模糊 20 + 圆角
///   `chrome.containerRadius`(=20)，末置一条 α0 的 0.5px 描边（不显示边框）。
/// - 消息中心 `_buildFrostedHeader`：`MiuixFrostedSurface`（硬编码底
///   `0xFF262626`/`0xFFEAEAEA` × `kMiuixSurfaceAlpha`0.85 + 模糊 16 + 圆角
///   `Style.radiusMd`12）。
///
/// 后者底色**不随主题 `surface` 走**（写死的灰），亮度/色相都与整页背景面
/// 不一致，实机观感与首页顶栏不和谐（CVO 反馈「消息中心顶栏背景模糊的颜色与
/// 亮度未对齐程序整体背景」）。此组件把首页那套材质收敛为**唯一实现**，两页
/// 同源即天然对齐，也杜绝再度漂移（P4「每个概念只在一处定义」）。
class AppTopBarSurface extends StatelessWidget {
  const AppTopBarSurface({super.key, required this.child});

  /// 半透明底的不透明度（与首页合并栏一致）。
  static const double surfaceAlpha = 0.72;

  /// backdrop 模糊半径（与首页合并栏一致；消息中心旧值 16 偏弱）。
  static const double blurSigma = 20;

  /// 半透明底色的**单一来源**：主题 `surface` 叠加 [surfaceAlpha]。
  ///
  /// 容器上色与本页前景色对比度解析（`resolveAccessibleContainerColors`）
  /// 共用，避免两处各写一遍 `surface.withValues(alpha: 0.72)` 而再次漂移。
  static Color barColor(Color surface) =>
      surface.withValues(alpha: surfaceAlpha);

  /// 容器内容（须自带尺寸；顶栏内容由调用方决定）。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final barColor = AppTopBarSurface.barColor(cs.surface);
    final radius = tokens.chrome.containerRadius;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Style.lg,
        vertical: Style.sm,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: BorderRadius.circular(radius),
              // α0 描边：保留 0.5px 占位（与首页一致），视觉上不画线。
              border: Border.all(
                color: cs.outline.withValues(alpha: 0),
                width: 0.5,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}