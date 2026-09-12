#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  title_bar_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "winwin/window_title_bar",
          &flutter::StandardMethodCodec::GetInstance());

  title_bar_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "setTitleBarColor") {
          const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
          if (args != nullptr) {
            auto dark_it = args->find(flutter::EncodableValue("dark"));
            if (dark_it != args->end() &&
                std::holds_alternative<bool>(dark_it->second)) {
              bool is_dark = std::get<bool>(dark_it->second);
              this->SetTitleBarColor(is_dark);
              result->Success();
              return;
            }
          }
          result->Error("INVALID_ARGUMENTS", "Invalid arguments for setTitleBarColor");
          return;
        }
        result->NotImplemented();
      });

  fullscreen_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "winwin/fullscreen",
          &flutter::StandardMethodCodec::GetInstance());

  fullscreen_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "enterFullScreen") {
          this->SetFullScreen(true);
          result->Success(flutter::EncodableValue(true));
          return;
        } else if (call.method_name() == "exitFullScreen") {
          this->SetFullScreen(false);
          result->Success(flutter::EncodableValue(false));
          return;
        } else if (call.method_name() == "isFullScreen") {
          result->Success(flutter::EncodableValue(this->IsFullScreen()));
          return;
        }
        result->NotImplemented();
      });

  mediakit_video_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "com.alexmercerind/media_kit_video",
          &flutter::StandardMethodCodec::GetInstance());

  mediakit_video_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "Utils.EnterNativeFullscreen") {
          this->SetFullScreen(true);
          result->Success();
          return;
        } else if (call.method_name() == "Utils.ExitNativeFullscreen") {
          this->SetFullScreen(false);
          result->Success();
          return;
        } else if (call.method_name() == "Utils.IsNativeFullscreen") {
          result->Success(flutter::EncodableValue(this->IsFullScreen()));
          return;
        }
        result->NotImplemented();
      });

  // flutter_controller_->engine()->SetNextFrameCallback([&]() {
  //   this->Show();
  // });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (title_bar_channel_) {
    title_bar_channel_ = nullptr;
  }
  if (fullscreen_channel_) {
    fullscreen_channel_ = nullptr;
  }
  if (mediakit_video_channel_) {
    mediakit_video_channel_ = nullptr;
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // 全屏状态下优先处理非客户区与尺寸限制，避免第三方插件（如 window_manager）
  // 错误钳制显示器全屏尺寸或保留标题栏
  if (IsFullScreen()) {
    if (message == WM_NCCALCSIZE) {
      return 0;
    }
    if (message == WM_GETMINMAXINFO) {
      MINMAXINFO* mmi = reinterpret_cast<MINMAXINFO*>(lparam);
      HMONITOR hMonitor = ::MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
      MONITORINFO mi = {sizeof(MONITORINFO)};
      if (::GetMonitorInfo(hMonitor, &mi)) {
        LONG width = mi.rcMonitor.right - mi.rcMonitor.left;
        LONG height = mi.rcMonitor.bottom - mi.rcMonitor.top;
        mmi->ptMaxSize.x = width;
        mmi->ptMaxSize.y = height;
        mmi->ptMaxPosition.x = mi.rcMonitor.left;
        mmi->ptMaxPosition.y = mi.rcMonitor.top;
        mmi->ptMaxTrackSize.x = width;
        mmi->ptMaxTrackSize.y = height;
        return 0;
      }
    }
  }

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
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
