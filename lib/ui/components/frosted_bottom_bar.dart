import 'dart:ui';
import 'package:flutter/material.dart';
import '../../theme/colors.dart';
import '../../theme/style.dart';

enum AppPage { home, dynamic, history, listenVideo, profile }

/// Frosted bottom navigation bar — floating pill shape with BackdropFilter blur.
/// Ported from BiliPai's FrostedBottomBar (simplified).
class FrostedBottomBar extends StatelessWidget {
  final AppPage currentPage;
  final ValueChanged<AppPage> onNavigate;

  const FrostedBottomBar({
    super.key,
    required this.currentPage,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = [
      _NavItem(AppPage.home, '首页', Icons.home_outlined, Icons.home, bottomBarColors[0]),
      _NavItem(AppPage.dynamic, '动态', Icons.notifications_outlined, Icons.notifications, bottomBarColors[1]),
      _NavItem(AppPage.history, '历史', Icons.history_outlined, Icons.history, bottomBarColors[2]),
      _NavItem(AppPage.listenVideo, '听视频', Icons.headphones_outlined, Icons.headphones, bottomBarColors[3]),
      _NavItem(AppPage.profile, '我的', Icons.person_outlined, Icons.person, bottomBarColors[4]),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Style.lg, vertical: Style.lg),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Style.radiusFloating),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: Style.bottomBarHeight,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withOpacity(0.72),
                borderRadius: BorderRadius.circular(Style.radiusFloating),
                border: Border.all(
                  color: theme.colorScheme.outline.withOpacity(0.1),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: items.map((item) {
                  final isSelected = currentPage == item.page;
                  return Expanded(
                    child: _NavButton(
                      item: item,
                      isSelected: isSelected,
                      onTap: () => onNavigate(item.page),
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

class _NavItem {
  final AppPage page;
  final String label;
  final IconData unselectedIcon;
  final IconData selectedIcon;
  final Color color;

  const _NavItem(this.page, this.label, this.unselectedIcon, this.selectedIcon, this.color);
}

class _NavButton extends StatelessWidget {
  final _NavItem item;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isSelected ? item.color : theme.colorScheme.onSurfaceVariant;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isSelected ? item.selectedIcon : item.unselectedIcon,
            color: color,
            size: 24,
          ),
          const SizedBox(height: 2),
          Text(
            item.label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
