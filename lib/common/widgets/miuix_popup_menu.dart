import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:material_ui/material_ui.dart';

import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/miuix_theme_bridge.dart';
import 'package:winwin/core/shell/app_theme_host.dart';

/// 自研 Miuix 弹层菜单壳（阶段4h）。
///
/// **背景**：上游 `MiuixWindowIconDropdownMenu` 的窗口弹层存在两个硬约束：
/// 1. 展开/收起过渡使用 `MiuixListPopupDefaults` 的 `static const` 弹簧
///    （dampingRatio 0.82）——弹性回弹幅度大，且没有任何禁用/调参入口
///    （无构造参数、不读取 `MediaQuery.disableAnimations`）；
/// 2. 面板底色不可定制（facade 未暴露 surfaceBuilder/面板色）。
///
/// 本壳复用官方条目渲染 [MiuixDropdownEntriesPopupContent]（选中态/分组分隔
/// 均为原生实现），自绘弹层壳以提供：
/// - **平滑动效**：fade + 轻微上浮（easeOutCubic，180ms 进 / 140ms 出），无回弹；
/// - **统一半透明材质**：`surfaceContainer × kMiuixSurfaceAlpha`（与 Toast 同源）；
/// - 交互契约：点击外部 / 选择（单组）/ Esc 收起；多组时选择后保持展开
///   （与上游 `collapseOnSelection = entries.length <= 1` 一致）。
class MiuixPopupMenu extends StatefulWidget {
  const MiuixPopupMenu({
    super.key,
    required this.entries,
    required this.child,
    this.title,
    this.maxHeight = 420,
    this.itemTextStyle,
  });

  final List<MiuixDropdownEntry> entries;

  /// 触发器（含 hover 视觉的任意控件；点击由本壳接管）。
  final Widget child;

  /// 弹层标题（取原触发控件的 tooltip / 功能描述，避免无标题导致误判
  /// 操作）；null 时不渲染标题行。
  final String? title;

  final double maxHeight;

  /// 条目文本样式（仅覆盖给定字段，其余继承面板基底）——用于继承触发
  /// 控件的字号，避免弹层与触发控件割裂（如播放器控制条 12px）。
  final TextStyle? itemTextStyle;

  @override
  State<MiuixPopupMenu> createState() => _MiuixPopupMenuState();
}

class _MiuixPopupMenuState extends State<MiuixPopupMenu>
    with SingleTickerProviderStateMixin {
  OverlayEntry? _entry;
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    reverseDuration: const Duration(milliseconds: 140),
  );
  final FocusNode _focusNode = FocusNode(debugLabel: 'MiuixPopupMenu');

  @override
  void dispose() {
    _entry?.remove();
    _entry = null;
    _focusNode.dispose();
    _anim.dispose();
    super.dispose();
  }

  void _show() {
    final box = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (box == null || overlay == null || !box.hasSize) return;

    final triggerRect = box.localToGlobal(Offset.zero) & box.size;
    _entry = OverlayEntry(
      builder: (_) => _PopupOverlay(
        triggerRect: triggerRect,
        maxHeight: widget.maxHeight,
        entries: widget.entries,
        title: widget.title,
        itemTextStyle: widget.itemTextStyle,
        animation: _anim,
        focusNode: _focusNode,
        onDismiss: _close,
        onSelect: _handleSelect,
      ),
    );
    overlay.insert(_entry!);
    _anim.forward(from: 0);
    _focusNode.requestFocus();
  }

  void _close() {
    final entry = _entry;
    if (entry == null) return;
    _entry = null;
    _anim.reverse().whenComplete(entry.remove);
  }

  void _handleSelect(int entryIdx, int itemIdx) {
    final entry = widget.entries.elementAtOrNull(entryIdx);
    final item = entry?.items.elementAtOrNull(itemIdx);
    if (item == null) return;
    item.onClick?.call();
    // B7 反馈轮#2：点击后先呈现即时视觉变化（下一帧 markNeedsBuild 以读取
    // 父级 setState 后的最新 entries —— 选中态/角标等立即刷新），随后延迟
    // 收起；共享控件统一口径（此前仅单组菜单收起，多组保持展开）。
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _entry?.markNeedsBuild(),
    );
    Future.delayed(const Duration(milliseconds: 130), () {
      if (_entry != null) _close();
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _entry == null ? _show : _close,
      child: widget.child,
    );
  }
}

