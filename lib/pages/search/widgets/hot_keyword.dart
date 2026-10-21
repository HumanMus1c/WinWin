import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart'
    show MiuixPressable, MiuixPressFeedbackType;

import 'package:winwin/common/skeleton/skeleton.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/models/search/result.dart';
import 'package:winwin/ui/components/app_tooltip.dart';

/// 两列网格热搜（对齐上游 PiliPlus `_HotKeywordGrid` 的新排版）。
///
/// 移植自 `PiliPlus/lib/pages/search/widgets/hot_keyword.dart`，按本项目口径
/// **去 Material 化**：`InkWell` → [MiuixPressable]，颜色全部取
/// [AppThemeHost] tokens（应用侧零 `material_ui` 消费）。
///
/// 排版口径（与上游一致）：
/// - 两列网格：列间距 [columnSpacing] 0.4，行间距 [rowSpacing] 5；
/// - **不显示 1/2/3 序号**；
/// - 每格 = 名字（14 号，超出省略）+ 至多一个后缀，按优先级：
///   小图标（高 15）→ 直播小标 → 推荐理由（灰色小字）。
class HotKeywordGrid extends StatelessWidget {
  const HotKeywordGrid({super.key, required this.list, required this.onTap});

  final List<SearchTrendingItemModel> list;

  /// 点某个关键词的回调（回传关键词原文）。
  final ValueChanged<String> onTap;

  /// 行间距（上游 5）。
  static const double rowSpacing = 5;

  /// 列间距（上游 0.4）。
  static const double columnSpacing = 0.4;

  /// 单元格内边距的**唯一口径**（真实格与 [HotKeywordSkeleton] 共用）：
  /// 只有两边同源，"加载中"与"已加载"才能逐像素等高。
  static const EdgeInsets cellPadding =
      EdgeInsets.only(left: 2, right: 10, top: 5, bottom: 5);

  /// 名称行高（fontSize 14 × line-height 1.2）= 单元格文本高度唯一口径。
  static const double cellLineHeight = 14 * 1.2;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 两列均分：保证「左右两格 + 一个列间距」正好铺满可用宽度。
        final cellWidth = (constraints.maxWidth - columnSpacing) / 2;
        return Wrap(
          spacing: columnSpacing,
          runSpacing: rowSpacing,
          children: [
            for (final item in list)
              SizedBox(
                width: cellWidth,
                child: _HotKeywordCell(
                  item: item,
                  onTap: () => onTap(item.keyword ?? ''),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 与 [HotKeywordGrid] **同几何**的骨架：同列/行间距、同单元格留白、同名称行高。
///
/// 目的：让"加载中"与"已加载"的**高度逐像素相等**——搜索态展开动画期间面板
/// 内在高度一旦跳变，`RenderAnimatedSize` 会把尺寸动画从 0 重跑（顿挫根因）；
/// 等高后跳变消失，动画目标自始至终稳定。
class HotKeywordSkeleton extends StatelessWidget {
  const HotKeywordSkeleton({super.key, this.itemCount = 20});

  /// 占位条目数——**应与真实列表条目数一致**（默认 20，即接口 limit），
  /// 否则行数不同、高度不等。调用方在已知真实条数时应传入真实条数。
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth =
            (constraints.maxWidth - HotKeywordGrid.columnSpacing) / 2;
        return Wrap(
          spacing: HotKeywordGrid.columnSpacing,
          runSpacing: HotKeywordGrid.rowSpacing,
          children: [
            for (var i = 0; i < itemCount; i++)
              SizedBox(
                width: cellWidth,
                child: const Padding(
                  padding: HotKeywordGrid.cellPadding,
                  child: SkeletonLine(height: HotKeywordGrid.cellLineHeight),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _HotKeywordCell extends StatelessWidget {
  const _HotKeywordCell({required this.item, required this.onTap});

  final SearchTrendingItemModel item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final name = item.displayName;
    final icon = item.icon;
    final reason = item.recommendReason;

    // 后缀优先级（与上游一致）：图标 → 直播标 → 推荐理由。
    Widget? trailing;
    if (icon != null && icon.isNotEmpty) {
      trailing = Padding(
        padding: const EdgeInsets.only(left: 4),
        child: CachedNetworkImage(
          imageUrl: icon,
          height: 15,
          fit: BoxFit.contain,
          memCacheHeight: (MediaQuery.devicePixelRatioOf(context) * 15).round(),
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      );
    } else if (item.showLiveIcon == true) {
      trailing = const Padding(
        padding: EdgeInsets.only(left: 4),
        child: _LiveTag(),
      );
    } else if (reason != null && reason.isNotEmpty) {
      trailing = Flexible(
        child: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            reason,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, height: 1.2, color: cs.outline),
          ),
        ),
      );
    }

    return MiuixPressable(
      feedbackType: MiuixPressFeedbackType.sink,
      sinkAmount: 0.98,
      borderRadius: BorderRadius.circular(3),
      onPressed: onTap,
      child: Padding(
        padding: HotKeywordGrid.cellPadding,
        child: AppTooltip(
          message: name,
          child: Row(
            children: [
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.2,
                    color: cs.onSurface,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// 直播小标（上游用的是 `Assets.livingRect` 位图 48×15；本项目无该资源，
/// 以同语义文字标替代，避免新增二进制资源）。
class _LiveTag extends StatelessWidget {
  const _LiveTag();

  @override
  Widget build(BuildContext context) {
    final cs = AppThemeHost.of(context).colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.5),
          width: 0.5,
        ),
      ),
      child: Text(
        '直播',
        style: TextStyle(fontSize: 10, height: 1.1, color: cs.primary),
      ),
    );
  }
}