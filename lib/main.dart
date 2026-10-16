import 'dart:async' show unawaited;
import 'dart:io' show Platform, pid;

import 'package:catcher_2/catcher_2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:fvp/mdk.dart' as mdk;
import 'package:window_manager/window_manager.dart' hide calcWindowPosition;

import 'core/bootstrap.dart';
import 'core/input/app_escape_scope.dart';
import 'core/log/api_blackbox.dart';
import 'core/log/app_logger.dart';
import 'core/log/sync_trace.dart';
import 'core/player/seek_probe.dart';
import 'core/perf/transition_probe.dart';
import 'core/shell/app_scaffold.dart';
import 'core/shell/app_shell.dart';
import 'core/shell/app_theme_host.dart';
import 'core/storage/storage_pref.dart';
import 'core/window/title_bar_controller.dart';
import 'core/window/window_state_controller.dart';
import 'pages/onboarding/user_agreement_page.dart';
import 'pages/setting/theme_notifier.dart';
import 'pages/video/desktop_pip.dart';
import 'theme/app_font_notifier.dart';
import 'theme/app_theme.dart';
import 'theme/colors.dart';
import 'ui/app.dart';
import 'utils/calc_window_position.dart';
import 'utils/json_file_handler.dart';
import 'package:winwin/theme/app_colors.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/ui/components/app_progress.dart';
import 'package:winwin/ui/components/app_components.dart';

/// 全局路由观察器，供 VideoDetailPage 监听 push/pop 事件，
/// 在页面被覆盖时暂停播放器、返回时恢复播放。
final RouteObserver<PageRoute<dynamic>> routeObserver =
    RouteObserver<PageRoute<dynamic>>();

