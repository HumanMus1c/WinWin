import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_miuix/miuix.dart';
import 'package:flutter/widgets.dart';

import 'package:winwin/common/widgets/miuix_overlay_panel.dart';
import 'package:winwin/common/widgets/miuix_popup_menu.dart';
import 'package:winwin/core/input/escape_layer_registry.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/core/shell/app_theme_host.dart';

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
    final tokens = AppThemeHost.of(context);
    final baseColors = MiuixDropdownDefaults.dropdownColors(context);
    final contentColor = baseColors.contentColor;
    final selectedContentColor = baseColors.selectedContentColor;
    // 文本基底（覆写黄绿双下划线错误样式）+ 反色行配色（与弹层壳一致）。
    final rowTextStyle =
        (tokens.text.bodyMedium ?? const TextStyle()).copyWith(
      decoration: TextDecoration.none,
    );
    // 选项图标尺寸 = 行文本尺寸（不再硬编码 16 造成与 14px 文本失配）。
    final iconSize = rowTextStyle.fontSize ?? 14;

    final media = MediaQuery.of(context);
    const gap = 4.0;
    const edge = 8.0;
    // 方向 = 上下可用空间较大侧（与布局委托同一策略），仅决定展开动画锚点。
    final spaceBelow = media.size.height - widget.position.dy - gap - edge;
    final spaceAbove = widget.position.dy - gap - edge;
    final openUpward = spaceAbove > spaceBelow;

    final curved =
        CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);
    // 对角线展开：以贴近点击点的角为缩放原点（向下→左上角；向上→左下角）。
    final panel = FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
        alignment: openUpward ? Alignment.bottomLeft : Alignment.topLeft,
        child: MiuixOverlayPanel(
          title: widget.title,
          icon: AppIcon(AppIcons.more(),
            size: 16,
            color: tokens.colors.primary,
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
        Positioned.fill(
          child: CustomSingleChildLayout(
            delegate: _MiuixContextMenuLayout(
              anchor: widget.position,
              gap: gap,
              edge: edge,
              maxWidth: 300,
            ),
            child: panel,
          ),
        ),
      ],
    );
  }
}

/// 右键菜单的视窗内自适应布局（对齐 Flutter 官方 PopupMenu 思路）：
/// 先按视窗给面板下发约束（宽固定、高不超视窗），拿到实际尺寸后决定
/// 展开方向与位置，并整体 clamp 进视窗 —— 四边不越界；窗口过矮时面板
/// 被约束收缩，列表区由 SingleChildScrollView 滚动。
class _MiuixContextMenuLayout extends SingleChildLayoutDelegate {
  _MiuixContextMenuLayout({
    required this.anchor,
    required this.gap,
    required this.edge,
    required this.maxWidth,
  });

  /// 触发点（点击位置）。
  final Offset anchor;

  /// 面板与触发点之间的间隙。
  final double gap;

  /// 视窗最小边距。
  final double edge;

  /// 面板宽度上限。
  final double maxWidth;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final width = math.max(
      0.0,
      math.min(maxWidth, constraints.maxWidth - edge * 2),
    );
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: math.max(0.0, constraints.maxHeight - edge * 2),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final spaceBelow = size.height - anchor.dy - gap - edge;
    final spaceAbove = anchor.dy - gap - edge;
    final y = spaceAbove > spaceBelow
        ? anchor.dy - gap - childSize.height
        : anchor.dy + gap;
    return Offset(
      anchor.dx
          .clamp(edge, math.max(edge, size.width - childSize.width - edge))
          .toDouble(),
      y.clamp(edge, math.max(edge, size.height - childSize.height - edge))
          .toDouble(),
    );
  }

  @override
  bool shouldRelayout(_MiuixContextMenuLayout oldDelegate) =>
      anchor != oldDelegate.anchor ||
      gap != oldDelegate.gap ||
      edge != oldDelegate.edge ||
      maxWidth != oldDelegate.maxWidth;
}

/// 文本选择场景的 Miuix 化右键菜单（供 `SelectableRegion.contextMenuBuilder`
/// 接入，文章页等可选中文本区共用）。
///
/// 与 [showMiuixContextMenu] 复用同一套浮层积木（[MiuixOverlayPanel] +
/// [MiuixPopupMenuRow]、180ms 对角展开、130ms 按压后回调、Esc 登记），差异：
/// - 条目来自 `SelectableRegionState.contextMenuButtonItems`（复制/全选等，
///   动作回调由框架绑定）；
/// - 定位由官方 [DesktopTextSelectionToolbarLayoutDelegate] 在**右键点击处**
///   展开（溢出时回推视窗内）；
/// - 关闭由 SelectableRegion 自身（点外 / Esc DismissIntent）驱动，本层仅
///   补充 Esc 登记，保证与全 app 右键菜单相同的"Esc 只关菜单、不级联"语义。
Widget buildMiuixTextSelectionContextMenu(
  BuildContext context,
  SelectableRegionState selectableRegionState,
) {
  return _MiuixTextSelectionContextMenu(state: selectableRegionState);
}

