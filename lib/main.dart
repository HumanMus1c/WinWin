import 'dart:async' show unawaited;
import 'dart:io' show Platform, pid;
import 'dart:ui' show PointerDeviceKind;

import 'package:catcher_2/catcher_2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fvp/mdk.dart' as mdk;
import 'package:window_manager/window_manager.dart' hide calcWindowPosition;

import 'core/bootstrap.dart';
import 'core/log/app_logger.dart';
import 'core/log/sync_trace.dart';
import 'core/storage/storage_pref.dart';
import 'core/window/title_bar_controller.dart';
import 'core/window/window_state_controller.dart';
import 'pages/onboarding/user_agreement_page.dart';
import 'pages/setting/theme_notifier.dart';
import 'pages/video/desktop_pip.dart';
import 'theme/app_font_notifier.dart';
import 'theme/app_theme.dart';
import 'theme/colors.dart';
import 'theme/inherited_ui_style.dart';
import 'theme/ui_style.dart';
import 'theme/ui_style_notifier.dart';
import 'ui/app.dart';
import 'utils/calc_window_position.dart';
import 'utils/json_file_handler.dart';

/// 全局路由观察器，供 VideoDetailPage 监听 push/pop 事件，
/// 在页面被覆盖时暂停播放器、返回时恢复播放。
final RouteObserver<PageRoute<dynamic>> routeObserver =
    RouteObserver<PageRoute<dynamic>>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 性能优化：为网格/瀑布流海量封面扩大图片内存缓存容量（256MB / 1000 items）
  // 避免高频滑动时的 cache eviction 与频繁重新解码。
  PaintingBinding.instance.imageCache.maximumSizeBytes = 256 << 20;
  PaintingBinding.instance.imageCache.maximumSize = 1000;

  // Phase 4.6：初始化桌面伪 PiP 窗口管理器。
  unawaited(DesktopPipController.instance.ensureInitialized());

  // Windows 原生标题栏沉浸色彩同步。
  TitleBarController.instance.init();

  // 日志系统初始化（L2-L4）：内存环形缓冲 + 异步落盘。
  // 不阻塞 runApp：LogCollector.init 失败时降级为仅内存缓冲，不影响启动。
  unawaited(AppLogger.init());

  // 同步崩溃安全追踪（诊断用）：关键生命周期埋点，瞬死不丢尾部。
  unawaited(SyncTrace.init());
  SyncTrace.log('main', 'app starting, pid=$pid');

  // L6：fvp 播放器日志接入。
  // setLogHandler 接收 mdk 内部日志，分级映射到 AppLogger。
  // 过滤高频常规日志，仅对 warning/error 始终记录；info 仅在 debug 模式下输出。
  mdk.setLogHandler((level, msg) {
    if (level == mdk.LogLevel.off || level == mdk.LogLevel.all) return;
    if (msg.endsWith('\n')) {
      msg = msg.substring(0, msg.length - 1);
    }
    switch (level) {
      case mdk.LogLevel.error:
        AppLogger.e('fvp', msg);
      case mdk.LogLevel.warning:
        AppLogger.w('fvp', msg);
      case mdk.LogLevel.info:
        if (kDebugMode) {
          AppLogger.i('fvp', msg);
        }
      case mdk.LogLevel.debug:
      case mdk.LogLevel.all:
      case mdk.LogLevel.off:
        break;
    }
  });

  // 对标 PiliPlus 极速启动架构：
  // 极轻量本地存储 bootstrap（Hive/Accounts/Request，仅耗时十数毫秒）与 windowManager 并行执行。
  Object? bootstrapError;
  try {
    await Future.wait([
      ensureBootstrap(),
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux)
        windowManager.ensureInitialized(),
    ]);
    ThemeNotifier.instance.refresh();
    UiStyleNotifier.instance.refresh();
    AppFontNotifier.instance.refresh();
  } catch (error, stackTrace) {
    bootstrapError = error;
    SyncTrace.log('main', 'ensureBootstrap failed: $error');
    AppLogger.e('main', 'ensureBootstrap failed',
        error: error, stackTrace: stackTrace);
  }

  if ((Platform.isWindows || Platform.isMacOS || Platform.isLinux) &&
      bootstrapError == null) {
    const windowOptions = WindowOptions(
      minimumSize: Size(640, 400),
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: 'WinWin',
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      final windowSize = WindowStateController.instance.savedWindowSize;
      await windowManager.setBounds(
        await calcWindowPosition(windowSize) & windowSize,
      );
      if (WindowStateController.instance.isMaximized) {
        await windowManager.maximize();
      }
      await windowManager.show();
      await windowManager.focus();
      WindowStateController.instance.startListening();
    });
  }

  // 崩溃捕获与启动
  JsonFileHandler? jsonHandler;
  try {
    jsonHandler = await JsonFileHandler.init();
  } catch (_) {}
  final handlers = <ReportHandler>[
    ?jsonHandler,
    ConsoleHandler(),
  ];
  Catcher2(
    rootWidget: WinWinApp(bootstrapError: bootstrapError),
    debugConfig: Catcher2Options(SilentReportMode(), handlers),
    releaseConfig: Catcher2Options(SilentReportMode(), handlers),
  );
}

