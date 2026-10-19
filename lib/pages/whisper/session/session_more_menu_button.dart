import 'package:flutter_miuix/miuix.dart';
import 'package:flutter/widgets.dart';

import 'package:winwin/common/widgets/miuix_context_menu.dart';
import 'package:winwin/common/widgets/miuix_popup_menu.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/ui/components/app_tooltip.dart';
import 'package:winwin/ui/components/hover_container.dart';

/// 构建会话「更多选项」动作列表（三点菜单与右键菜单共用）。
///
/// 图标不设显式尺寸：弹层壳/右键浮层统一按行文本尺寸驱动，
/// 保证与选项文本大小一致。
List<ContextMenuAction> buildSessionMenuActions({
  required BuildContext context,
  required bool isPinned,
  required bool isDnd,
  required VoidCallback onToggleTop,
  required VoidCallback onToggleDnd,
  required VoidCallback onRemove,
}) {
  final cs = AppThemeHost.of(context).colors;
  return [
    ContextMenuAction(
      title: isPinned ? '取消置顶' : '置顶会话',
      icon: AppIcon(
        AppIcons.pin(active: isPinned),
        color: isPinned ? cs.primary : null,
      ),
      onTap: onToggleTop,
    ),
    ContextMenuAction(
      title: isDnd ? '关闭免打扰' : '开启免打扰',
      icon: AppIcon(
        AppIcons.notificationsOff(active: isDnd),
        color: isDnd ? cs.primary : null,
      ),
      onTap: onToggleDnd,
    ),
    ContextMenuAction(
      title: '删除会话',
      icon: AppIcon(AppIcons.delete(), color: cs.error),
      onTap: onRemove,
    ),
  ];
}

/// 会话列表项右侧的现代化更多操作菜单按钮。
///
/// - 弹层壳为自研 [MiuixPopupMenu]（阶段4h 起替代上游组件）；
/// - 菜单项文本颜色保持统一内容色，「删除会话」以红色图标区分
///   （见阶段3 复盘"已知差异"）；
/// - 图标经 [AppIcon] 分发为 Miuix 矢量，尺寸随行文本（不再硬编码 18）；
/// - 动作列表由 [buildSessionMenuActions] 构建，与右键菜单共用。
class SessionMoreMenuButton extends StatelessWidget {
  const SessionMoreMenuButton({
    super.key,
    required this.isPinned,
    required this.isDnd,
    required this.onToggleTop,
    required this.onToggleDnd,
    required this.onRemove,
  });

  final bool isPinned;
  final bool isDnd;
  final VoidCallback onToggleTop;
  final VoidCallback onToggleDnd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final actions = buildSessionMenuActions(
      context: context,
      isPinned: isPinned,
      isDnd: isDnd,
      onToggleTop: onToggleTop,
      onToggleDnd: onToggleDnd,
      onRemove: onRemove,
    );
    // 阶段5d-L1：M3 冻结分支已移除，弹层壳为唯一实现。
    return MiuixPopupMenu(
        title: '更多选项',
        entries: [
          MiuixDropdownEntry(
            items: [
              MiuixDropdownItem(
                text: actions[0].title,
                icon: actions[0].icon,
                onClick: actions[0].onTap,
              ),
              MiuixDropdownItem(
                text: actions[1].title,
                icon: actions[1].icon,
                onClick: actions[1].onTap,
              ),
            ],
          ),
          MiuixDropdownEntry(
            items: [
              MiuixDropdownItem(
                text: actions[2].title,
                icon: actions[2].icon,
                onClick: actions[2].onTap,
              ),
            ],
          ),
        ],
        child: Padding(
          // 与左侧时间标记留出安全间距，避免长文本（"XX天前"）贴到按钮。
          padding: const EdgeInsets.only(left: Style.sm),
          child: HoverContainer(
            borderRadius: Style.radiusSm,
            padding: const EdgeInsets.all(Style.xs),
            child: AppTooltip(
              message: '更多选项',
              child: AppIcon(
                AppIcons.moreOptions(),
                size: 20,
                color: tokens.colors.outline,
              ),
            ),
          ),
        ),
      );
  }
}
