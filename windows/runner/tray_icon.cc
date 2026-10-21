#include "tray_icon.h"

#include "resource.h"

namespace {

constexpr UINT kMenuShow = 1;
constexpr UINT kMenuExit = 2;

}  // namespace

TrayIcon::TrayIcon() {
  nid_.cbSize = sizeof(NOTIFYICONDATAW);
  nid_.uID = 1;
  nid_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  nid_.uCallbackMessage = WM_WINWIN_TRAY;
}

TrayIcon::~TrayIcon() {
  Hide();
}

void TrayIcon::Show(HWND owner, const std::wstring& tip, HICON icon) {
  nid_.hWnd = owner;
  nid_.hIcon = icon;
  nid_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  wcsncpy_s(nid_.szTip, tip.c_str(), _TRUNCATE);

  if (visible_) {
    // 已显示：仅刷新图标与提示，避免重复 NIM_ADD 产生“幽灵图标”。
    Shell_NotifyIconW(NIM_MODIFY, &nid_);
    return;
  }
  if (Shell_NotifyIconW(NIM_ADD, &nid_)) {
    visible_ = true;
  }
}

void TrayIcon::Hide() {
  if (!visible_) return;
  Shell_NotifyIconW(NIM_DELETE, &nid_);
  visible_ = false;
}

bool TrayIcon::HandleMessage(HWND owner, WPARAM wparam, LPARAM lparam) {
  if (!visible_) return false;
  if (static_cast<UINT>(wparam) != nid_.uID) return false;

  switch (LOWORD(lparam)) {
    case WM_LBUTTONUP:
    case WM_LBUTTONDBLCLK:
      if (callback_) callback_(TrayEvent::kShow);
      return true;
    case WM_RBUTTONUP:
    case WM_CONTEXTMENU:
      ShowContextMenu(owner);
      return true;
    default:
      return false;
  }
}

void TrayIcon::ShowContextMenu(HWND owner) {
  POINT cursor;
  if (!GetCursorPos(&cursor)) return;

  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) return;
  AppendMenuW(menu, MF_STRING, kMenuShow, L"显示主窗口");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kMenuExit, L"退出 WinWin");

  // 托盘菜单惯例：先置前台，再 TrackPopupMenu，否则菜单不会随点击外部消失。
  SetForegroundWindow(owner);
  const UINT cmd = TrackPopupMenu(menu,
                                  TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY,
                                  cursor.x, cursor.y, 0, owner, nullptr);
  DestroyMenu(menu);

  if (cmd == kMenuShow) {
    if (callback_) callback_(TrayEvent::kShow);
  } else if (cmd == kMenuExit) {
    if (callback_) callback_(TrayEvent::kExit);
  }
}