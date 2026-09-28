import 'dart:async' show unawaited;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'package:winwin/core/input/escape_layer_registry.dart';
import 'package:winwin/utils/bilibili_emotes.dart';
import 'package:winwin/utils/image_utils.dart';

/// 官方表情面板按钮（评论输入框 / 直播互动条共用）。
///
/// 点击按钮在 **按钮上方** 弹出毛玻璃表情面板（样式对齐视频页"弹幕样式"
/// 面板），面板水平方向与按钮左/右缘对齐，展开动画自靠近按钮的面板角
/// 向对角缩放（左半区左下角 → 右上展开，右半区右下角 → 左上展开）；
/// 上方空间不足时翻转到按钮下方对称展开。
class OfficialEmotePickerButton extends StatefulWidget {
  const OfficialEmotePickerButton({
    super.key,
    required this.controller,
    this.focusNode,
    this.size = 40.0,
    this.enabled = true,
    this.onInserted,
  });

  /// 表情插入目标输入控制器。
  final TextEditingController controller;

  /// 插入后恢复焦点（可空，不传则不请求焦点）。
  final FocusNode? focusNode;

  /// 按钮尺寸（宽高一致）。
  final double size;

  /// 是否可用（false 时置灰且不可点开）。
  final bool enabled;

  /// 插入完成回调（供调用方刷新依赖输入文本的 UI）。
  final VoidCallback? onInserted;

  @override
  State<OfficialEmotePickerButton> createState() =>
      _OfficialEmotePickerButtonState();
}

