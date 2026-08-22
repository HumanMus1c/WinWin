import 'dart:async' show unawaited;
import 'dart:io' show pid;

import 'package:catcher_2/catcher_2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fvp/mdk.dart' as mdk;

import 'core/bootstrap.dart';
import 'core/log/api_blackbox.dart';
import 'core/log/app_logger.dart';
import 'core/log/startup_blackbox.dart';
import 'core/log/sync_trace.dart';
import 'core/storage/storage_pref.dart';
import 'core/window/window_state_controller.dart';
import 'pages/onboarding/user_agreement_page.dart';
import 'pages/setting/theme_notifier.dart';
import 'pages/video/desktop_pip.dart';
import 'theme/app_font_notifier.dart';
import 'theme/app_theme.dart';
import 'theme/inherited_ui_style.dart';
import 'theme/ui_style.dart';
import 'theme/ui_style_notifier.dart';
import 'ui/app.dart';
import 'utils/json_file_handler.dart';

/// 全局路由观察器，供 VideoDetailPage 监听 push/pop 事件，
/// 在页面被覆盖时暂停播放器、返回时恢复播放。
final RouteObserver<PageRoute<dynamic>> routeObserver =
    RouteObserver<PageRoute<dynamic>>();

void main() async {
  // 黑箱：最先注册（偶发启动白屏取证；pending 缓冲保证早于 IO 就绪的
  // 事件也按序落盘），不阻塞启动。
  unawaited(StartupBlackbox.init());
  unawaited(ApiBlackbox.init());
  StartupBlackbox.log(
      'main', 'entered, release=$kReleaseMode, debug=$kDebugMode, pid=$pid');

  WidgetsFlutterBinding.ensureInitialized();
  StartupBlackbox.log('main', 'binding initialized');

  // 黑箱：首帧 FrameTiming + post-frame 里程碑 + 30s 帧心跳 + 生命周期。
  StartupBlackbox.attachFrameTracking();
  AppLifecycleListener(onStateChange: StartupBlackbox.logLifecycle);

  // Phase 4.6：初始化桌面伪 PiP 窗口管理器。
  unawaited(DesktopPipController.instance.ensureInitialized());

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

  // The video player kernel (fvp/mdk) needs no manual init here: the fvp
  // plugin's dartPluginClass auto-registers on startup (mdk key + globals).
  // The Windows runner shows the window only after the first frame renders,
  // so bootstrap (Hive → accounts → Dio) must not block runApp(). Controllers
  // await ensureBootstrap() themselves before touching the network.
  unawaited(
    ensureBootstrap().then((_) {
      ThemeNotifier.instance.refresh();
      // Phase 7.1：从持久化存储读取实际 UI 风格。
      UiStyleNotifier.instance.refresh();
      // 字体设置：从持久化存储读取并加载自定义字体（如有）。
      AppFontNotifier.instance.refresh();
      // 恢复上次窗口尺寸/位置/最大化状态，并开始监听变更以持久化。
      WindowStateController.instance.restoreAndListen();
    }),
  );

  // L5：崩溃捕获 — Catcher2 包装根 widget，handlers = [JsonFileHandler, ConsoleHandler]。
  // JsonFileHandler 把崩溃 Report 以 NDJSON 追加到 .winwin_logs.json。
  // 默认开启（L7 阶段接入 Pref.enableLog 后改为用户可控）。
  final jsonHandler = await JsonFileHandler.init();
  final handlers = <ReportHandler>[
    ?jsonHandler,
    ConsoleHandler(),
  ];
  StartupBlackbox.log('main', 'handing off to Catcher2 runApp');
  Catcher2(
    rootWidget: const WinWinApp(),
    debugConfig: Catcher2Options(SilentReportMode(), handlers),
    releaseConfig: Catcher2Options(SilentReportMode(), handlers),
  );
}

class WinWinApp extends StatelessWidget {
  const WinWinApp({super.key});

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
                    theme: AppTheme.lightFor(uiStyle, fontFamily: fontFamily),
                    darkTheme: AppTheme.darkFor(uiStyle, fontFamily: fontFamily),
                    themeMode: themeMode,
                    navigatorObservers: [routeObserver],
                    home: const AgreementGate(child: AppRoot()),
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
/// 在 [ensureBootstrap] 完成前显示加载占位（此时 Hive 尚未就绪，无法读取确认状态）；
/// 已确认 → 直接渲染 [child]（AppRoot）；未确认 → 展示 [UserAgreementPage]，
/// 确认后写回持久化并切换到主界面。不阻塞 runApp，遵守现有 bootstrap 约定。
class AgreementGate extends StatefulWidget {
  const AgreementGate({super.key, required this.child});

  final Widget child;

  @override
  State<AgreementGate> createState() => _AgreementGateState();
}

class _AgreementGateState extends State<AgreementGate> {
  /// null = bootstrap 进行中；true/false = 已读取确认状态。
  bool? _acked;

  @override
  void initState() {
    super.initState();
    StartupBlackbox.log('gate', 'AgreementGate initState, awaiting bootstrap');
    ensureBootstrap().then((_) {
      if (!mounted) return;
      final acked = Pref.userAgreementAck;
      StartupBlackbox.log('gate', 'bootstrap done, acked=$acked');
      setState(() => _acked = acked);
    });
  }

  @override
  Widget build(BuildContext context) {
    final acked = _acked;
    if (acked == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
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
