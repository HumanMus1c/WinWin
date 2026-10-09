import 'package:flutter_miuix/miuix.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:winwin/theme/app_colors.dart';
import 'package:winwin/core/account/account_service.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/services/msg_unread_service.dart';
import 'package:winwin/theme/colors.dart';

import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/utils/image_utils.dart';
import 'package:winwin/core/shell/app_theme_host.dart';

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
  IconData icon({bool selected = false}) => switch (page) {
        AppPage.home => AppIcons.home(selected: selected),
        AppPage.dynamic => AppIcons.dynamic(selected: selected),
        AppPage.history => AppIcons.history(selected: selected),
        AppPage.whisper => AppIcons.whisper(selected: selected),
        AppPage.profile => AppIcons.profile(selected: selected),
      };

  IconData get outlinedIcon => icon(selected: false);
  IconData get filledIcon => icon(selected: true);
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
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final color = selected ? destination.color : cs.onSurfaceVariant;
    final iconData = destination.icon(selected: selected);

    if (destination.page == AppPage.profile) {
      return ListenableBuilder(
        listenable: AccountService(),
        builder: (context, _) {
          final account = AccountService();
          // 演示模式下头像走程序默认图标（displayUserInfo.face 已置空）。
          final face = account.displayUserInfo?.face ?? '';
          if (account.isLogin && face.isNotEmpty) {
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
                  imageUrl: ImageUtils.thumbnailUrl(face, type: 'avatar'),
                  fit: BoxFit.cover,
                  memCacheWidth: ImageUtils.decodeClamp(size, context, max: 256),
                  memCacheHeight: ImageUtils.decodeClamp(size, context, max: 256),
                  placeholder: (_, _) => const ColoredBox(
                    color: AppColors.grey,
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
      return ListenableBuilder(
        listenable: Listenable.merge([MsgUnreadService(), Pref.demoModeNotifier]),
        builder: (context, _) {
          // 演示模式：不显示未读角标（账号数据脱敏）。
          if (Pref.demoMode) return baseIcon;
          final unreadCount = MsgUnreadService().totalInteractiveUnread;
          final label = unreadCount > 99 ? '99+' : unreadCount.toString();

          // 阶段5d-L1：M3 分支已移除；原生 BadgedBox + Badge（error 容器 /
          // onError 内容色取自桥接主题）。
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
        },
      );
    }

    return baseIcon;
  }
}

/// 浮动底部导航栏 — 毛玻璃胶囊 + 自适应圆角/阴影。
///
/// 参照 BiliPai 的 `FrostedBottomBar`（简化），状状与阴影按 [UiStyle]
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
    // 阶段5d-L1：M3 冻结分支（毛玻璃外壳）已移除，浮动导航栏为唯一实现。
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
}

