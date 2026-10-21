import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/theme/app_colors.dart';
import 'package:winwin/theme/miuix_theme_bridge.dart' show kMiuixSurfaceAlpha;

/// Miuix 毛玻璃表面：`MiuixOverlayPanel` 与浮层横条共用的**材质单一来源**
/// （半透明底 × [kMiuixSurfaceAlpha] + backdrop 模糊 16 + 可选 1px 描边 + 圆角
/// 12 + 4px 下投影）。
///
/// 供**浮于滚动内容之上**的横条类控件复用（分类标签条、按钮行等），使滚动
/// 内容从其后经过时呈模糊；`MiuixOverlayPanel` 在此材质上再补标题行与内边距。
/// 内容由 [child] 决定（须自带尺寸）。
///
/// ## 边缘无渐变（本版核心修复）
///
/// `BackdropFilter` 的模糊核在**自身边界处会被夹断**（clamp），把面板外侧的
/// 亮/暗背景"拖"进可视区，形成约 3σ（σ=16 → ~48px）的**软边渐变**；因背景四边
/// 明暗不同，面板四条边观感遂不一致。本组件把模糊层向**外扩 [bleed]**（= 3σ，
/// 超出被 `ClipRRect` 裁剪的可见区），让这段渐变整体落在可见区之外，可视四条边
/// 变成清晰的硬边，同时保留面板内部的毛玻璃。实现见 [_edgeSafeFrost]。
///
/// ## 两种档位
///
/// - 面板档（默认 `borderRadius = 12`）：四边 1px 描边（`outline` 为 true 时）+
///   下投影。描边画在**裁剪层之外**（前景层），不被 `ClipRRect` 抗锯齿吞掉，
///   四边得到一条稳定、一致的细线。
/// - 全宽档（`borderRadius = 0`）：不画圆角与投影，仅底部 1px 描边（`outline`
///   为 true 时），用于通栏行（如页面顶部的按钮行），避免屏幕边缘出现多余圆角。
class MiuixFrostedSurface extends StatelessWidget {
  const MiuixFrostedSurface({
    super.key,
    required this.child,
    this.borderRadius = 12,
    this.blurSigma = 16,
    this.outline = true,
    this.shadow = true,
    this.color,
  });

  /// 表面内容（须自带尺寸：面板档由外部定宽高，全宽档建议 `SizedBox.expand`）。
  final Widget child;

  /// 圆角半径；传 0 取全宽档（无圆角/无投影，仅底部描边）。
  final double borderRadius;

  /// backdrop 模糊半径（默认 16，对齐 `MiuixOverlayPanel`）。
  final double blurSigma;

  /// 是否画 1px 描边（默认 true：面板档画四边、全宽档画底边）。
  ///
  /// 置 false 时只保留毛玻璃与投影，用于"容器细线多余"的场合（实机反馈：标签
  /// 条面板的上下细线观感不好）。
  final bool outline;

  /// 是否画面板档的 4px 下投影（默认 true）。
  ///
  /// 置 false 用于**背后是空白页底**的合并栏：面板自身投影画在 `BackdropFilter`
  /// **之前**、属其 backdrop，会被模糊核从下缘向内采样，在面板下缘糊出一条
  /// 「背景决定」的浸润带（实机反馈：分类栏下缘发散阴影、筛选项发虚看不清）。
  /// 首页合并栏（自绘毛玻璃、无投影）同口径。
  final bool shadow;

  /// 半透明底色；null = 沿用默认的**中性灰**（`0xFF262626`/`0xFFEAEAEA`）。
  ///
  /// 供**需要与页面主题面同源**的小尺寸毛玻璃（如壳层全局返回按钮）覆盖：
  /// 传 `AppTopBarSurface.barColor(cs.surface)` 即与「首页顶栏」同一底色口径，
  /// 同时复用本组件的**边缘无渐变**（bleed）实现——小圆按钮的模糊核大于按钮本体，
  /// 若不外扩搬运，四边会被夹断成一片软边渐变。
  final Color? color;

  /// 边缘模糊渐变的"搬运"距离：把模糊层外扩的像素量。
  ///
  /// 取值 3×[blurSigma]，覆盖模糊核在边界被夹断所形成的全部软边（≈3σ）宽度，
  /// 使渐变整体移出可视裁剪区。分档计算见 [bleedFor]。
  static double bleedFor(double blurSigma) => blurSigma * 3;

  /// 浮层 1px 描边的**单一来源**（毛玻璃面板 [MiuixOverlayPanel] 与弹层菜单
  /// `MiuixPopupMenu` 共用），保证两处弹层的边线口径一致。
  ///
  /// 对比度高于初版（0.12/0.08）：压在已与背景混合的半透明底上，需要更高
  /// alpha 才能定义一条稳定可见的边线。
  static Color outlineColor({required bool isDark}) => isDark
      ? AppColors.white.withValues(alpha: 0.18)
      : AppColors.black.withValues(alpha: 0.12);

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final isDark = tokens.isDark;
    final baseColor =
        color ?? (isDark ? const Color(0xFF262626) : const Color(0xFFEAEAEA));
    final outlineColor = MiuixFrostedSurface.outlineColor(isDark: isDark);
    final isFullBleed = borderRadius <= 0;
    final radius = BorderRadius.circular(isFullBleed ? 0 : borderRadius);

    final frosted = _edgeSafeFrost(
      sigma: blurSigma,
      color: baseColor.withValues(alpha: kMiuixSurfaceAlpha),
      radius: radius,
      child: child,
    );

    if (isFullBleed) {
      // 全宽档：不画圆角与投影；仅底部 1px 描边（描边在裁剪层之外）。
      return DecoratedBox(
        decoration: BoxDecoration(
          border: outline ? Border(bottom: BorderSide(color: outlineColor)) : null,
        ),
        child: frosted,
      );
    }

    // 面板档的 4px 下投影 = 既定设计（浮层需要下投影）。注意：该投影画在
    // `BackdropFilter` **之前**、属其 backdrop，会被模糊核从下缘向内采样，故
    // 背后是空白页底的合并栏可传 `shadow: false` 关掉（见 [shadow] 说明）。
    final shadows = <BoxShadow>[
      BoxShadow(
        color: AppColors.black.withValues(alpha: isDark ? 0.35 : 0.15),
        blurRadius: 16,
        offset: const Offset(0, 4),
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: shadow ? shadows : null,
      ),
      // 描边画在裁剪层之外（前景层）：不被 ClipRRect 抗锯齿吞掉，也不与
      // BackdropFilter 的模糊渐变混在一起 → 四条边一致、清晰。
      foregroundDecoration: outline
          ? BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: outlineColor),
            )
          : null,
      child: frosted,
    );
  }

  /// 构建"边缘无渐变"的毛玻璃层：`ClipRRect` 负责可见裁剪，内部 `Stack` 把
  /// `BackdropFilter` 四向 **[bleed]** 外扩，使模糊核的边界夹断渐变落在裁剪区
  /// 之外；[child] 为非定位子，决定 Stack 尺寸（= 可见面板尺寸）。
  Widget _edgeSafeFrost({
    required double sigma,
    required Color color,
    required BorderRadius radius,
    required Widget child,
  }) {
    final bleed = bleedFor(sigma);
    return ClipRRect(
      borderRadius: radius,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -bleed,
            top: -bleed,
            right: -bleed,
            bottom: -bleed,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: ColoredBox(color: color),
            ),
          ),
          child,
        ],
      ),
    );
  }
}