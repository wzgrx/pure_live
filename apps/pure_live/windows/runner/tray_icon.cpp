#include "tray_icon.h"

#include <cwchar>

#include "resource.h"

namespace {

constexpr UINT kTrayIconId = 1;

}  // namespace

TrayIcon::TrayIcon(HWND window, UINT callback_message)
    : window_(window), callback_message_(callback_message) {}

TrayIcon::~TrayIcon() {
  Hide();
  if (icon_ != nullptr) {
    ::DestroyIcon(icon_);
    icon_ = nullptr;
  }
}

NOTIFYICONDATAW TrayIcon::Data() const {
  NOTIFYICONDATAW data = {};
  data.cbSize = sizeof(data);
  data.hWnd = window_;
  data.uID = kTrayIconId;
  return data;
}

void TrayIcon::Show(const std::wstring& tooltip) {
  tooltip_ = tooltip;
  if (icon_ == nullptr) {
    icon_ = static_cast<HICON>(::LoadImageW(
        ::GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
        ::GetSystemMetrics(SM_CXSMICON), ::GetSystemMetrics(SM_CYSMICON),
        LR_DEFAULTCOLOR));
  }
  NOTIFYICONDATAW data = Data();
  data.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  data.uCallbackMessage = callback_message_;
  data.hIcon = icon_;
  wcsncpy_s(data.szTip, tooltip_.c_str(), _TRUNCATE);
  if (visible_ && ::Shell_NotifyIconW(NIM_MODIFY, &data)) {
    return;
  }
  visible_ = ::Shell_NotifyIconW(NIM_ADD, &data) != FALSE;
}

void TrayIcon::Hide() {
  if (!visible_) {
    return;
  }
  NOTIFYICONDATAW data = Data();
  ::Shell_NotifyIconW(NIM_DELETE, &data);
  visible_ = false;
}

void TrayIcon::Restore() {
  if (!visible_) {
    return;
  }
  // Explorer lost every icon; add ours again.
  visible_ = false;
  Show(tooltip_);
}

UINT TrayIcon::ShowMenu(const std::vector<MenuItem>& items) {
  HMENU menu = ::CreatePopupMenu();
  if (menu == nullptr) {
    return 0;
  }
  for (const auto& item : items) {
    if (item.id == 0) {
      ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    } else {
      ::AppendMenuW(menu, MF_STRING, item.id, item.label.c_str());
    }
  }
  POINT cursor = {};
  ::GetCursorPos(&cursor);
  // Without the foreground the menu would not close on a click elsewhere.
  ::SetForegroundWindow(window_);
  const UINT align = ::GetSystemMetrics(SM_MENUDROPALIGNMENT) != 0
                         ? TPM_RIGHTALIGN
                         : TPM_LEFTALIGN;
  const BOOL chosen = ::TrackPopupMenuEx(
      menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON | TPM_BOTTOMALIGN | align,
      cursor.x, cursor.y, window_, nullptr);
  ::PostMessageW(window_, WM_NULL, 0, 0);
  ::DestroyMenu(menu);
  return chosen > 0 ? static_cast<UINT>(chosen) : 0;
}
