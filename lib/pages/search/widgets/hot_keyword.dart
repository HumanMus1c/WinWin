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
  const HotKeywordGrid({
    super.key,
    required this.list,
    required this.onTap,
    this.placeholder = false,
  });

  final List<SearchTrendingItemModel> list;

  /// 点某个关键词的回调（回传关键词原文）。
  final ValueChanged<String> onTap;

  /// 占位（骨架）模式：格子仍走**同一套布局**（同 Wrap、同 [cellPadding]、同名称
  /// 行盒），只把名称文字透明化并在其上覆盖骨架块。
  ///
  /// 这是「骨架与真身逐像素等高」的**唯一可靠做法**：文本行盒受字体/DPR/textScaler
  /// 影响并有**整像素取整**（14×1.2=16.8 实际渲染为 17.0），手写常量对不准；由真实
  /// `Text` 撑行盒则天然对齐。详见
  /// `docs/搜索态扩充动效与合并栏阴影复盘-2026-10-21.md` §八。
  final bool placeholder;

  /// 行间距（上游 5）。
  static const double rowSpacing = 5;

  /// 列间距（上游 0.4）。
  static const double columnSpacing = 0.4;

  /// 单元格内边距的**唯一口径**（真实格与占位格共用）。
  static const EdgeInsets cellPadding =
      EdgeInsets.only(left: 2, right: 10, top: 5, bottom: 5);

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
                  placeholder: placeholder,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 占位名（仅用于撑起行盒，视觉被骨架块覆盖）。
const String kHotKeywordPlaceholder = '热搜关键词';

/// 热搜骨架 = [HotKeywordGrid] 的**占位模式**（同一套布局），高度与真身
/// **逐像素一致**。
///
/// 为何不手写"等高常量"：文本行盒受字体 / DPR / textScaler 影响并有**整像素
/// 取整**（14×1.2=16.8 实渲为 17.0），手写常量对不准 ⇒ 换真身时子高度变化 ⇒
/// `RenderAnimatedSize` 从 0 重跑 ⇒ 顿挫（详见
/// `docs/搜索态扩充动效与合并栏阴影复盘-2026-10-21.md` §八）。
class HotKeywordSkeleton extends StatelessWidget {
  const HotKeywordSkeleton({super.key, this.itemCount = 20});

  /// 占位条目数——**应与真实列表条目数一致**（默认 20，即接口 limit），
  /// 否则行数不同、高度不等。调用方在已知真实条数时应传入真实条数。
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return HotKeywordGrid(
      list: List<SearchTrendingItemModel>.generate(
        itemCount,
        (i) => SearchTrendingItemModel(
          keyword: kHotKeywordPlaceholder,
          showName: kHotKeywordPlaceholder,
        ),
      ),
      onTap: (_) {},
      placeholder: true,
    );
  }
}

class _HotKeywordCell extends StatelessWidget {
  const _HotKeywordCell({
    required this.item,
    required this.onTap,
    required this.placeholder,
  });

  final SearchTrendingItemModel item;
  final VoidCallback onTap;

  /// 占位（骨架）模式：名称文字透明化 + 覆盖骨架块，行盒仍由真实 `Text` 撑起。
  final bool placeholder;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final name = item.displayName;
    final icon = item.icon;
    final reason = item.recommendReason;
    final nameStyle = TextStyle(fontSize: 14, height: 1.2, color: cs.onSurface);

    // 占位格：与真身**同一套布局**，只把名称透明化并盖上骨架块 —— 行盒由真实
    // `Text` 撑起（含字体/DPR/textScaler 与整像素取整），故高度逐像素一致。
    if (placeholder) {
      return Padding(
        padding: HotKeywordGrid.cellPadding,
        child: Row(
          children: [
            Flexible(
              child: Stack(
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: nameStyle.copyWith(color: const Color(0x00000000)),
                  ),
                  Positioned.fill(child: SkeletonBox()),
                ],
              ),
            ),
          ],
        ),
      );
    }

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
                  style: nameStyle,
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