/// 全局平滑滚动行为配置。
///
/// 解决 Windows 桌面端默认 [ClampingScrollPhysics] 滚轮步进僵硬卡手的问题，
/// 开启弹性动量插值物理，并允许鼠标/触控板/触屏全设备指针平滑滚动。
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(
      parent: AlwaysScrollableScrollPhysics(),
    );
  }
}

class WinWinApp extends StatelessWidget {
  const WinWinApp({super.key, this.bootstrapError});

  final Object? bootstrapError;

  @override
  Widget build(BuildContext context) {
    // 三层 ValueListenableBuilder — UI 风格 × 主题模式 × 应用字体。
    // 任意一个变化都会重建 MaterialApp + UiStyleScope，实现热切换。
    return ValueListenableBuilder<UiStyle>(
      valueListenable: UiStyleNotifier.instance,
      builder: (context, uiStyle, _) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: ThemeNotifier.instance,
          builder: (context, themeMode, _) {
            return ValueListenableBuilder<String>(
              valueListenable: AppFontNotifier.instance,
              builder: (context, fontFamily, _) {
                return UiStyleScope(
                  style: uiStyle,
                  child: MaterialApp(
                    title: 'WinWin — BiliPai Desktop Port',
                    debugShowCheckedModeBanner: false,
                    scrollBehavior: const AppScrollBehavior(),
                    theme: AppTheme.lightFor(uiStyle, fontFamily: fontFamily),
                    darkTheme: AppTheme.darkFor(uiStyle, fontFamily: fontFamily),
                    themeMode: themeMode,
                    navigatorObservers: [routeObserver],
                    builder: (context, child) => UiStyleScope(
                      style: uiStyle,
                      child: child ?? const SizedBox.shrink(),
                    ),
                    home: AgreementGate(
                      bootstrapError: bootstrapError,
                      child: const AppRoot(),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

/// 用户协议门禁壳层。
///
/// 在本地存储就绪后直接根据持久化状态秒开渲染 [child]（AppRoot）；
/// 未确认时展示 [UserAgreementPage]，确认后写回持久化并切换到主界面；
/// 异常（如多开文件锁定）时展示居中重试面板。
class AgreementGate extends StatefulWidget {
  const AgreementGate({super.key, required this.child, this.bootstrapError});

  final Widget child;
  final Object? bootstrapError;

  @override
  State<AgreementGate> createState() => _AgreementGateState();
}

class _AgreementGateState extends State<AgreementGate> {
  /// null = bootstrap 进行中；true/false = 已读取确认状态。
  bool? _acked;
  Object? _bootstrapError;

  @override
  void initState() {
    super.initState();
    _bootstrapError = widget.bootstrapError;
    if (_bootstrapError == null) {
      try {
        _acked = Pref.userAgreementAck;
      } catch (_) {
        _acked = null;
      }
    }
    if (_acked == null && _bootstrapError == null) {
      _load();
    }
  }

  void _load() {
    setState(() {
      _acked = null;
      _bootstrapError = null;
    });
    ensureBootstrap().then((_) {
      ThemeNotifier.instance.refresh();
      UiStyleNotifier.instance.refresh();
      AppFontNotifier.instance.refresh();
      if (!mounted) return;
      final acked = Pref.userAgreementAck;
      setState(() {
        _acked = acked;
        _bootstrapError = null;
      });
    }).catchError((Object error, StackTrace stackTrace) {
      SyncTrace.log('AgreementGate', 'bootstrap failed: $error');
      AppLogger.e('AgreementGate', 'ensureBootstrap failed',
          error: error, stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _bootstrapError = error;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    InheritedUiStyle.of(context);
    final bootstrapError = _bootstrapError;
    if (bootstrapError != null) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final errStr = bootstrapError.toString();
      final isLockError = errStr.contains('33') ||
          errStr.contains('锁定') ||
          errStr.contains('locked');
      final tip = isLockError
          ? '数据文件被锁定，可能由于另一个 WinWin 实例正在运行或上次未完全退出。\n请在任务管理器中结束残留的 winwin.exe 进程后重试。'
          : '资源载入失败：$errStr';
      return Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF18191C) : const Color(0xFFF1F2F5),
        body: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 30),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF222429) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.error_outline,
                      size: 28,
                      color: Colors.redAccent,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '资源加载失败',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  tip,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: isDark
                        ? const Color(0xFF9499A0)
                        : const Color(0xFF61666D),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _load,
                  style: FilledButton.styleFrom(
                    backgroundColor: biliPink,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final acked = _acked;
    if (acked == null) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF18191C) : const Color(0xFFF1F2F5),
        body: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 30),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF222429) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: biliPink.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.8,
                        color: biliPink,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'WinWin',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '正在载入资源...',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? const Color(0xFF9499A0)
                        : const Color(0xFF61666D),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (acked) {
      return widget.child;
    }
    return UserAgreementPage(
      onAgreed: () async {
        await Pref.setUserAgreementAck(true);
        if (mounted) setState(() => _acked = true);
      },
    );
  }
}
