import 'package:flutter/material.dart';

import 'package:winwin/theme/app_chrome.dart';
import 'package:winwin/theme/inherited_ui_style.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/theme/ui_style.dart';
import 'components/frosted_bottom_bar.dart';

/// 宽屏断点（≥ 此宽度启用侧边 [AppNavRail]，否则底部浮动栏）。
const double kRailBreakpoint = 900;

/// 主导航壳层 — PiliPlus 三槽位架构（sideBar / bottomNav / body）。
///
/// 宽屏（≥ [kRailBreakpoint]）显示左侧 [AppNavRail]；窄屏显示底部
/// [FrostedBottomBar]。底部栏支持滚动联动隐藏：内部用
/// [NotificationListener] 监听 body 滚动，超过阈值后用 [AnimatedSlide]
/// 滑出底部栏，停顿后滑回。
class MainLayout extends StatefulWidget {
  const MainLayout({
    super.key,
    required this.currentIndex,
    required this.onSelect,
    required this.body,
  });

  /// 当前选中的导航项索引（对应 [navDestinations]）。
  final int currentIndex;

  /// 切换导航项回调。
  final ValueChanged<int> onSelect;

  /// 主体内容（通常为 [IndexedStack]）。
  final Widget body;

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  /// 底部栏是否可见（滚动联动）。
  final ValueNotifier<bool> _bottomBarVisible = ValueNotifier<bool>(true);

  /// 上一次滚动偏移，用于判断方向。
  double _lastOffset = 0;

  @override
  void dispose() {
    _bottomBarVisible.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    if (!n.metrics.hasPixels) return false;
    final offset = n.metrics.pixels;
    final delta = offset - _lastOffset;
    // 仅在可滚动区域且偏移超过 12px 才触发，避免抖动。
    if (offset <= 0) {
      _bottomBarVisible.value = true;
    } else if (delta.abs() > 4) {
      // 向下滚 → 隐藏；向上滚 → 显示。
      _bottomBarVisible.value = delta < 0;
    }
    _lastOffset = offset;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= kRailBreakpoint;
        if (wide) {
          return Row(
            children: [
              AppNavRail(
                currentIndex: widget.currentIndex,
                onSelect: widget.onSelect,
              ),
              Expanded(child: widget.body),
            ],
          );
        }
        return Stack(
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: widget.body,
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ValueListenableBuilder<bool>(
                valueListenable: _bottomBarVisible,
                builder: (context, visible, child) =>
                    AnimatedSlide(
                  offset: visible ? Offset.zero : const Offset(0, 1.4),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: child,
                ),
                child: FrostedBottomBar(
                  currentIndex: widget.currentIndex,
                  onSelect: widget.onSelect,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 桌面侧边导航栏 — 宽屏启用。
///
/// 参照 PiliPlus 的 `NavigationRail` 定制：顶部留白、图标+文字纵向排列、
/// 选中态用强调色 pill 指示器（按 [AppChrome.pillRadius] 切换圆角）。
class AppNavRail extends StatelessWidget {
  const AppNavRail({
    super.key,
    required this.currentIndex,
    required this.onSelect,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final chrome = Theme.of(context).extension<AppChrome>() ?? AppChrome.material3;
    final style = InheritedUiStyle.of(context);
    final renderer = resolvePrimitiveRenderer(style);

    return SafeArea(
      child: Container(
        width: 84,
        padding: const EdgeInsets.symmetric(vertical: Style.md),
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(
            right: BorderSide(
              color: cs.outlineVariant.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: navDestinations.asMap().entries.map((entry) {
            final i = entry.key;
            final d = entry.value;
            final selected = i == currentIndex;
            final color = selected ? d.color : cs.onSurfaceVariant;
            return Expanded(
              child: GestureDetector(
                onTap: () => onSelect(i),
                behavior: HitTestBehavior.opaque,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: selected
                            ? d.color.withValues(alpha: renderer == PrimitiveRenderer.miuix ? 0.12 : 0.18)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(chrome.pillRadius),
                      ),
                      child: Icon(
                        selected ? d.filledIcon : d.outlinedIcon,
                        color: color,
                        size: 24,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      d.label,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
