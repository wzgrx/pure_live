#ifndef RUNNER_TRAY_ICON_H_
#define RUNNER_TRAY_ICON_H_

#include <windows.h>
#include <shellapi.h>

#include <string>
#include <vector>

// A notification-area icon with a context menu (spec/product.md F-WIN-03).
// Mouse events arrive at the owner window as |callback_message| with the
// mouse message in lParam (the classic notify-icon protocol).
class TrayIcon {
 public:
  struct MenuItem {
    UINT id;  // 0 draws a separator.
    std::wstring label;
  };

  TrayIcon(HWND window, UINT callback_message);
  ~TrayIcon();

  TrayIcon(const TrayIcon&) = delete;
  TrayIcon& operator=(const TrayIcon&) = delete;

  // Adds the icon or updates its tooltip.
  void Show(const std::wstring& tooltip);

  // Removes the icon.
  void Hide();

  // Adds the icon again after Explorer restarted ("TaskbarCreated").
  void Restore();

  // Shows |items| at the cursor; returns the chosen id, or 0.
  UINT ShowMenu(const std::vector<MenuItem>& items);

  bool visible() const { return visible_; }

 private:
  NOTIFYICONDATAW Data() const;

  HWND window_;
  UINT callback_message_;
  HICON icon_ = nullptr;
  bool visible_ = false;
  std::wstring tooltip_;
};

#endif  // RUNNER_TRAY_ICON_H_