class _OfficialEmotePickerButtonState extends State<OfficialEmotePickerButton>
    with SingleTickerProviderStateMixin {
  static const double _panelWidth = 320;
  static const double _estimatedPanelHeight = 240;
  static const double _edgeMargin = 8;

  final GlobalKey _anchorKey = GlobalKey();
  OverlayEntry? _overlay;

  /// 表情面板的 Esc 登记注销回调。
  VoidCallback? _escUnregister;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );
  late final Animation<double> _scale = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  bool _prefetched = false;

  @override
  void dispose() {
    _removePanel();
    _controller.dispose();
    super.dispose();
  }

  void _insert(String code) {
    final currentText = widget.controller.text;
    final selection = widget.controller.selection;
    final newText = (selection.start >= 0 && selection.end >= 0)
        ? currentText.replaceRange(selection.start, selection.end, code)
        : '$currentText$code';
    widget.controller.text = newText;
    widget.controller.selection = TextSelection.collapsed(
      offset: selection.start >= 0
          ? selection.start + code.length
          : newText.length,
    );
    widget.onInserted?.call();
    widget.focusNode?.requestFocus();
  }

  void _togglePanel() {
    if (_overlay != null) {
      _removePanel();
      return;
    }
    _openPanel();
  }

  void _removePanel() {
    _overlay?.remove();
    _overlay = null;
    _escUnregister?.call();
    _escUnregister = null;
  }

  /// 首次打开时后台预取全部表情图，再次打开即命中缓存、零 pop-in。
  void _precacheEmotes() {
    if (_prefetched) return;
    _prefetched = true;
    for (final code in BilibiliEmotes.popularEmotes) {
      final url = BilibiliEmotes.defaultEmotes[code];
      if (url == null) continue;
      unawaited(
        precacheImage(
          NetworkImage(ImageUtils.thumbnailUrl(url, type: 'emote')),
          context,
        ).catchError((Object _) {}),
      );
    }
  }

  void _openPanel() {
    final renderBox =
        _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final buttonRect = renderBox.localToGlobal(Offset.zero) & renderBox.size;
    final screenSize = MediaQuery.sizeOf(context);

    // 水平锚定：按钮在屏幕左半区 → 面板左缘对齐按钮左缘（自左下角展开）；
    // 右半区 → 面板右缘对齐按钮右缘（自右下角展开）。
    final alignLeft = buttonRect.center.dx < screenSize.width / 2;
    final rawLeft = alignLeft
        ? buttonRect.left
        : buttonRect.right - _panelWidth;
    final maxLeft = screenSize.width - _panelWidth - _edgeMargin;
    final left = rawLeft
        .clamp(_edgeMargin, maxLeft < _edgeMargin ? _edgeMargin : maxLeft)
        .toDouble();

    // 垂直：默认在按钮上方展开（底边距按钮顶 8px），上方空间不足时翻转到下方。
    final openAbove =
        buttonRect.top > _estimatedPanelHeight + _edgeMargin;

    // 展开锚点：取与按钮相邻的面板角，向对角方向缩放展开。
    final anchor = openAbove
        ? (alignLeft ? Alignment.bottomLeft : Alignment.bottomRight)
        : (alignLeft ? Alignment.topLeft : Alignment.topRight);

    _overlay = OverlayEntry(
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final isDark = theme.brightness == Brightness.dark;

        final panel = FadeTransition(
          opacity: _controller,
          child: ScaleTransition(
            scale: _scale,
            alignment: anchor,
            child: _buildPanel(theme, isDark),
          ),
        );

        return Stack(
          children: [
            // 透明遮罩：点击外部关闭面板。
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removePanel,
                child: const SizedBox.expand(),
              ),
            ),
            if (openAbove)
              Positioned(
                left: left,
                bottom: screenSize.height - buttonRect.top + _edgeMargin,
                width: _panelWidth,
                child: panel,
              )
            else
              Positioned(
                left: left,
                top: buttonRect.bottom + _edgeMargin,
                width: _panelWidth,
                child: panel,
              ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_overlay!);
    _escUnregister = EscapeLayerRegistry.instance.register(() {
      if (_overlay == null) return false;
      _removePanel();
      return true;
    });
    _controller.forward(from: 0);
    _precacheEmotes();
  }

  Widget _buildPanel(ThemeData theme, bool isDark) {
    final cs = theme.colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.15),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xD9262626)
                    : const Color(0xD9EAEAEA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.08),
                  width: 1,
                ),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.sentiment_satisfied_alt_outlined,
                        size: 16,
                        color: cs.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '表情',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    height: 1,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.08),
                  ),
                  const SizedBox(height: 10),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                    ),
                    itemCount: BilibiliEmotes.popularEmotes.length,
                    itemBuilder: (ctx, i) {
                      final code = BilibiliEmotes.popularEmotes[i];
                      final url = BilibiliEmotes.defaultEmotes[code];
                      final cacheSize =
                          ImageUtils.decodeClamp(28, ctx, max: 128);
                      return Tooltip(
                        message: code,
                        waitDuration: const Duration(milliseconds: 600),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () {
                            _insert(code);
                            _removePanel();
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: url != null
                                ? Image.network(
                                    ImageUtils.thumbnailUrl(url, type: 'emote'),
                                    width: 28,
                                    height: 28,
                                    fit: BoxFit.contain,
                                    cacheWidth: cacheSize,
                                    cacheHeight: cacheSize,
                                    gaplessPlayback: true,
                                    frameBuilder:
                                        (_, child, frame, wasSynchronouslyLoaded) {
                                      if (wasSynchronouslyLoaded) return child;
                                      return AnimatedOpacity(
                                        opacity: frame == null ? 0 : 1,
                                        duration:
                                            const Duration(milliseconds: 150),
                                        curve: Curves.easeOut,
                                        child: child,
                                      );
                                    },
                                    errorBuilder: (_, _, _) => Center(
                                      child: Text(
                                        code,
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    ),
                                  )
                                : Center(
                                    child: Text(
                                      code,
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: '选择官方表情',
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor:
            widget.enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          onTap: widget.enabled ? _togglePanel : null,
          child: Container(
            key: _anchorKey,
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: widget.enabled
                  ? cs.surface.withValues(alpha: 0.75)
                  : cs.surface.withValues(alpha: 0.4),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.sentiment_satisfied_alt_outlined,
              color: widget.enabled
                  ? cs.outline
                  : cs.outline.withValues(alpha: 0.4),
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
