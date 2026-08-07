import 'package:flutter/scheduler.dart';

/// 启动任务编排 — 从 BiliPai AppStartupTask.kt + AppStartupOrchestrator.kt 移植。
///
/// 适配 Flutter 桌面端：
/// - MAIN → 同步执行
/// - MAIN_DELAYED → Future.delayed
/// - MAIN_IDLE → SchedulerBinding.addPostFrameCallback（替代 Android IdleHandler）

enum StartupPhase {
  beforeFirstInteractive,
  afterFirstInteractive,
}

enum StartupCriticality {
  required,
  deferred,
}

enum StartupThread {
  main,
  mainDelayed,
  mainIdle,
}

class AppStartupTask {
  final String id;
  final StartupPhase phase;
  final StartupCriticality criticality;
  final StartupThread thread;
  final Duration delay;

  const AppStartupTask({
    required this.id,
    required this.phase,
    required this.criticality,
    required this.thread,
    this.delay = Duration.zero,
  });
}

/// 启动编排器：先执行首屏前必需任务，再调度延迟任务。
class AppStartupOrchestrator {
  final List<AppStartupTask> _tasks;

  AppStartupOrchestrator(this._tasks);

  List<AppStartupTask> get tasks => List.unmodifiable(_tasks);

  /// 执行首屏前必需任务（同步）。
  Future<void> runImmediate(
    Future<void> Function(AppStartupTask task) taskRunner,
  ) async {
    for (final task in _tasks) {
      if (task.phase == StartupPhase.beforeFirstInteractive &&
          task.criticality == StartupCriticality.required) {
        await taskRunner(task);
      }
    }
  }

  /// 调度延迟任务（首帧后）。
  void scheduleDeferred(
    Future<void> Function(AppStartupTask task) taskRunner,
  ) {
    final deferred = _tasks
        .where((t) =>
            t.phase == StartupPhase.afterFirstInteractive ||
            t.criticality == StartupCriticality.deferred)
        .toList();

    for (final task in deferred) {
      switch (task.thread) {
        case StartupThread.main:
          taskRunner(task);
          break;
        case StartupThread.mainDelayed:
          Future.delayed(task.delay, () => taskRunner(task));
          break;
        case StartupThread.mainIdle:
          // 首帧回调替代 Android IdleHandler
          SchedulerBinding.instance.addPostFrameCallback(
            (_) => taskRunner(task),
          );
          break;
      }
    }
  }
}

/// WinWin 默认启动任务列表。
///
/// 顺序依赖：storage → accounts → request → accountService.restore。
/// 其余任务延迟到首帧后执行。
List<AppStartupTask> defaultAppStartupTasks() {
  return const [
    AppStartupTask(
      id: 'storage_init',
      phase: StartupPhase.beforeFirstInteractive,
      criticality: StartupCriticality.required,
      thread: StartupThread.main,
    ),
    AppStartupTask(
      id: 'accounts_init',
      phase: StartupPhase.beforeFirstInteractive,
      criticality: StartupCriticality.required,
      thread: StartupThread.main,
    ),
    AppStartupTask(
      id: 'request_init',
      phase: StartupPhase.beforeFirstInteractive,
      criticality: StartupCriticality.required,
      thread: StartupThread.main,
    ),
    AppStartupTask(
      id: 'account_restore',
      phase: StartupPhase.beforeFirstInteractive,
      criticality: StartupCriticality.required,
      thread: StartupThread.main,
    ),
    AppStartupTask(
      id: 'play_url_cache_warmup',
      phase: StartupPhase.afterFirstInteractive,
      criticality: StartupCriticality.deferred,
      thread: StartupThread.mainIdle,
    ),
    AppStartupTask(
      id: 'url_parser_init',
      phase: StartupPhase.afterFirstInteractive,
      criticality: StartupCriticality.deferred,
      thread: StartupThread.mainIdle,
    ),
  ];
}
