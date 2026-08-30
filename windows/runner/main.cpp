#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "blackbox.h"
#include "flutter_window.h"
#include "utils.h"

#ifdef NDEBUG
// 单实例互斥锁：防止同一会话启动多个 WinWin 实例。
// 根因：Hive 以独占共享模式打开每个 Box 的 .lock 文件，两个实例共用
// %APPDATA%\com.winwin\winwin\hive\ 路径时，第二个实例会拿到
// ERROR_ACCESS_DENIED (errno=5)，从而首页推荐板块报
// PathAccessException 加载失败。命名前缀 Local\\ 表示仅限当前会话。
static constexpr const wchar_t* kSingleInstanceMutexName =
    L"Local\\winwin-single-instance-v1";

// 窗口类名，用于把已存在实例提到前台。
static constexpr const wchar_t* kExistingWindowClass =
    L"FLUTTER_RUNNER_WIN32_WINDOW";

static bool BringExistingWindowToForeground() {
  HWND existing = FindWindowW(kExistingWindowClass, nullptr);
  if (existing == nullptr) {
    return false;
  }
  if (IsIconic(existing)) {
    ShowWindow(existing, SW_RESTORE);
  } else {
    ShowWindow(existing, SW_SHOW);
  }
  // 交替调用 AllowSetForegroundWindow + SetForegroundWindow 绕过 Win32
  // 的前台窗口限制（第二个进程默认不能抢前台）。
  AllowSetForegroundWindow(ASFW_ANY);
  SetForegroundWindow(existing);
  BringWindowToTop(existing);
  return true;
}
#endif

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // 确保工作目录（CWD）和 DLL 搜索目录与 exe 所在目录严格一致（消除终端与资源管理器启动差异）
  wchar_t exe_path[MAX_PATH] = {};
  GetModuleFileNameW(nullptr, exe_path, MAX_PATH);
  wchar_t* last_slash = wcsrchr(exe_path, L'\\');
  if (last_slash != nullptr) {
    *last_slash = L'\0';
    SetCurrentDirectoryW(exe_path);
    SetDllDirectoryW(exe_path);
  }

  // 检查当前线程是否处于 IDE 沙箱或隔离虚拟桌面（例如 exebox-*）
  // 仅在被隔离到非物理桌面时，自动挂载到用户的交互式物理桌面 WinSta0\Default
  char current_desktop[256] = {};
  HDESK h_current = GetThreadDesktop(GetCurrentThreadId());
  DWORD desk_len = 0;
  if (h_current != nullptr &&
      GetUserObjectInformationA(h_current, UOI_NAME, current_desktop,
                                sizeof(current_desktop), &desk_len)) {
    if (strstr(current_desktop, "exebox") != nullptr) {
      HWINSTA hwinsta = OpenWindowStationW(L"WinSta0", FALSE, WINSTA_ALL_ACCESS);
      if (hwinsta != nullptr) {
        SetProcessWindowStation(hwinsta);
      }
      HDESK default_desktop = OpenDesktopW(
          L"Default", 0, FALSE,
          DESKTOP_READOBJECTS | DESKTOP_WRITEOBJECTS | DESKTOP_CREATEWINDOW |
              DESKTOP_CREATEMENU | DESKTOP_HOOKCONTROL | DESKTOP_JOURNALRECORD |
              DESKTOP_JOURNALPLAYBACK | DESKTOP_ENUMERATE | DESKTOP_SWITCHDESKTOP);
      if (default_desktop == nullptr) {
        default_desktop = OpenInputDesktop(
            0, FALSE,
            DESKTOP_READOBJECTS | DESKTOP_WRITEOBJECTS | DESKTOP_CREATEWINDOW |
                DESKTOP_CREATEMENU | DESKTOP_HOOKCONTROL | DESKTOP_JOURNALRECORD |
                DESKTOP_JOURNALPLAYBACK | DESKTOP_ENUMERATE | DESKTOP_SWITCHDESKTOP);
      }
      if (default_desktop != nullptr) {
        SetThreadDesktop(default_desktop);
        CloseDesktop(default_desktop);
      }
      if (hwinsta != nullptr) {
        CloseWindowStation(hwinsta);
      }
    }
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // 黑箱：最先初始化，记录完整启动时间线（偶发启动白屏取证）。
  blackbox::Init();
  blackbox::Log("main", "wWinMain enter, pid=%lu", GetCurrentProcessId());

#ifdef NDEBUG
  // 第一个实例创建 mutex 成功；若已存在则把原窗口提到前台并立即退出。
  // mutex 句柄在进程退出时由 OS 自动释放，不需要显式 CloseHandle。
  // 仅在 Release 模式启用，避免 Debug 模式下 flutter run 发生调试锁死与秒退。
  HANDLE single_instance_mutex =
      CreateMutexW(nullptr, TRUE, kSingleInstanceMutexName);
  if (single_instance_mutex != nullptr &&
      GetLastError() == ERROR_ALREADY_EXISTS) {
    blackbox::Log("main", "second instance detected, attempting forward");
    if (BringExistingWindowToForeground()) {
      CloseHandle(single_instance_mutex);
      return EXIT_SUCCESS;
    }
    // 若原窗口在异常桌面或已失效，关闭锁并继续启动以确保用户能看到界面
    blackbox::Log("main", "existing window not found, continuing startup");
    CloseHandle(single_instance_mutex);
    single_instance_mutex = nullptr;
  }
#endif

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  // 黑箱：GPU 适配器/显示器环境（白屏常与 GPU 切换/驱动/远程会话相关）。
  blackbox::DumpGpuInfo();

  flutter::DartProject project(L"data");

  // Flutter 3.47 原生 Direct3D 11 / Impeller 渲染后端
  project.set_impeller_switch(flutter::ImpellerSwitch::Default);
  project.set_gpu_preference(flutter::GpuPreference::NoPreference);
  blackbox::Log("main",
                "DartProject created, Impeller Default (Direct3D 11)");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  blackbox::Log("main", "creating FlutterWindow 1280x720 @10,10");
  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"winwin", origin, size)) {
    blackbox::Log("main", "window.Create FAILED, gle=%lu", GetLastError());
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  blackbox::Log("main", "entering message loop");
  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }
  blackbox::Log("main", "message loop exited, process ending");

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
