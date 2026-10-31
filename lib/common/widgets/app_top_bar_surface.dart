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
  const AppTopBarSurface({
    super.key,
    required this.child,
    this.shadow = const <BoxShadow>[],
  });

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

  /// 合并栏外投影（**默认无**，零影响：消息中心沿用原观感）。
  ///
  /// 传空列表 = 不投影（原行为）；传入时画在 [ClipRRect] **之外**、沿可见栏体
  /// 轮廓（`chrome.containerRadius`）向外辐射——即「整体悬浮四向辐射阴影」的
  /// 载体。动画（淡入/淡出的 lerp）由调用方（首页搜索态）负责，本组件只呈现
  /// 当前帧的阴影值（单一职责：材质）。
  final List<BoxShadow> shadow;

  /// 深色主题下的栏体**浅描边**不透明度（0 = 不画）。
  ///
  /// 深色页底（`miuixDarkBackground` `0xFF131316`）与栏体半透明底同源 ⇒ 两者
  /// 亮度几乎一致，投影又是黑色、在近黑底上不可见；没有描边时顶栏与后方内容
  /// 完全糊在一起（CVO 反馈「深色主题下看不见阴影、没有层次」）。深色下改用
  /// `outline` 浅灰细线定义轮廓（浅色页底栏体本身比页底亮，无需描边，保持 0）。
  static const double darkRimAlpha = 0.26;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final barColor = AppTopBarSurface.barColor(cs.surface);
    final radius = tokens.chrome.containerRadius;
    final borderRadius = BorderRadius.circular(radius);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Style.lg,
        vertical: Style.sm,
      ),
      // 投影层：贴在可见栏体外轮廓上（在 Padding **内侧**，避免阴影从留白外缘
      // 辐射而与栏体"脱开"）。@see shadow
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: shadow.isEmpty ? null : shadow,
        ),
        child: DecoratedBox(
          // 描边画在**前景层**：栏体内部是半透明底 + 背景模糊，若放在背景层
          // 会被上层的半透明填充盖住、只剩 ~28% 可见度；前景层保证四边一致。
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(
              color: cs.outline.withValues(
                alpha: tokens.isDark ? darkRimAlpha : 0,
              ),
              width: 0.5,
            ),
          ),
          child: ClipRRect(
            borderRadius: borderRadius,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
              child: Container(
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: borderRadius,
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}