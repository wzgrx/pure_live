#ifndef RUNNER_SYSTEM_BRIDGE_H_
#define RUNNER_SYSTEM_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "media_controls.h"
#include "tray_icon.h"

// The runner side of channel `purelive/windows`
// (lib/features/system/windows_native.dart):
//
// Dart -> runner: ready, setStartMaximized, setTitleBarDark, showTray,
// hideTray, setLaunchAtStartup, updateMediaControls, clearMediaControls.
// Runner -> Dart: forwardedArguments (F-WIN-01), trayEvent (F-WIN-03:
// click, show, hide, exit), mediaButton (F-NEW-12: play, pause, stop).
class SystemBridge {
 public:
  // |primary| marks the main window of the single instance (extra windows
  // started with --instance are not primary).
  SystemBridge(flutter::BinaryMessenger* messenger, HWND window, bool primary);
  ~SystemBridge();

  SystemBridge(const SystemBridge&) = delete;
  SystemBridge& operator=(const SystemBridge&) = delete;

  // Handles the runner's window messages; a value means the message was
  // consumed.
  std::optional<LRESULT> HandleMessage(UINT message, WPARAM wparam,
                                       LPARAM lparam);

  // Applies the title bar colour chosen by Dart again (the system resets it
  // when the accent colour changes).
  void ReapplyTitleBar();

  // Whether the first show should maximise the window (F-WIN-06).
  bool start_maximized() const { return start_maximized_; }

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void Invoke(const char* method, flutter::EncodableValue argument);
  void DeliverForwarded(std::vector<std::string> arguments);
  void BringToFront();
  void OnTrayEvent(LPARAM event);
  void OnMediaButton(WPARAM button);

  HWND window_;
  bool primary_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  TrayIcon tray_;
  MediaControls media_;
  UINT taskbar_created_message_;
  bool dart_ready_ = false;
  std::vector<std::vector<std::string>> pending_forwarded_;
  int title_bar_dark_ = -1;
  bool start_maximized_ = false;
  std::wstring show_label_;
  std::wstring hide_label_;
  std::wstring exit_label_;
};

#endif  // RUNNER_SYSTEM_BRIDGE_H_
