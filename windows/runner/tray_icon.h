// AI生成
#ifndef RUNNER_TRAY_ICON_H_
#define RUNNER_TRAY_ICON_H_

#include <windows.h>

#include <functional>
#include <string>

// 托盘图标自定义消息（Win32 自定义区间 WM_APP 起）。
// 由主窗口的 WndProc 收到后转发给 TrayIcon::HandleMessage。
#define WM_WINWIN_TRAY (WM_APP + 1)

// 托盘交互事件（转发给 Flutter 层的语义事件）。
enum class TrayEvent {
  kShow,  // 左键单击/双击：请求显示主窗口
  kExit,  // 菜单「退出」：请求真正退出应用
};

// 纯原生 Windows 系统托盘（Shell_NotifyIcon），不依赖任何第三方包。
//
// 设计：托盘消息宿主复用主窗口 HWND（不额外创建隐藏窗口），
// uCallbackMessage = WM_WINWIN_TRAY，由 FlutterWindow::MessageHandler 转发。
// 事件不直接操作窗口/进程，而是通过回调抛给 FlutterWindow，再由其经
// MethodChannel 通知 Dart 层处理（保证退出/显示逻辑单点可控）。
class TrayIcon {
 public:
  TrayIcon();
  ~TrayIcon();

  // 以 |owner| 为消息宿主显示托盘图标；|tip| 为悬停提示，|icon| 为图标。
  // 重复调用（已显示时）走 NIM_MODIFY 刷新，避免重复添加产生“幽灵图标”。
  void Show(HWND owner, const std::wstring& tip, HICON icon);

  // 移除托盘图标；未显示时为空操作。
  void Hide();

  bool visible() const { return visible_; }

  // 注入事件回调（由 FlutterWindow 在创建托盘前设置）。
  void SetEventCallback(std::function<void(TrayEvent)> callback) {
    callback_ = std::move(callback);
  }

  // 处理来自主窗口的托盘消息；返回 true 表示已消费。
  bool HandleMessage(HWND owner, WPARAM wparam, LPARAM lparam);

 private:
  void ShowContextMenu(HWND owner);

  NOTIFYICONDATAW nid_ = {};
  bool visible_ = false;
  std::function<void(TrayEvent)> callback_;
};

#endif  // RUNNER_TRAY_ICON_H_