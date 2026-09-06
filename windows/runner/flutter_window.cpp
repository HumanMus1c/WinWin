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
            auto color_it = args->find(flutter::EncodableValue("color"));
            auto text_color_it = args->find(flutter::EncodableValue("textColor"));
            auto dark_it = args->find(flutter::EncodableValue("dark"));
            if (color_it != args->end() && dark_it != args->end()) {
              int64_t color_val = 0;
              if (std::holds_alternative<int32_t>(color_it->second)) {
                color_val = std::get<int32_t>(color_it->second);
              } else if (std::holds_alternative<int64_t>(color_it->second)) {
                color_val = std::get<int64_t>(color_it->second);
              }

              int64_t text_color_val = 0;
              if (text_color_it != args->end()) {
                if (std::holds_alternative<int32_t>(text_color_it->second)) {
                  text_color_val = std::get<int32_t>(text_color_it->second);
                } else if (std::holds_alternative<int64_t>(text_color_it->second)) {
                  text_color_val = std::get<int64_t>(text_color_it->second);
                }
              }

              bool is_dark = std::get<bool>(dark_it->second);

              COLORREF caption_color = RGB((color_val >> 16) & 0xFF,
                                           (color_val >> 8) & 0xFF,
                                           color_val & 0xFF);
              COLORREF text_color = (text_color_it != args->end())
                  ? RGB((text_color_val >> 16) & 0xFF,
                        (text_color_val >> 8) & 0xFF,
                        text_color_val & 0xFF)
                  : (is_dark ? RGB(0xE8, 0xE8, 0xE8) : RGB(0x18, 0x19, 0x1C));

              this->SetTitleBarColor(caption_color, text_color, is_dark);
              result->Success();
              return;
            }
          }
          result->Error("INVALID_ARGUMENTS", "Invalid arguments for setTitleBarColor");
          return;
        }
        result->NotImplemented();
      });

  // 显式显示窗口，避免因首帧回调在无焦点/非前台或命令行启动环境下被 DWM 挂起而导致窗口永久隐藏
  this->Show();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
    ::SetWindowPos(GetHandle(), HWND_TOP, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
    ::SetForegroundWindow(GetHandle());
    ::BringWindowToTop(GetHandle());
  });

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
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
