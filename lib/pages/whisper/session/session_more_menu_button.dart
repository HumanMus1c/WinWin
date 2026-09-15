import 'package:flutter/material.dart';

import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/inherited_ui_style.dart';
import 'package:winwin/theme/ui_style.dart';

/// 会话列表项右侧的现代化更多操作菜单按钮。
///
/// 替代老旧的 [PopupMenuButton]，基于 Flutter 官方 Material 3 的 [MenuAnchor] 与
/// [MenuItemButton] 构建，并随 [UiStyle] 自动适配 M3 悬浮菜单或 Miuix 风格。
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
    final theme = Theme.of(context);
    final style = InheritedUiStyle.of(context);
    final isMiuix = style == UiStyle.miuix;

    return MenuAnchor(
      alignmentOffset: const Offset(-100, 0),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(
          isMiuix
              ? theme.colorScheme.surface.withValues(alpha: 0.95)
              : theme.colorScheme.surfaceContainer,
        ),
        elevation: WidgetStatePropertyAll(isMiuix ? 2 : 3),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(isMiuix ? 14 : 12),
            side: isMiuix
                ? BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                  )
                : BorderSide.none,
          ),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        ),
      ),
      builder: (context, controller, child) {
        return IconButton(
          icon: Icon(
            AppIcons.moreOptions(context),
            size: 20,
            color: theme.colorScheme.outline,
          ),
          tooltip: '更多选项',
          splashRadius: 18,
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
        );
      },
      menuChildren: [
        MenuItemButton(
          leadingIcon: Icon(
            AppIcons.pin(context, active: isPinned),
            size: 18,
            color: isPinned ? theme.colorScheme.primary : null,
          ),
          onPressed: onToggleTop,
          child: Text(isPinned ? '取消置顶' : '置顶会话'),
        ),
        MenuItemButton(
          leadingIcon: Icon(
            AppIcons.notificationsOff(context, active: isDnd),
            size: 18,
            color: isDnd ? theme.colorScheme.primary : null,
          ),
          onPressed: onToggleDnd,
          child: Text(isDnd ? '关闭免打扰' : '开启免打扰'),
        ),
        const Divider(height: 1, indent: 8, endIndent: 8),
        MenuItemButton(
          leadingIcon: Icon(
            AppIcons.delete(context),
            size: 18,
            color: theme.colorScheme.error,
          ),
          onPressed: onRemove,
          child: Text(
            '删除会话',
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      ],
    );
  }
}