/// 根 Navigator 引用：供全局 Esc 路由器（[AppEscapeScope]）执行 maybePop。
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// 全局 Esc 路由器的路由栈观察器（判断栈顶是否为弹层路由）。
final AppEscapeNavigatorObserver appEscapeObserver =
    AppEscapeNavigatorObserver();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 图片内存缓存容量：128MB / 1000 items。
  // 原为 256MB；2026-09-27/28 内存调查确认"解码位图在重度浏览后会常驻放大"，
  // 实测峰值用量约 86MB（191 张），128MB 上限足以覆盖正常滚动窗口，
  // 同时避免缓存上限本身抬高常驻内存水位（Flutter 默认 100MB）。
  PaintingBinding.instance.imageCache.maximumSizeBytes = 128 << 20;
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

  // 深度网络黑箱（仅 debug）：完整请求/响应链路（Cookie 脱敏）落盘供排障；
  // release 不初始化、不落盘（拦截器同样仅 debug 挂载），零开销。
  if (kDebugMode) {
    unawaited(ApiBlackbox.init());
  }

  // Seek 取证探针（诊断用）：读取 Documents/logs/seek_probe.json 选择 A/B 变体。
  await SeekProbe.init();

  // 页面转场探针（诊断用）：读取 Documents/logs/transition_probe.json；
  // 启用后记录每次转场的用时与逐帧 build/raster 耗时（默认关闭=零开销）。
  await TransitionProbe.init();

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
        // mdk 已知无害噪声：请求的状态变换与当前一致（如播放完成后再 pause）。
        // 2026-09 日志审计实测 24 次均无功能影响；降级为调试级避免污染
        // release 运行日志，排查播放状态问题时可在 debug 构建中查看。
        if (msg.endsWith('state not changed!')) {
          AppLogger.d('fvp', msg);
        } else {
          AppLogger.e('fvp', msg);
        }
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

  // Windows 平台开启 D3D11 CPU-GPU 同步屏障，根除 Flutter Texture 纹理读取与 MDK 解码表面之间的时序撕裂与新旧画面闪烁
  if (Platform.isWindows) {
    mdk.setGlobalOption('d3d11.sync.cpu', 1);
  }

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
    AppFontNotifier.instance.refresh();
    Pref.refreshDemoMode();
    TitleBarController.instance.update();
  } catch (error, stackTrace) {
    bootstrapError = error;
    SyncTrace.log('main', 'ensureBootstrap failed: $error');
    AppLogger.e('main', 'ensureBootstrap failed',
        error: error, stackTrace: stackTrace);
  }

  if ((Platform.isWindows || Platform.isMacOS || Platform.isLinux) &&
      bootstrapError == null) {
    final windowOptions = WindowOptions(
      minimumSize: const Size(640, 400),
      skipTaskbar: false,
      titleBarStyle: Pref.useNativeTitleBar
          ? TitleBarStyle.normal
          : TitleBarStyle.hidden,
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

class WinWinApp extends StatelessWidget {
  const WinWinApp({super.key, this.bootstrapError});

  final Object? bootstrapError;

  @override
  Widget build(BuildContext context) {
    // 两层 ValueListenableBuilder — 主题模式 × 应用字体，任一变化重建应用壳。
    // （B1：应用壳由 MaterialApp 换为 AppShell（WidgetsApp + AppThemeHost +
    //  过渡期 Material 主题）；主题模式为项目枚举 ThemeModeType，不再依赖
    //  Material 的 ThemeMode。）
    return ValueListenableBuilder<ThemeModeType>(
      valueListenable: ThemeNotifier.instance,
      builder: (context, themeMode, _) {
        return ValueListenableBuilder<String>(
          valueListenable: AppFontNotifier.instance,
          builder: (context, fontFamily, _) {
            final isDark = themeMode.resolveIsDark(
              MediaQuery.platformBrightnessOf(context),
            );
            return AppShell(
              title: 'WinWin — BiliPai Desktop Port',
              isDark: isDark,
              fontFamily: fontFamily,
              theme: isDark
                  ? AppTheme.darkFor(fontFamily: fontFamily)
                  : AppTheme.lightFor(fontFamily: fontFamily),
              navigatorKey: appNavigatorKey,
              escapeObserver: appEscapeObserver,
              navigatorObservers: [routeObserver, appEscapeObserver],
              home: AgreementGate(
                bootstrapError: bootstrapError,
                child: const AppRoot(),
              ),
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
      AppFontNotifier.instance.refresh();
      Pref.refreshDemoMode();
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
    final bootstrapError = _bootstrapError;
    if (bootstrapError != null) {
      final isDark = AppThemeHost.of(context).isDark;
      final errStr = bootstrapError.toString();
      final isLockError = errStr.contains('33') ||
          errStr.contains('锁定') ||
          errStr.contains('locked');
      final tip = isLockError
          ? '数据文件被锁定，可能由于另一个 WinWin 实例正在运行或上次未完全退出。\n请在任务管理器中结束残留的 winwin.exe 进程后重试。'
          : '资源载入失败：$errStr';
      return AppScaffold(
        backgroundColor:
            isDark ? const Color(0xFF18191C) : const Color(0xFFF1F2F5),
        // 启动门禁面板（异常 / 加载）：无顶部安全行、无返回按钮，纯居中内容。
        reserveTopStrip: false,
        body: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 30),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF222429) : AppColors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.black.withValues(alpha: isDark ? 0.3 : 0.06),
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
                    color: AppColors.redAccent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: AppIcon(AppIcons.error(),
                      size: 28,
                      color: AppColors.redAccent,
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
                AppPrimaryButton(onPressed: _load, child: const Text('重试')),
              ],
            ),
          ),
        ),
      );
    }

    final acked = _acked;
    if (acked == null) {
      final isDark = AppThemeHost.of(context).isDark;
      return AppScaffold(
        backgroundColor:
            isDark ? const Color(0xFF18191C) : const Color(0xFFF1F2F5),
        // 启动门禁面板（异常 / 加载）：无顶部安全行、无返回按钮，纯居中内容。
        reserveTopStrip: false,
        body: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 30),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF222429) : AppColors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.black.withValues(alpha: isDark ? 0.3 : 0.06),
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
                      child: AppProgressIndicator(
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
