import 'package:material_ui/material_ui.dart';

import 'package:winwin/theme/app_colors.dart';
import 'package:winwin/theme/app_chrome.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
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
        return Row(
          children: [
            if (wide)
              AppNavRail(
                currentIndex: widget.currentIndex,
                onSelect: widget.onSelect,
              ),
            Expanded(
              child: Stack(
                children: [
                  NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    child: widget.body,
                  ),
                  // 阶段5d-L3：M3 底栏分支已移除，毛玻璃浮动底栏恒用。
                  if (!wide)
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
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final chrome = AppThemeHost.of(context).chrome;

    return SafeArea(
      child: Container(
        width: 80,
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(
            right: BorderSide(
              color: cs.outlineVariant.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: navDestinations.asMap().entries.map((entry) {
              final i = entry.key;
              final d = entry.value;
              final selected = i == currentIndex;
              final color = selected ? d.color : cs.onSurfaceVariant;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: InkResponse(
                  onTap: () => onSelect(i),
                  radius: 28,
                  child: SizedBox(
                    width: 64,
                    height: 56,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 4),
                          decoration: BoxDecoration(
                            // 阶段5d-L1：选中底衬恒为 Miuix 值。
                            color: selected
                                ? d.color.withValues(alpha: 0.12)
                                : AppColors.transparent,
                            borderRadius: BorderRadius.circular(chrome.pillRadius),
                          ),
                          child: NavDestinationIcon(
                            destination: d,
                            selected: selected,
                            size: 24,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          d.label,
                          style: TextStyle(
                            color: color,
                            fontSize: 11,
                            // 固定行高：中文字体默认行高较大（≈2.0×），会使
                            // 56px 导航项底部溢出 2px，并随字体/风格切换漂移。
                            height: 1.25,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
