#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "system_bridge.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  // |primary| marks the main window of the single instance (F-WIN-01).
  FlutterWindow(const flutter::DartProject& project, bool primary);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // Whether this is the single instance's main window.
  bool primary_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Tray, SMTC, forwarded launches and window chrome (channel
  // purelive/windows). Declared after the controller, so it is destroyed
  // first: its channel uses the engine's messenger.
  std::unique_ptr<SystemBridge> system_bridge_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
