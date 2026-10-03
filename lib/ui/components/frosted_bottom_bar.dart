import 'dart:ui';
import 'package:flutter_miuix/miuix.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:winwin/core/account/account_service.dart';
import 'package:winwin/services/msg_unread_service.dart';
import 'package:winwin/theme/app_chrome.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/inherited_ui_style.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/theme/ui_style.dart';

import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/utils/image_utils.dart';

/// 顶层导航页面枚举。
enum AppPage { home, dynamic, history, whisper, profile }

/// 导航项配置 — 图标 / 标签 / 强调色。
///
/// 供 [FrostedBottomBar] 与桌面侧边栏共用，保证两端导航项一致。
class NavDestination {
  final AppPage page;
  final String label;
  final Color color;

  const NavDestination(
    this.page,
    this.label,
    this.color,
  );

  /// 依据 [UiStyle] 动态分发 M3 与 Miuix 图标
  IconData icon(UiStyle style, {bool selected = false}) => switch (page) {
        AppPage.home => AppIcons.homeOf(style, selected: selected),
        AppPage.dynamic => AppIcons.dynamicOf(style, selected: selected),
        AppPage.history => AppIcons.historyOf(style, selected: selected),
        AppPage.whisper => AppIcons.whisperOf(style, selected: selected),
        AppPage.profile => AppIcons.profileOf(style, selected: selected),
      };

  IconData get outlinedIcon => icon(UiStyle.material3, selected: false);
  IconData get filledIcon => icon(UiStyle.material3, selected: true);
}

/// 默认导航项顺序（可后续接入 [SettingBoxKey.navBarSort] 用户重排）。
const List<NavDestination> navDestinations = [
  NavDestination(AppPage.home, '首页', iosBlue),
  NavDestination(AppPage.dynamic, '动态', iosOrange),
  NavDestination(AppPage.history, '历史', iosTeal),
  NavDestination(AppPage.whisper, '消息', iosPink),
  NavDestination(AppPage.profile, '我的', iosGreen),
];

/// 导航项自适应图标：
/// 1. 「我的」页面在登录状态下展示用户头像，未登录展示默认图标；
/// 2. 「消息」页面在有四类互动未读消息时展示红底未读角标气泡。
class NavDestinationIcon extends StatelessWidget {
  final NavDestination destination;
  final bool selected;
  final double size;

  const NavDestinationIcon({
    super.key,
    required this.destination,
    required this.selected,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final style = InheritedUiStyle.of(context);
    final color = selected ? destination.color : cs.onSurfaceVariant;
    final iconData = destination.icon(style, selected: selected);

    if (destination.page == AppPage.profile) {
      return ListenableBuilder(
        listenable: AccountService(),
        builder: (context, _) {
          final account = AccountService();
          if (account.isLogin && account.face.isNotEmpty) {
            return Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? destination.color : cs.outlineVariant.withValues(alpha: 0.5),
                  width: selected ? 2 : 1,
                ),
              ),
              child: ClipOval(
                child: CachedNetworkImage(
                  imageUrl: ImageUtils.thumbnailUrl(account.face, type: 'avatar'),
                  fit: BoxFit.cover,
                  memCacheWidth: ImageUtils.decodeClamp(size, context, max: 256),
                  memCacheHeight: ImageUtils.decodeClamp(size, context, max: 256),
                  placeholder: (_, _) => const ColoredBox(
                    color: Colors.grey,
                    child: SizedBox.expand(),
                  ),
                  errorBuilder: (_, _, _) => Icon(
                    iconData,
                    color: color,
                    size: size - 4,
                  ),
                ),
              ),
            );
          }
          return Icon(
            iconData,
            color: color,
            size: size,
          );
        },
      );
    }

    final Widget baseIcon = Icon(
      iconData,
      color: color,
      size: size,
    );

    if (destination.page == AppPage.whisper) {
      final isMiuix = style == UiStyle.miuix;
      return ListenableBuilder(
        listenable: MsgUnreadService(),
        builder: (context, _) {
          final unreadCount = MsgUnreadService().totalInteractiveUnread;
          final label = unreadCount > 99 ? '99+' : unreadCount.toString();

          // Miuix 分支（阶段3b）：原生 BadgedBox + Badge（error 容器 /
          // onError 内容色取自桥接主题）。
          if (isMiuix) {
            if (unreadCount <= 0) return baseIcon;
            return MiuixBadgedBox(
              badge: MiuixBadge(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: cs.onError,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              child: baseIcon,
            );
          }

          return Badge(
            isLabelVisible: unreadCount > 0,
            label: Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: cs.error,
            child: baseIcon,
          );
        },
      );
    }

    return baseIcon;
  }
}

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
    final chrome = Theme.of(context).extension<AppChrome>() ?? AppChrome.material3;
    final style = InheritedUiStyle.of(context);
    final renderer = resolvePrimitiveRenderer(style);

    final radius = chrome.containerRadius;

    // Miuix 分支（阶段4b）：外壳替换为 flutter_miuix 浮动导航栏（squircle 胶囊 +
    // 原生按压/选中态）。逐项彩色图标保留：_FloatingIconBadge 走 IconTheme
    // 继承（非 ColorFilter 强制着色，经源码核对），显式色标的图标不受影响。
    // 毛玻璃外壳仅保留在 M3 分支。
    if (style == UiStyle.miuix) {
      return MiuixFloatingNavigationBar(
        children: [
          for (var i = 0; i < navDestinations.length; i++)
            MiuixFloatingNavigationBarItem(
              label: navDestinations[i].label,
              selected: i == currentIndex,
              onPressed: () => onSelect(i),
              icon: NavDestinationIcon(
                destination: navDestinations[i],
                selected: i == currentIndex,
                size: 24,
              ),
            ),
        ],
      );
    }

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
          NavDestinationIcon(
            destination: destination,
            selected: selected,
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