class _PopupOverlay extends StatelessWidget {
  const _PopupOverlay({
    required this.triggerRect,
    required this.maxHeight,
    required this.entries,
    required this.title,
    required this.itemTextStyle,
    required this.animation,
    required this.focusNode,
    required this.onDismiss,
    required this.onSelect,
  });

  final Rect triggerRect;
  final double maxHeight;
  final List<MiuixDropdownEntry> entries;
  final String? title;
  final TextStyle? itemTextStyle;
  final Animation<double> animation;
  final FocusNode focusNode;
  final VoidCallback onDismiss;
  final void Function(int entryIdx, int itemIdx) onSelect;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final muiColors = MiuixTheme.of(context).colors;
    final baseColors = MiuixDropdownDefaults.dropdownColors(context);
    final contentColor = baseColors.contentColor;
    final selectedContentColor = baseColors.selectedContentColor;
    // 文本基底：覆写 WidgetsApp 的默认"黄绿双下划线"错误样式
    // （浮层无 Material/DefaultTextStyle 时 Text 合并到该样式）。
    final bodyStyle =
        (AppThemeHost.of(context).text.bodyMedium ?? const TextStyle())
            .copyWith(decoration: TextDecoration.none);
    // 条目字号继承触发控件（如播放器控制条 12px），避免弹层与其割裂。
    final rowTextStyle = itemTextStyle == null
        ? bodyStyle
        : bodyStyle.merge(itemTextStyle);

    const gap = 6.0;
    const screenInset = 12.0;

