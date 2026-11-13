import 'package:flutter/widgets.dart';

import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/ui/components/app_progress.dart';

/// 列表底部「加载更多」槽位：**高度恒定**，只换内容。
///
/// 为什么必须恒高（2026-11-13 滚动体验轮）：此前各列表的 footer 是
/// 「转圈（约 56px）↔ 没有更多（约 49px）↔ SizedBox.shrink（0px）」三态切换。
/// 用户贴在底部时，footer 缩短会让 `maxScrollExtent` 变小，滚动位置被回弹/
/// 夹紧 —— 表现就是「滚动加载时整页上下抖一下」。固定槽位后内容尺寸不再随
/// 加载状态变化，新批次只会在槽位之后向下延展，观感无跳变。
///
/// 三种视觉态：
/// - [loading] 为真：转圈（高度不变）；
/// - [loading] 为假且 [hasMore] 为假：`没有更多了`（高度不变）；
/// - 其余：空白占位（高度不变）。
class ListLoadFooter extends StatelessWidget {
  const ListLoadFooter({
    super.key,
    required this.loading,
    required this.hasMore,
    this.height = defaultHeight,
    this.textColor,
    this.errorText,
    this.onRetry,
  });

  /// 槽位高度（高于转圈直径 + 上下余量，与各列表原观感一致）。
  static const double defaultHeight = 56;

  final bool loading;
  final bool hasMore;
  final double height;
  final Color? textColor;

  /// 错误态文案（可空）：非空时显示可点击重试，仍保持恒高。
  final String? errorText;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final color = textColor ?? AppThemeHost.of(context).colors.outline;
    Widget child;
    if (loading) {
      child = const SizedBox(
        width: 24,
        height: 24,
        child: AppProgressIndicator(strokeWidth: 2),
      );
    } else if (errorText != null && onRetry != null) {
      child = _FooterRetry(text: errorText!, onRetry: onRetry!, color: color);
    } else if (!hasMore) {
      child = Text(
        '没有更多了',
        style: TextStyle(fontSize: 12, color: color),
      );
    } else {
      child = const SizedBox.shrink();
    }

    return SizedBox(
      height: height,
      child: Center(child: child),
    );
  }
}

/// 底部错误重试：保持与文本态同样的视觉密度（不额外增加高度）。
class _FooterRetry extends StatelessWidget {
  const _FooterRetry({
    required this.text,
    required this.onRetry,
    required this.color,
  });

  final String text;
  final VoidCallback onRetry;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onRetry,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          text,
          style: TextStyle(fontSize: 12, color: color),
        ),
      ),
    );
  }
}
