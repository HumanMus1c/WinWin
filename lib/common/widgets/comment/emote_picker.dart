import 'dart:async' show unawaited;

import 'package:flutter_miuix/miuix.dart' show MiuixPressFeedbackType, MiuixPressable;
import 'package:flutter/widgets.dart';

import 'package:winwin/common/widgets/miuix_overlay_panel.dart';
import 'package:winwin/core/emote/emote_store.dart';
import 'package:winwin/core/input/escape_layer_registry.dart';
import 'package:winwin/utils/bilibili_emotes.dart';
import 'package:winwin/utils/image_utils.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/ui/components/app_tooltip.dart';

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

  /// 面板高度估算（头部 + 分包 Tab + 网格最大高度 + 内边距），用于上下翻转判定。
  static const double _estimatedPanelHeight = 340;
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
          // 个别失效表情（404）不再产生崩溃报告：失败由网格 errorBuilder
          // 兜底展示占位文字，预取侧仅静默忽略。
          onError: (Object _, StackTrace? _) {},
        ),
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
        final tokens = AppThemeHost.of(ctx);

        final panel = FadeTransition(
          opacity: _controller,
          child: ScaleTransition(
            scale: _scale,
            alignment: anchor,
            child: _buildPanel(tokens),
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
    EmoteStore.instance.ensureLoaded();
    _precacheEmotes();
  }

  Widget _buildPanel(AppTokens tokens) {
    // 共用浮层面板（MiuixOverlayPanel）：与"弹幕样式"面板统一样式，
    // 半透明底统一走 kMiuixSurfaceAlpha；对角线展开动画在 Overlay 层包裹。
    return MiuixOverlayPanel(
      title: '表情',
      icon: AppIcon(
        AppIcons.emoteEntry(),
        size: 16,
        color: tokens.colors.primary,
      ),
      child: _EmoteGridArea(
        onPick: (code) {
          _insert(code);
          _removePanel();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = AppThemeHost.of(context).colors;
    return AppTooltip(
      message: '选择官方表情',
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
            child: AppIcon(
              AppIcons.emoteEntry(),
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

/// 表情网格区（2026-09-29）：优先展示官方分包（[EmoteStore]），
/// 不可用时回退内置静态表；服务端数据到达后原地切换（静态优先，不闪加载态）。
class _EmoteGridArea extends StatefulWidget {
  const _EmoteGridArea({required this.onPick});

  final void Function(String code) onPick;

  @override
  State<_EmoteGridArea> createState() => _EmoteGridAreaState();
}

class _EmoteGridAreaState extends State<_EmoteGridArea> {
  static const double _tileSize = 28;
  static const double _maxGridHeight = 236;

  int _packageIndex = 0;

  @override
  void initState() {
    super.initState();
    EmoteStore.instance.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: EmoteStore.instance,
      builder: (context, _) {
        final packages = EmoteStore.instance.packages;
        if (packages.isEmpty) return _buildStaticGrid(context);
        final index = _packageIndex.clamp(0, packages.length - 1);
        final selected = packages[index];
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (packages.length > 1) ...[
              SizedBox(
                height: 28,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: packages.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (ctx, i) => _buildPackageTab(ctx, i, index),
                ),
              ),
              const SizedBox(height: 8),
            ],
            _buildGrid(
              context,
              itemCount: selected.emote.length,
              builder: (ctx, i) {
                final e = selected.emote[i];
                if (e.isText || e.url.isEmpty) {
                  return _buildTextTile(e.text);
                }
                return _buildImageTile(
                  ctx,
                  url: e.url,
                  label: e.text,
                  tooltip: e.text,
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildPackageTab(BuildContext context, int i, int activeIndex) {
    final tokens = AppThemeHost.of(context);
    final active = i == activeIndex;
    return MiuixPressable(
      feedbackType: MiuixPressFeedbackType.sink,
      sinkAmount: 0.98,
      borderRadius: BorderRadius.circular(6),
      onPressed: () => setState(() => _packageIndex = i),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: active
              ? tokens.colors.primary.withValues(alpha: 0.16)
              : null,
        ),
        child: Text(
          EmoteStore.instance.packages[i].text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active
                ? tokens.colors.primary
                : tokens.colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildStaticGrid(BuildContext context) {
    return _buildGrid(
      context,
      itemCount: BilibiliEmotes.popularEmotes.length,
      builder: (ctx, i) {
        final code = BilibiliEmotes.popularEmotes[i];
        final url = BilibiliEmotes.defaultEmotes[code];
        if (url == null) return _buildTextTile(code);
        return _buildImageTile(ctx, url: url, label: code, tooltip: code);
      },
    );
  }

  Widget _buildGrid(
    BuildContext context, {
    required int itemCount,
    required NullableIndexedWidgetBuilder builder,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _maxGridHeight),
      child: GridView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
        ),
        itemCount: itemCount,
        itemBuilder: builder,
      ),
    );
  }

  Widget _buildImageTile(
    BuildContext context, {
    required String url,
    required String label,
    required String tooltip,
  }) {
    final cacheSize = ImageUtils.decodeClamp(_tileSize, context, max: 128);
    return AppTooltip(
      message: tooltip,
      child: MiuixPressable(
        feedbackType: MiuixPressFeedbackType.sink,
        sinkAmount: 0.98,
        borderRadius: BorderRadius.circular(6),
        onPressed: () => widget.onPick(label),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Image.network(
            ImageUtils.thumbnailUrl(url, type: 'emote'),
            width: _tileSize,
            height: _tileSize,
            fit: BoxFit.contain,
            cacheWidth: cacheSize,
            cacheHeight: cacheSize,
            gaplessPlayback: true,
            frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded) return child;
              return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                child: child,
              );
            },
            errorBuilder: (_, _, _) => Center(
              child: Text(label, style: const TextStyle(fontSize: 10)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextTile(String text) {
    return AppTooltip(
      message: text,
      child: MiuixPressable(
        feedbackType: MiuixPressFeedbackType.sink,
        sinkAmount: 0.98,
        borderRadius: BorderRadius.circular(6),
        onPressed: () => widget.onPick(text),
        child: Center(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: const TextStyle(fontSize: 10),
          ),
        ),
      ),
    );
  }
}