    // 方向 = 上下可用空间较大侧（与布局委托同一策略），仅决定展开动画锚点：
    // 默认向下展开；上侧空间更大时翻转到触发器上方。
    final spaceBelow =
        media.size.height - triggerRect.bottom - gap - screenInset;
    final spaceAbove = triggerRect.top - gap - screenInset;
    final placeAbove = spaceAbove > spaceBelow;

    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    // 对角线展开：以贴近触发器的一角为原点缩放（向下展开→右上角；
    // 向上翻转→右下角）。
    final panel = FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
        alignment: placeAbove ? Alignment.bottomRight : Alignment.topRight,
        child: DefaultTextStyle(
          style: bodyStyle,
          child: Focus(
            focusNode: focusNode,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                onDismiss();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: MiuixSurface(
                cornerRadius: 16,
                color: muiColors.surfaceContainer.withValues(
                  alpha: kMiuixSurfaceAlpha,
                ),
                shadowElevation: 6,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  // B7 反馈轮#2：背景模糊对齐表情面板（MiuixOverlayPanel 的
                  // BackdropFilter blur 16 口径）。
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (title != null) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                            child: Text(
                              title!,
                              style:
                                  (Theme.of(context).textTheme.titleSmall ??
                                          const TextStyle())
                                      .copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: contentColor,
                                      ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 14),
                            child: MiuixHorizontalDivider(thickness: 1.5),
                          ),
                        ],
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: _buildRows(
                                context,
                                rowTextStyle: rowTextStyle,
                                contentColor: contentColor,
                                selectedContentColor: selectedContentColor,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Stack(
      children: [
        // 拦截层：点击任意处（含其余交互）收起。
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => onDismiss(),
            child: const SizedBox.expand(),
          ),
        ),
        Positioned.fill(
          child: CustomSingleChildLayout(
            delegate: _PopupMenuLayout(
              triggerRect: triggerRect,
              gap: gap,
              inset: screenInset,
              maxWidth: 320,
              maxHeight: maxHeight,
            ),
            child: panel,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildRows(
    BuildContext context, {
    required TextStyle rowTextStyle,
    required Color contentColor,
    required Color selectedContentColor,
  }) {
    final rows = <Widget>[];
    for (var entryIdx = 0; entryIdx < entries.length; entryIdx++) {
      final entry = entries[entryIdx];
      for (var itemIdx = 0; itemIdx < entry.items.length; itemIdx++) {
        final item = entry.items[itemIdx];
        rows.add(
          MiuixPopupMenuRow(
            text: item.text,
            // L5-10b：补传条目图标（此前自绘壳未接 leading，图标不渲染），
            // 尺寸随行文本（不再依赖调用方硬编码）。
            leading: item.icon == null
                ? null
                : IconTheme(
                    data: IconThemeData(
                      color: contentColor,
                      size: rowTextStyle.fontSize ?? 14,
                    ),
                    child: item.icon!,
                  ),
            enabled: entry.enabled && item.enabled,
            selected: item.selected,
            textStyle: rowTextStyle,
            contentColor: contentColor,
            selectedContentColor: selectedContentColor,
            onTap: () => onSelect(entryIdx, itemIdx),
          ),
        );
      }
      if (entryIdx != entries.length - 1) {
        rows.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: MiuixHorizontalDivider(thickness: 1.5),
          ),
        );
      }
    }
    return rows;
  }
}

/// 弹层菜单的视窗内自适应布局（对齐 Flutter 官方 PopupMenu 思路）：
/// 先按视窗给面板下发约束（宽不超 [maxWidth]、高不超 [maxHeight] 与视窗），
/// 拿到实际尺寸后决定展开方向与位置，并整体 clamp 进视窗 —— 四边不越界；
/// 窗口过矮时面板被约束收缩，条目区由 SingleChildScrollView 滚动。
class _PopupMenuLayout extends SingleChildLayoutDelegate {
  _PopupMenuLayout({
    required this.triggerRect,
    required this.gap,
    required this.inset,
    required this.maxWidth,
    required this.maxHeight,
  });

  /// 触发器矩形（弹层插入时快照）。
  final Rect triggerRect;

  /// 面板与触发器之间的间隙。
  final double gap;

  /// 视窗最小边距。
  final double inset;

  /// 面板宽度上限。
  final double maxWidth;

  /// 面板高度上限（组件常态上限，再与视窗取 min）。
  final double maxHeight;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      maxWidth: math.max(
        0.0,
        math.min(maxWidth, constraints.maxWidth - inset * 2),
      ),
      maxHeight: math.max(
        0.0,
        math.min(maxHeight, constraints.maxHeight - inset * 2),
      ),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final spaceBelow = size.height - triggerRect.bottom - gap - inset;
    final spaceAbove = triggerRect.top - gap - inset;
    final y = spaceAbove > spaceBelow
        ? triggerRect.top - gap - childSize.height
        : triggerRect.bottom + gap;
    return Offset(
      (triggerRect.right - childSize.width)
          .clamp(inset, math.max(inset, size.width - childSize.width - inset))
          .toDouble(),
      y
          .clamp(inset, math.max(inset, size.height - childSize.height - inset))
          .toDouble(),
    );
  }

  @override
  bool shouldRelayout(_PopupMenuLayout oldDelegate) =>
      triggerRect != oldDelegate.triggerRect ||
      gap != oldDelegate.gap ||
      inset != oldDelegate.inset ||
      maxWidth != oldDelegate.maxWidth ||
      maxHeight != oldDelegate.maxHeight;
}

/// 弹层条目行：hover 高亮 + 按压即时反馈（替代上游"纯矩形填充、无按压
/// 涟漪"的行渲染；上游行无任何桌面 hover/按压视觉）。
///
/// 公开供同类浮层（如视频卡片右键菜单）复用同一行交互与配色。
class MiuixPopupMenuRow extends StatefulWidget {
  const MiuixPopupMenuRow({
    super.key,
    required this.text,
    this.leading,
    required this.enabled,
    required this.selected,
    required this.textStyle,
    required this.contentColor,
    required this.selectedContentColor,
    required this.onTap,
  });

  final String text;

  /// 前置图标（可选；调用方自行处理尺寸/颜色继承）。
  final Widget? leading;
  final bool enabled;
  final bool selected;
  final TextStyle textStyle;
  final Color contentColor;
  final Color selectedContentColor;
  final VoidCallback onTap;

  @override
  State<MiuixPopupMenuRow> createState() => _MiuixPopupMenuRowState();
}

class _MiuixPopupMenuRowState extends State<MiuixPopupMenuRow> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final textColor = !widget.enabled
        ? widget.contentColor.withValues(alpha: 0.45)
        : (widget.selected ? widget.selectedContentColor : widget.contentColor);
    // hover 8% / 按压 14%（在内容色上叠透明层，明暗主题自适应）。
    final highlight = _pressed ? 0.14 : (_hovered ? 0.08 : 0.0);

    final row = Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: widget.contentColor.withValues(alpha: highlight),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (widget.leading != null) ...[
            widget.leading!,
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Text(
              widget.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: widget.textStyle.copyWith(color: textColor),
            ),
          ),
          if (widget.selected) ...[
            const SizedBox(width: 12),
            AppIcon(
              AppIcons.check(),
              size: 18,
              color: widget.selectedContentColor,
            ),
          ],
        ],
      ),
    );

    if (!widget.enabled) return row;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: row,
      ),
    );
  }
}
