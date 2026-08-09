#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

// 单实例互斥锁：防止同一会话启动多个 WinWin 实例。
// 根因：Hive 以独占共享模式打开每个 Box 的 .lock 文件，两个实例共用
// %APPDATA%\com.winwin\winwin\hive\ 路径时，第二个实例会拿到
// ERROR_ACCESS_DENIED (errno=5)，从而首页推荐板块报
// PathAccessException 加载失败。命名前缀 Local\\ 表示仅限当前会话。
static constexpr const wchar_t* kSingleInstanceMutexName =
    L"Local\\winwin-single-instance-v1";

// 窗口标题与类名，用于把已存在实例提到前台。
static constexpr const wchar_t* kExistingWindowTitle = L"winwin";
static constexpr const wchar_t* kExistingWindowClass =
    L"FLUTTER_RUNNER_WIN32_WINDOW";

static void BringExistingWindowToForeground() {
  HWND existing = FindWindowW(kExistingWindowClass, kExistingWindowTitle);
  if (existing == nullptr) {
    return;
  }
  if (IsIconic(existing)) {
    ShowWindow(existing, SW_RESTORE);
  }
  // 交替调用 AllowSetForegroundWindow + SetForegroundWindow 绕过 Win32
  // 的前台窗口限制（第二个进程默认不能抢前台）。
  AllowSetForegroundWindow(ASFW_ANY);
  SetForegroundWindow(existing);
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // 第一个实例创建 mutex 成功；若已存在则把原窗口提到前台并立即退出。
  // mutex 句柄在进程退出时由 OS 自动释放，不需要显式 CloseHandle。
  HANDLE single_instance_mutex =
      CreateMutexW(nullptr, TRUE, kSingleInstanceMutexName);
  if (single_instance_mutex == nullptr) {
    return EXIT_FAILURE;
  }
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    CloseHandle(single_instance_mutex);
    BringExistingWindowToForeground();
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"winwin", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
