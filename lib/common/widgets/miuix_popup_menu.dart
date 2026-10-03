import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:material_ui/material_ui.dart';

import 'package:winwin/theme/miuix_theme_bridge.dart';

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
    this.maxHeight = 420,
  });

  final List<MiuixDropdownEntry> entries;

  /// 触发器（含 hover 视觉的任意控件；点击由本壳接管）。
  final Widget child;

  final double maxHeight;

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
    entry?.items.elementAtOrNull(itemIdx)?.onClick?.call();
    // 单组：选择即收起；多组（如音轨）保持展开，与上游行为一致。
    if (widget.entries.length <= 1) _close();
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
    required this.animation,
    required this.focusNode,
    required this.onDismiss,
    required this.onSelect,
  });

  final Rect triggerRect;
  final double maxHeight;
  final List<MiuixDropdownEntry> entries;
  final Animation<double> animation;
  final FocusNode focusNode;
  final VoidCallback onDismiss;
  final void Function(int entryIdx, int itemIdx) onSelect;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final muiColors = MiuixTheme.of(context).colors;
    final dropdownColors = MiuixDropdownDefaults.dropdownColors(context);

    const gap = 6.0;
    const screenInset = 12.0;

    // 默认向下展开；下方空间不足时翻转到触发器上方。
    final spaceBelow = media.size.height - triggerRect.bottom - gap - screenInset;
    final placeAbove = spaceBelow < 160;
    final panelMaxHeight = math.max(
      120.0,
      math.min(maxHeight, placeAbove ? triggerRect.top - gap - screenInset : spaceBelow),
    );

    final right = math.max(8.0, media.size.width - triggerRect.right);
    final maxWidth = math.min(320.0, media.size.width - 16);

    final panel = FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.035),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
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
              color: muiColors.surfaceContainer
                  .withValues(alpha: kMiuixSurfaceAlpha),
              shadowElevation: 6,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: panelMaxHeight),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: MiuixDropdownEntriesPopupContent(
                      entries: entries,
                      dropdownColors: dropdownColors,
                      onItemClick: onSelect,
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
        if (placeAbove)
          Positioned(
            bottom: media.size.height - triggerRect.top + gap,
            right: right,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: panel,
            ),
          )
        else
          Positioned(
            top: triggerRect.bottom + gap,
            right: right,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: panel,
            ),
          ),
      ],
    );
  }
}
