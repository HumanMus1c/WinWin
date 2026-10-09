import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart'
    show MiuixIconButton, MiuixMotion, MiuixScaffold;
// 过渡期依赖（B7 摘除 material_ui 时替换为 miuix 表面容器）：
// 骨架必须提供 Material 祖先，见下方 [_AppScaffoldState] 注释。
import 'package:material_ui/material_ui.dart' show Material, MaterialType;

import 'app_theme_host.dart';

/// 页面骨架替身（取代 Material `Scaffold`）。
///
/// 基于 flutter_miuix [MiuixScaffold]（纯 widgets 层实现，自带
/// topBar/bottomBar/FAB/floatingToolbar/snackbarHost/popupHost 槽位与
/// 窗口内边距换算）；本类只补项目口径的默认值：
/// - 背景默认取 [AppTokens] 的 `colors.background`（可由 [backgroundColor] 覆盖）；
/// - **顶部安全行**（[reserveTopStrip]）：每个页面顶部预留一行（高度 = 此前的紧凑标题栏
///   高度 [topStripHeight]）作为安全区域，避免内容贴顶；
/// - **返回按钮**（[showBackButton]）：仅在**二级页面**（可 pop）的顶部安全行左侧显示
///   悬浮返回按钮（Miuix 图标按钮规范 + 阴影）；
/// - 顶部安全行右侧承载 [actions]（原顶栏操作按钮的落点）。
///
/// 2026-10-08 起项目去除页面标题栏，由上述安全行 + 悬浮按钮取代；
/// **根页面**（一级页面）传入 [title]，安全行即显示页面标题，并可随滚动收缩。
class AppScaffold extends StatefulWidget {
  const AppScaffold({
    super.key,
    this.topBar,
    this.bottomBar,
    this.floatingActionButton,
    this.snackbarHost,
    this.popupHost,
    this.backgroundColor,
    this.title,
    this.showBackButton = true,
    this.reserveTopStrip = true,
    this.collapsible = true,
    this.actions,
    required this.body,
  });

  /// 顶部安全行高度（= 此前的紧凑标题栏高度口径）。
  static const double topStripHeight = 50;

  /// 顶栏（通常为 MiuixTopAppBar 或页面自绘顶栏）。
  ///
  /// 2026-10-08 起项目**默认不再使用页面标题栏**（窗口标题条 + 左侧导航已表达位置），
  /// 仅保留槽位供个别必需场景（如分类 Tab 栏）使用。
  final Widget? topBar;

  /// 底栏。
  final Widget? bottomBar;

  /// 浮动按钮。
  final Widget? floatingActionButton;

  /// Toast/Snackbar 宿主槽位。
  final Widget? snackbarHost;

  /// 弹层宿主槽位（MiuixOverlayDialog 等）。
  final Widget? popupHost;

  /// 背景色；null 时取当前 Token 的应用背景色。
  final Color? backgroundColor;

  /// 页面标题（**根页面**传入）：显示在顶部安全行左侧（二级页面为返回按钮位置）。
  final String? title;

  /// 是否在顶部安全行左侧提供返回按钮（[Navigator.canPop] 为真时显示）。
  final bool showBackButton;

  /// 是否预留顶部安全行（内嵌在别的页面里的子页面可关掉）。
  final bool reserveTopStrip;

  /// 顶部安全行是否随滚动收缩（向下滚动收起、向上滚动展开，Miuix 顶栏行为）。
  final bool collapsible;

  /// 顶部安全行右侧的操作区（刷新/清空/分享等）。
  final List<Widget>? actions;

  /// 页面主体。
  final Widget body;

  @override
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  bool _collapsed = false;

  bool _onScroll(ScrollNotification notification) {
    if (!widget.collapsible || widget.title == null || !widget.reserveTopStrip) {
      return false;
    }
    const threshold = 8.0;
    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      final atTop = notification.metrics.pixels <= 0;
      if (!_collapsed && delta > threshold && !atTop) {
        setState(() => _collapsed = true);
      } else if (_collapsed && (delta < -threshold || atTop)) {
        setState(() => _collapsed = false);
      }
    } else if (notification is ScrollEndNotification &&
        notification.metrics.pixels <= 0 &&
        _collapsed) {
      setState(() => _collapsed = false);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    return MiuixScaffold(
      topBar: widget.topBar,
      bottomBar: widget.bottomBar,
      floatingActionButton: widget.floatingActionButton,
      snackbarHost: widget.snackbarHost,
      popupHost: widget.popupHost,
      containerColor: widget.backgroundColor ?? tokens.colors.background,
      content: (EdgeInsets padding) {
        final canPop = widget.showBackButton &&
            (Navigator.maybeOf(context)?.canPop() ?? false);
        final actions = widget.actions;
        final hasActions = actions != null && actions.isNotEmpty;
        // B5-3 起骨架改用纯 widgets 实现的 MiuixScaffold，树上不再有 Material
        // 祖先；Material 系控件（TextField/InkWell/ListTile 等）要求有 Material
        // 祖先，否则整页红屏（2026-10-09 视频/专栏/空间/会话页回归，祖先链实测
        // MiuixScaffold→AppScaffold 之上无 Material）。此处统一补一层透明
        // Material（复用 session_list_section.dart 成熟模式），各页无需重复处理；
        // 顶部安全行在 Material 之外，水波绘制限定在 body 区域内。
        final body = Material(
          type: MaterialType.transparency,
          child: widget.body,
        );
        if (!widget.reserveTopStrip) {
          return Padding(padding: padding, child: body);
        }
        final title = widget.title;
        final strip = Row(
          children: [
            const SizedBox(width: 8),
            if (canPop) FloatingBackButton(tokens: tokens),
            if (!canPop && title != null) ...[
              const SizedBox(width: 16),
              Text(
                title,
                style: tokens.text.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: tokens.colors.onSurface,
                ),
              ),
            ],
            const Spacer(),
            if (hasActions) ...actions,
            const SizedBox(width: 8),
          ],
        );
        return Padding(
          padding: padding,
          child: Column(
            children: [
              // 安全行：向下滚动收起、向上滚动展开（Miuix 顶栏收缩行为）。
              ClipRect(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: MiuixMotion.standardDecelerate,
                  height: _collapsed ? 0 : AppScaffold.topStripHeight,
                  child: strip,
                ),
              ),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScroll,
                  child: body,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 悬浮返回按钮：Miuix 图标按钮规范（squircle + 按压反馈）+ 额外阴影。
///
/// 尺寸 42；Miuix 图标按钮默认 40 且**无阴影**，
/// 按项目要求补一层柔和阴影以在内容上可辨识。
class FloatingBackButton extends StatelessWidget {
  const FloatingBackButton({super.key, required this.tokens, this.onPressed});

  final AppTokens tokens;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '返回',
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0x33000000),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: MiuixIconButton(
          onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
          minWidth: 42,
          minHeight: 42,
          backgroundColor:
              tokens.colors.surfaceContainerHighest.withValues(alpha: 0.92),
          child: Icon(
            CupertinoIcons.chevron_back,
            size: 22,
            color: tokens.colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
