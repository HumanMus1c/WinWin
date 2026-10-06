import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/core/window/desktop_fullscreen.dart';

/// 沉浸式标题栏背景色覆写（null = 跟随主题 Scaffold 背景色）。
///
/// 顶部为深色/独立配色的页面（如视频详情页全屏播放）可推送与页顶一致的颜色，
/// 使标题栏与页面顶部无缝衔接；页面退出或被覆盖时应回收（见
/// [pushTitleBarBackdrop] / [clearTitleBarBackdrop]）。
final ValueNotifier<Color?> titleBarBackdrop = ValueNotifier<Color?>(null);

/// 标题条背景覆写的当前所有者（页面实例），防止旧页面清理误伤新页面。
Object? _titleBarBackdropOwner;

/// 以 [owner] 名义推送标题条背景色。
void pushTitleBarBackdrop(Object owner, Color color) {
  _titleBarBackdropOwner = owner;
  titleBarBackdrop.value = color;
}

/// 回收 [owner] 推送的标题条背景色（非当前所有者时忽略）。
void clearTitleBarBackdrop(Object owner) {
  if (identical(_titleBarBackdropOwner, owner)) {
    _titleBarBackdropOwner = null;
    titleBarBackdrop.value = null;
  }
}

/// 沉浸式透明标题栏壳层（对标 PiliPlus「隐藏系统标题栏 + 应用自绘标题条」）。
///
/// 系统原生标题栏由 DWM 绘制、不支持透明通道，因此沉浸模式（默认）：
/// - 原生标题栏隐藏（`TitleBarStyle.hidden`，见 main.dart 窗口选项）；
/// - 顶部 [kWindowCaptionHeight] 逻辑像素为纯透明标题条：拖动移动窗口、
///   双击最大化/还原、右键系统菜单，右侧为最小化/最大化/关闭三键；
/// - 顶部边缘 8px 由 [DragToResizeArea] 承接拉伸（隐藏标题栏后系统无顶部边框）；
///   左/右/下边缘仍由系统原生 8px 非客户区 resize 边框接管；
/// - 显示器原生全屏时整条隐藏（全屏样式联动见 [DesktopFullscreen]）。
class ImmersiveTitleBarShell extends StatefulWidget {
  const ImmersiveTitleBarShell({super.key, required this.child});

  /// 路由内容（通常为 Navigator）。
  final Widget child;

  @override
  State<ImmersiveTitleBarShell> createState() => _ImmersiveTitleBarShellState();
}

class _ImmersiveTitleBarShellState extends State<ImmersiveTitleBarShell>
    with WindowListener {
  bool _isMaximized = false;
  bool _isFocused = true;
  bool _isFullScreen = false;

  /// 沉浸模式启动时锁定（与窗口启动时的 TitleBarStyle 决策一致；设置项需重启生效）。
  late final bool _immersive = Pref.immersiveTitleBar;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _isFullScreen = DesktopFullscreen.isFullScreen;
    DesktopFullscreen.fullScreenNotifier.addListener(_onFullScreenChanged);
    _syncWindowState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    DesktopFullscreen.fullScreenNotifier.removeListener(_onFullScreenChanged);
    super.dispose();
  }

  Future<void> _syncWindowState() async {
    try {
      final maximized = await windowManager.isMaximized();
      final focused = await windowManager.isFocused();
      if (!mounted) return;
      if (maximized != _isMaximized || focused != _isFocused) {
        setState(() {
          _isMaximized = maximized;
          _isFocused = focused;
        });
      }
    } catch (_) {
      // 窗口管理器未就绪（如 bootstrap 失败）时忽略，保持默认状态。
    }
  }

  void _onFullScreenChanged() {
    if (!mounted) return;
    setState(() => _isFullScreen = DesktopFullscreen.fullScreenNotifier.value);
  }

  // ── WindowListener ──

  @override
  void onWindowMaximize() {
    if (mounted && !_isMaximized) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted && _isMaximized) setState(() => _isMaximized = false);
  }

  @override
  void onWindowFocus() {
    if (mounted && !_isFocused) setState(() => _isFocused = true);
  }

  @override
  void onWindowBlur() {
    if (mounted && _isFocused) setState(() => _isFocused = false);
  }

  @override
  Widget build(BuildContext context) {
    // 「使用系统原生标题栏」开启时不渲染沉浸条（逃生舱，见设置-外观）。
    if (!_immersive) return widget.child;

    return DragToResizeArea(
      enableResizeEdges: (_isFullScreen || _isMaximized)
          ? const []
          : const [ResizeEdge.topLeft, ResizeEdge.top, ResizeEdge.topRight],
      child: ValueListenableBuilder<Color?>(
        valueListenable: titleBarBackdrop,
        builder: (context, backdrop, _) => ColoredBox(
          color: backdrop ?? Theme.of(context).scaffoldBackgroundColor,
          child: Column(
            children: [
              if (!_isFullScreen)
                SizedBox(
                  height: kWindowCaptionHeight,
                  child: _buildTitleBarRow(context),
                ),
              Expanded(child: widget.child),
            ],
          ),
        ),
      ),
    );
  }

  /// 32px 透明标题条：左侧拖动区（含右键系统菜单）+ 右侧窗口控制三键。
  Widget _buildTitleBarRow(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onSecondaryTap: () => windowManager.popUpWindowMenu(),
            child: const DragToMoveArea(child: SizedBox.expand()),
          ),
        ),
        AnimatedOpacity(
          opacity: _isFocused ? 1 : 0.6,
          duration: const Duration(milliseconds: 150),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              WindowCaptionButton.minimize(
                brightness: brightness,
                onPressed: () => windowManager.minimize(),
              ),
              if (_isMaximized)
                WindowCaptionButton.unmaximize(
                  brightness: brightness,
                  onPressed: () => windowManager.unmaximize(),
                )
              else
                WindowCaptionButton.maximize(
                  brightness: brightness,
                  onPressed: () => windowManager.maximize(),
                ),
              WindowCaptionButton.close(
                brightness: brightness,
                onPressed: () => windowManager.close(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
