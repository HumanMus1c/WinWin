import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_miuix/miuix.dart';
import 'package:material_ui/material_ui.dart';

import 'package:winwin/common/widgets/miuix_overlay_panel.dart';
import 'package:winwin/common/widgets/miuix_popup_menu.dart';
import 'package:winwin/core/input/escape_layer_registry.dart';
import 'package:winwin/theme/app_icons.dart';

/// 通用右键/坐标上下文菜单动作结构体（视频卡片、消息会话等共用）。
class ContextMenuAction {
  final String title;
  final Widget icon;
  final VoidCallback onTap;

  const ContextMenuAction({
    required this.title,
    required this.icon,
    required this.onTap,
  });
}

/// 以点击位置为锚点弹出 Miuix 右键菜单；返回所选动作（未选返回 null）。
///
/// 自绘浮层为唯一实现（阶段5d-L1 起）：OverlayEntry + 180ms 淡入缩放，
/// 点击外部/Esc 收起，选择后先给 130ms 行按压反馈再关闭并回调。
/// 选项图标由本浮层按行文本尺寸统一驱动（不设显式尺寸），
/// 保证「图标与选项文本同大小」。
Future<VoidCallback?> showMiuixContextMenu({
  required BuildContext context,
  required Offset position,
  required List<ContextMenuAction> actions,
  String title = '更多操作',
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return Future.value(null);

  final completer = Completer<VoidCallback?>();
  late OverlayEntry entry;
  var closed = false;
  void close(VoidCallback? result) {
    if (closed) return;
    closed = true;
    entry.remove();
    if (!completer.isCompleted) completer.complete(result);
  }

  entry = OverlayEntry(
    builder: (_) => _MiuixContextMenuOverlay(
      position: position,
      actions: actions,
      title: title,
      onDismiss: () => close(null),
      onSelect: (action) {
        // 点击先即时反馈（行按压态），130ms 后关闭并回调所选动作。
        Future.delayed(const Duration(milliseconds: 130), () => close(action));
      },
    ),
  );
  overlay.insert(entry);
  return completer.future;
}

class _MiuixContextMenuOverlay extends StatefulWidget {
  const _MiuixContextMenuOverlay({
    required this.position,
    required this.actions,
    required this.title,
    required this.onDismiss,
    required this.onSelect,
  });

  final Offset position;
  final List<ContextMenuAction> actions;
  final String title;
  final VoidCallback onDismiss;
  final ValueChanged<VoidCallback> onSelect;

  @override
  State<_MiuixContextMenuOverlay> createState() =>
      _MiuixContextMenuOverlayState();
}

class _MiuixContextMenuOverlayState extends State<_MiuixContextMenuOverlay>
    with SingleTickerProviderStateMixin {
  VoidCallback? _escUnregister;
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  @override
  void initState() {
    super.initState();
    _escUnregister = EscapeLayerRegistry.instance.register(() {
      widget.onDismiss();
      return true;
    });
    _anim.forward(from: 0);
  }

  @override
  void dispose() {
    _escUnregister?.call();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColors = MiuixDropdownDefaults.dropdownColors(context);
    final contentColor = baseColors.contentColor;
    final selectedContentColor = baseColors.selectedContentColor;
    // 文本基底（覆写黄绿双下划线错误样式）+ 反色行配色（与弹层壳一致）。
    final rowTextStyle =
        (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      decoration: TextDecoration.none,
    );
    // 选项图标尺寸 = 行文本尺寸（不再硬编码 16 造成与 14px 文本失配）。
    final iconSize = rowTextStyle.fontSize ?? 14;

    final media = MediaQuery.of(context);
    const gap = 4.0;
    final width = math.min(300.0, media.size.width - 16);
    final left = widget.position.dx
        .clamp(8.0, math.max(8.0, media.size.width - width - 8))
        .toDouble();
    final top = widget.position.dy
        .clamp(8.0, math.max(8.0, media.size.height - 160))
        .toDouble();

    final curved =
        CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);
    // 对角线展开：以点击点为面板左上角（topLeft 锚点）缩放展开。
    final panel = FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
        alignment: Alignment.topLeft,
        child: MiuixOverlayPanel(
          title: widget.title,
          icon: AppIcon(AppIcons.more(),
            size: 16,
            color: theme.colorScheme.primary,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: math.max(120.0, media.size.height - top - 24),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final action in widget.actions)
                    MiuixPopupMenuRow(
                      text: action.title,
                      leading: IconTheme(
                        data: IconThemeData(color: contentColor, size: iconSize),
                        child: action.icon,
                      ),
                      enabled: true,
                      selected: false,
                      textStyle: rowTextStyle,
                      contentColor: contentColor,
                      selectedContentColor: selectedContentColor,
                      onTap: () => widget.onSelect(action.onTap),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return Stack(
      children: [
        // 点击外部关闭。
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onDismiss,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: left,
          top: top + gap,
          width: width,
          child: panel,
        ),
      ],
    );
  }
}
