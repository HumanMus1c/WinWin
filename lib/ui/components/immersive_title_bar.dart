import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

import 'package:winwin/theme/app_colors.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
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
        builder: (context, backdrop, _) {
          final stripColor =
              backdrop ?? AppThemeHost.of(context).colors.background;
          return ColoredBox(
            color: stripColor,
            child: Column(
              children: [
                if (!_isFullScreen)
                  SizedBox(
                    height: kWindowCaptionHeight,
                    child: _buildTitleBarRow(context, stripColor),
                  ),
                // 路由内容区裁剪（物理兜底）：Flutter 不裁剪子节点绘制，页面转场的
                // 缩放/位移动画、浮层等一旦越界就会覆盖到 32px 标题条上（曾表现为
                // "进出视频页时页面瞬间叠在标题条之上"）。此处把内容区裁到标题条
                // 之下——等价于系统原生标题栏时代的客户区边界，标题条（含三键）
                // 恒不被任何页面内容覆盖。
                Expanded(child: ClipRect(child: widget.child)),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 32px 透明标题条：程序图标 + 名称 + 拖动区（含右键系统菜单）+ 右侧窗口控制三键。
  ///
  /// 条带为深色（如视频全屏纯黑）时，图标/名称/按钮自动切换为浅色（反色），保证可见。
  Widget _buildTitleBarRow(BuildContext context, Color stripColor) {
    final onDark = stripColor.computeLuminance() < 0.5;
    final brightness = onDark ? Brightness.dark : Brightness.light;
    final foreground = onDark
        ? AppColors.white.withValues(alpha: 0.92)
        : AppColors.black.withValues(alpha: 0.78);
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onSecondaryTap: () => windowManager.popUpWindowMenu(),
            child: DragToMoveArea(
              child: Row(
                children: [
                  const SizedBox(width: 10),
                  _dim(
                    Row(
                      children: [
                        // 程序图标（左键 = 系统菜单，与原生标题栏行为一致）。
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => windowManager.popUpWindowMenu(),
                          child: Image.asset(
                            'assets/app_icon.png',
                            width: 16,
                            height: 16,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 覆写 WidgetsApp 默认「黄绿双下划线」错误文本样式
                        // （壳层位于 Material 之外，与 app_messenger.dart 同款处理）。
                        DefaultTextStyle(
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.1,
                            fontWeight: FontWeight.w500,
                            color: foreground,
                            decoration: TextDecoration.none,
                          ),
                          child: const Text('WinWin'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(child: SizedBox.expand()),
                ],
              ),
            ),
          ),
        ),
        _dim(
          // ValueKey 随底色亮度变化强制重建：window_manager 的按钮字形画笔
          // shouldRepaint 恒返回 false，仅在重建后才会以新颜色重新绘制
          // （否则底色翻转后图标颜色要等到鼠标掠过重绘才更新）。
          Row(
            key: ValueKey(brightness),
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

  /// 窗口失焦时整体淡显（对齐原生标题栏的非激活观感）。
  Widget _dim(Widget child) => AnimatedOpacity(
        opacity: _isFocused ? 1 : 0.6,
        duration: const Duration(milliseconds: 150),
        child: child,
      );
}
