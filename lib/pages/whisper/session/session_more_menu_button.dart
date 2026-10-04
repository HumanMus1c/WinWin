import 'package:flutter_miuix/miuix.dart';
import 'package:material_ui/material_ui.dart';

import 'package:winwin/common/widgets/miuix_popup_menu.dart';
import 'package:winwin/theme/app_icons.dart';

/// 会话列表项右侧的现代化更多操作菜单按钮。
///
/// - MD3：[MenuAnchor] + [MenuItemButton]（原实现保留）；
/// - Miuix：[MiuixWindowIconDropdownMenu]（阶段3a 起替换自绘 MenuStyle 近似，
///   获得原生菜单揭示动效与分组分隔线）。受上游 API 限制，菜单项文本颜色
///   无法逐项定制——「删除会话」保留红色图标，文本退化为默认内容色
///   （见阶段3 复盘"已知差异"）。
/// 图标经 [AppIcon] 分发：Miuix 风格下升级为 Miuix 矢量（阶段3c）。
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
    // 阶段5d-L1：M3 冻结分支已移除，弹层壳为唯一实现。
    return MiuixPopupMenu(
        title: '更多选项',
        entries: [
          MiuixDropdownEntry(
            items: [
              MiuixDropdownItem(
                text: isPinned ? '取消置顶' : '置顶会话',
                icon: AppIcon(
                  AppIcons.pin(context, active: isPinned),
                  size: 18,
                  color: isPinned ? theme.colorScheme.primary : null,
                ),
                onClick: onToggleTop,
              ),
              MiuixDropdownItem(
                text: isDnd ? '关闭免打扰' : '开启免打扰',
                icon: AppIcon(
                  AppIcons.notificationsOff(context, active: isDnd),
                  size: 18,
                  color: isDnd ? theme.colorScheme.primary : null,
                ),
                onClick: onToggleDnd,
              ),
            ],
          ),
          MiuixDropdownEntry(
            items: [
              MiuixDropdownItem(
                text: '删除会话',
                icon: AppIcon(
                  AppIcons.delete(context),
                  size: 18,
                  color: theme.colorScheme.error,
                ),
                onClick: onRemove,
              ),
            ],
          ),
        ],
        child: Tooltip(
          message: '更多选项',
          child: AppIcon(
            AppIcons.moreOptions(context),
            size: 20,
            color: theme.colorScheme.outline,
          ),
        ),
      );
  }
}
