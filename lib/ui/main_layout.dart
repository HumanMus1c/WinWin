import 'package:flutter_miuix/miuix.dart';
import 'package:material_ui/material_ui.dart';

import 'package:winwin/theme/inherited_ui_style.dart';
import 'package:winwin/theme/ui_style.dart';
import 'components/frosted_bottom_bar.dart';

/// 宽屏断点（≥ 此宽度启用侧边导航栏，否则底部浮动栏）。
const double kRailBreakpoint = 900;

/// 主导航壳层 — PiliPlus 三槽位架构（sideBar / bottomNav / body）。
///
/// 宽屏（≥ [kRailBreakpoint]）显示左侧导航栏：MD3 用 [NavigationRail]，
/// Miuix 用 flutter_miuix 的 [MiuixNavigationRail]（阶段3b 起替换原自绘
/// AppNavRail）；窄屏显示底部浮动栏（[FrostedBottomBar]；Miuix 侧保留自研
/// 毛玻璃外壳——flutter_miuix 的 FloatingNavigationBar 为 icon-only，
/// 无「图标+文字+逐项强调色」的对应物，见阶段3 复盘）。
/// 底部栏支持滚动联动隐藏：内部用 [NotificationListener] 监听 body 滚动，
/// 超过阈值后用 [AnimatedSlide] 滑出底部栏，停顿后滑回。
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
    final style = InheritedUiStyle.of(context);
    final renderer = resolvePrimitiveRenderer(style);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= kRailBreakpoint;
        return Row(
          children: [
            if (wide)
              renderer == PrimitiveRenderer.material3
                  ? _buildMaterial3Rail(context)
                  : _buildMiuixRail(context),
            Expanded(
              child: Stack(
                children: [
                  NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    child: widget.body,
                  ),
                  if (!wide && renderer == PrimitiveRenderer.material3)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: NavigationBar(
                        selectedIndex: widget.currentIndex,
                        onDestinationSelected: widget.onSelect,
                        destinations: navDestinations
                            .map(
                              (d) => NavigationDestination(
                                icon: NavDestinationIcon(destination: d, selected: false),
                                selectedIcon: NavDestinationIcon(destination: d, selected: true),
                                label: d.label,
                              ),
                            )
                            .toList(),
                      ),
                    )
                  else if (!wide)
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
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMaterial3Rail(BuildContext context) {
    return NavigationRail(
      selectedIndex: widget.currentIndex,
      onDestinationSelected: widget.onSelect,
      labelType: NavigationRailLabelType.all,
      groupAlignment: 0.0,
      destinations: navDestinations
          .map(
            (d) => NavigationRailDestination(
              icon: NavDestinationIcon(destination: d, selected: false),
              selectedIcon: NavDestinationIcon(destination: d, selected: true),
              label: Text(d.label),
            ),
          )
          .toList(),
    );
  }

  /// Miuix 宽屏侧栏（阶段3b）：flutter_miuix 原生固定紧凑 NavigationRail
  /// （80px 宽、图标 + 文字、squircle 选中指示）。原自绘 AppNavRail 的
  /// 逐项强调色由 Miuix 主题指示器取代（阶段3 复盘"已知差异"）。
  Widget _buildMiuixRail(BuildContext context) {
    return MiuixNavigationRail(
      children: navDestinations.asMap().entries.map((entry) {
        final index = entry.key;
        final destination = entry.value;
        final selected = index == widget.currentIndex;
        return MiuixNavigationRailItem(
          selected: selected,
          onPressed: () => widget.onSelect(index),
          icon: NavDestinationIcon(
            destination: destination,
            selected: selected,
            size: 24,
          ),
          label: destination.label,
        );
      }).toList(),
    );
  }
}
