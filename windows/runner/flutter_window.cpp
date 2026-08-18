#include "flutter_window.h"

#include <optional>

#include "blackbox.h"
#include "flutter/generated_plugin_registrant.h"

namespace {
// WM 消息埋点限量（防日志风暴）。
constexpr int kMaxWmSizeLogs = 24;
constexpr int kMaxWmPaintLogs = 3;
constexpr int kMaxWmShowLogs = 6;
int g_wm_size_logged = 0;
int g_wm_paint_logged = 0;
int g_wm_show_logged = 0;
int g_wm_activate_logged = 0;
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  blackbox::Log("runner", "FlutterWindow::OnCreate enter");
  if (!Win32Window::OnCreate()) {
    blackbox::Log("runner", "Win32Window::OnCreate FAILED");
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    blackbox::Log("runner", "engine/view creation FAILED");
    return false;
  }
  blackbox::MarkControllerCreated();
  RegisterPlugins(flutter_controller_->engine());
  blackbox::Log("runner", "plugins registered");
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  blackbox::Log("runner", "child content attached");

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    // 黑箱：首帧呈现是启动白屏诊断的核心里程碑。
    blackbox::NotifyFirstFrame(GetHandle());
    this->Show();
    blackbox::Log("runner", "Show() after first frame done");
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();
  blackbox::Log("runner", "ForceRedraw requested");
  blackbox::StartPreFrameWatchdog(GetHandle());

  return true;
}

void FlutterWindow::OnDestroy() {
  blackbox::Log("runner", "FlutterWindow::OnDestroy");
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    // ---- 黑箱：窗口消息埋点（白屏取证关键信号）----
    case WM_SHOWWINDOW:
      if (g_wm_show_logged < kMaxWmShowLogs) {
        ++g_wm_show_logged;
        blackbox::Log("wm", "WM_SHOWWINDOW show=%d", (int)wparam);
      }
      break;
    case WM_ACTIVATE:
      if (g_wm_activate_logged < kMaxWmShowLogs) {
        ++g_wm_activate_logged;
        blackbox::Log("wm", "WM_ACTIVATE state=%lu minimized=%d",
                      (unsigned long)LOWORD(wparam), (int)HIWORD(wparam));
      }
      break;
    case WM_SIZE:
      // 窗口在首帧前被显示/最大化的证据（白屏头号嫌疑路径）。
      if (g_wm_size_logged < kMaxWmSizeLogs) {
        ++g_wm_size_logged;
        blackbox::Log("wm", "WM_SIZE type=%lu cx=%u cy=%u",
                      (unsigned long)wparam, (unsigned)LOWORD(lparam),
                      (unsigned)HIWORD(lparam));
      }
      break;
    case WM_DPICHANGED:
      blackbox::Log("wm", "WM_DPICHANGED dpi=%u", (unsigned)HIWORD(wparam));
      break;
    case WM_PAINT:
      // 父窗口收到 WM_PAINT 说明系统要求重绘（Flutter 未呈现时的白屏现场）。
      if (g_wm_paint_logged < kMaxWmPaintLogs) {
        ++g_wm_paint_logged;
        blackbox::Log("wm", "WM_PAINT (parent window)");
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
