#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

// 单实例互斥锁：防止同一会话启动多个 WinWin 实例导致 Hive 数据库文件锁冲突
static constexpr const wchar_t* kSingleInstanceMutexName =
    L"Local\\winwin-single-instance-v1";
static constexpr const wchar_t* kExistingWindowClass =
    L"FLUTTER_RUNNER_WIN32_WINDOW";

static bool BringExistingWindowToForeground() {
  HWND existing = FindWindowW(kExistingWindowClass, L"winwin");
  if (existing == nullptr) {
    existing = FindWindowW(kExistingWindowClass, nullptr);
  }
  if (existing == nullptr) {
    return false;
  }
  if (IsIconic(existing)) {
    ShowWindow(existing, SW_RESTORE);
  } else {
    ShowWindow(existing, SW_SHOW);
  }
  AllowSetForegroundWindow(ASFW_ANY);
  SetForegroundWindow(existing);
  BringWindowToTop(existing);
  return true;
}

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

  // 检查是否已有实例运行，若是则呼出已有窗口并退出，避免 Hive 文件锁冲突
  HANDLE single_instance_mutex =
      CreateMutexW(nullptr, TRUE, kSingleInstanceMutexName);
  if (single_instance_mutex != nullptr &&
      GetLastError() == ERROR_ALREADY_EXISTS) {
    if (BringExistingWindowToForeground()) {
      CloseHandle(single_instance_mutex);
      return EXIT_SUCCESS;
    }
    CloseHandle(single_instance_mutex);
    single_instance_mutex = nullptr;
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

  // Flutter 3.47 Windows 默认启用 Impeller 渲染后端，其外部视频纹理
  //（fvp DXGI shared handle）在路由转场场景变化时光栅线程空指针崩溃
  //（flutter_windows.dll+0x2C55F7，播放中返回必崩）。回退 Skia 后端规避。
  project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);

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
  if (single_instance_mutex != nullptr) {
    CloseHandle(single_instance_mutex);
  }
  // 强行终止进程内所有插件与底层后台工作线程（如 MDK、WebView2、Dart worker），
  // 确保彻底释放 Hive 数据库排他锁，杜绝后台僵尸进程
  ::ExitProcess(EXIT_SUCCESS);
  return EXIT_SUCCESS;
}