class _MiuixTextSelectionContextMenu extends StatefulWidget {
  const _MiuixTextSelectionContextMenu({required this.state});

  final SelectableRegionState state;

  @override
  State<_MiuixTextSelectionContextMenu> createState() =>
      _MiuixTextSelectionContextMenuState();
}

class _MiuixTextSelectionContextMenuState
    extends State<_MiuixTextSelectionContextMenu>
    with SingleTickerProviderStateMixin {
  VoidCallback? _escUnregister;
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  /// 右键点击位置（Overlay 全局坐标）：显示时捕获一次——
  /// `contextMenuAnchors` 读取即消费（读取后框架清空点击位置），
  /// 缓存可避免重建时回退到选区端点导致菜单跳动。
  late final Offset _anchor;

  @override
  void initState() {
    super.initState();
    _anchor = widget.state.contextMenuAnchors.primaryAnchor;
    _escUnregister = EscapeLayerRegistry.instance.register(() {
      widget.state.hideToolbar();
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

  /// 条目文案：优先框架 label，其余按控件类型映射中文（全 app 口径一致）。
  static String _labelFor(ContextMenuButtonItem item) {
    final label = item.label;
    if (label != null && label.isNotEmpty) return label;
    return switch (item.type) {
      ContextMenuButtonType.cut => '剪切',
      ContextMenuButtonType.copy => '复制',
      ContextMenuButtonType.paste => '粘贴',
      ContextMenuButtonType.selectAll => '全选',
      ContextMenuButtonType.delete => '删除',
      ContextMenuButtonType.share => '分享',
      ContextMenuButtonType.lookUp => '查询',
      ContextMenuButtonType.searchWeb => '搜索',
      _ => '操作',
    };
  }

  /// 条目图标：语义方法映射（未知类型回退 [AppIcons.more]）。
  static Widget _iconFor(ContextMenuButtonItem item, double size) {
    return switch (item.type) {
      ContextMenuButtonType.copy => AppIcon(AppIcons.copy(), size: size),
      ContextMenuButtonType.selectAll => AppIcon(AppIcons.check(), size: size),
      ContextMenuButtonType.share => AppIcon(AppIcons.share(), size: size),
      _ => AppIcon(AppIcons.more(), size: size),
    };
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final baseColors = MiuixDropdownDefaults.dropdownColors(context);
    final contentColor = baseColors.contentColor;
    final selectedContentColor = baseColors.selectedContentColor;
    // 文本基底（覆写黄绿双下划线错误样式）+ 反色行配色（与右键菜单一致）。
    final rowTextStyle =
        (tokens.text.bodyMedium ?? const TextStyle()).copyWith(
      decoration: TextDecoration.none,
    );
    // 选项图标尺寸 = 行文本尺寸（与右键菜单同口径）。
    final iconSize = rowTextStyle.fontSize ?? 14;

    final items = widget.state.contextMenuButtonItems;

    final curved = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);
    final panel = FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
        alignment: Alignment.topLeft,
        child: MiuixOverlayPanel(
          title: '文本操作',
          icon: AppIcon(AppIcons.copy(),
            size: 16,
            color: tokens.colors.primary,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final item in items)
                MiuixPopupMenuRow(
                  text: _labelFor(item),
                  leading: IconTheme(
                    data: IconThemeData(color: contentColor, size: iconSize),
                    child: _iconFor(item, iconSize),
                  ),
                  enabled: true,
                  selected: false,
                  textStyle: rowTextStyle,
                  contentColor: contentColor,
                  selectedContentColor: selectedContentColor,
                  onTap: () {
                    // 与全 app 右键菜单同节奏：先给行按压反馈，130ms 后执行并收起。
                    Future.delayed(const Duration(milliseconds: 130), () {
                      if (!widget.state.mounted) return;
                      item.onPressed?.call();
                      widget.state.hideToolbar();
                    });
                  },
                ),
            ],
          ),
        ),
      ),
    );

    return CustomSingleChildLayout(
      delegate: DesktopTextSelectionToolbarLayoutDelegate(anchor: _anchor),
      child: SizedBox(width: 200, child: panel),
    );
  }
}
