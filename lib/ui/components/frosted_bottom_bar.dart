import 'dart:ui';
import 'package:flutter/material.dart';

import 'package:winwin/theme/app_chrome.dart';
import 'package:winwin/theme/app_shapes.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/inherited_ui_style.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/theme/ui_style.dart';

/// 顶层导航页面枚举。
enum AppPage { home, dynamic, history, listenVideo, profile }

/// 导航项配置 — 图标 / 标签 / 强调色。
///
/// 供 [FrostedBottomBar] 与桌面侧边栏共用，保证两端导航项一致。
class NavDestination {
  final AppPage page;
  final String label;
  final IconData outlinedIcon;
  final IconData filledIcon;
  final Color color;

  const NavDestination(
    this.page,
    this.label,
    this.outlinedIcon,
    this.filledIcon,
    this.color,
  );
}

/// 默认导航项顺序（可后续接入 [SettingBoxKey.navBarSort] 用户重排）。
const List<NavDestination> navDestinations = [
  NavDestination(AppPage.home, '首页', Icons.home_outlined, Icons.home, iosBlue),
  NavDestination(AppPage.dynamic, '动态', Icons.notifications_outlined, Icons.notifications, iosOrange),
  NavDestination(AppPage.history, '历史', Icons.history_outlined, Icons.history, iosTeal),
  NavDestination(AppPage.listenVideo, '听视频', Icons.headphones_outlined, Icons.headphones, iosPink),
  NavDestination(AppPage.profile, '我的', Icons.person_outlined, Icons.person, iosGreen),
];

/// 浮动底部导航栏 — 毛玻璃胶囊 + 自适应圆角/阴影。
///
/// 参照 BiliPai 的 `FrostedBottomBar`（简化），形状与阴影按 [UiStyle]
/// 解析：iOS 连续曲率 + 扩散阴影，MD3 tonal elevation，Miuix 扁平 0 阴影。
/// 由 [MainLayout] 通过 [AnimatedSlide] 控制滚动联动显隐。
class FrostedBottomBar extends StatelessWidget {
  const FrostedBottomBar({
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
    final shapes = Theme.of(context).extension<AppShapes>() ?? AppShapes.ios;
    final chrome = Theme.of(context).extension<AppChrome>() ?? AppChrome.ios;
    final style = InheritedUiStyle.of(context);
    final renderer = resolvePrimitiveRenderer(style);

    final radius = switch (renderer) {
      PrimitiveRenderer.ios => Style.radiusFloating,
      PrimitiveRenderer.material3 => chrome.containerRadius,
      PrimitiveRenderer.miuix => chrome.containerRadius,
    };

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: Style.lg, vertical: Style.lg),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: Style.bottomBarHeight,
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(
                  color: cs.outline.withValues(alpha: renderer == PrimitiveRenderer.miuix ? 0 : 0.1),
                  width: 0.5,
                ),
                boxShadow: renderer == PrimitiveRenderer.miuix
                    ? const []
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Row(
                children: navDestinations.asMap().entries.map((entry) {
                  final selected = entry.key == currentIndex;
                  return Expanded(
                    child: _NavButton(
                      destination: entry.value,
                      selected: selected,
                      onTap: () => onSelect(entry.key),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  const _NavButton({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected ? destination.color : theme.colorScheme.onSurfaceVariant;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            selected ? destination.filledIcon : destination.outlinedIcon,
            color: color,
            size: 24,
          ),
          const SizedBox(height: 2),
          Text(
            destination.label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
