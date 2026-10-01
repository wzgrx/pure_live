#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <cstdlib>
#include <string>
#include <vector>
#include "flutter_window.h"
#include "utils.h"
#include <shobjidl.h>

namespace {

constexpr wchar_t kPrimaryInstanceMutex[] =
    L"Local\\PureLive_Primary_Instance_v1";

// Native title shown by the taskbar, Alt+Tab and Task Manager (the Chinese app name);
// the in-app title bar is drawn by Flutter. Escaped to keep the source ASCII.
// The app renames the window while a room is open ("<streamer> - 纯粹直播",
// docs/ui/compare/U.13 c11), so the main window is found by a property
// instead of its title.
constexpr wchar_t kWindowTitle[] = L"纯粹直播";

constexpr wchar_t kWindowClass[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

// Set on the main window only; extra windows share the class and title.
constexpr wchar_t kPrimaryWindowProperty[] = L"PureLive.PrimaryWindow";

BOOL CALLBACK FindPrimaryWindow(HWND window, LPARAM found) {
  wchar_t class_name[64] = {};
  if (::GetClassNameW(window, class_name, 64) == 0 ||
      std::wstring(class_name) != kWindowClass) {
    return TRUE;
  }
  if (::GetPropW(window, kPrimaryWindowProperty) == nullptr) {
    return TRUE;
  }
  *reinterpret_cast<HWND*>(found) = window;
  return FALSE;
}

void BringPrimaryWindowToFront() {
  HWND window = nullptr;
  ::EnumWindows(FindPrimaryWindow, reinterpret_cast<LPARAM>(&window));
  if (window == nullptr) {
    // A main window of a build before the property: its title is still the
    // app's name unless a room is open.
    window = ::FindWindowW(kWindowClass, kWindowTitle);
  }
  if (window == nullptr) {
    return;
  }
  if (::IsIconic(window)) {
    ::ShowWindowAsync(window, SW_RESTORE);
  } else {
    ::ShowWindowAsync(window, SW_SHOW);
  }
  ::SetWindowPos(window, HWND_TOP, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
  ::SetForegroundWindow(window);
}

// The window's id from `--instance=<id>` (extra windows), or empty for the
// main window. Only [A-Za-z0-9_.-] is kept, as the Dart side sanitizes it.
std::wstring InstanceIdFromArguments(const std::vector<std::string>& arguments) {
  const std::string prefix = "--instance=";
  for (const auto& argument : arguments) {
    if (argument.rfind(prefix, 0) != 0) continue;
    std::wstring id;
    for (const char c : argument.substr(prefix.size())) {
      if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
          (c >= '0' && c <= '9') || c == '_' || c == '.' || c == '-') {
        id.push_back(static_cast<wchar_t>(c));
      }
      if (id.size() >= 96) break;
    }
    return id;
  }
  return std::wstring();
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  // One process per window id, decided before any Flutter engine, GPU
  // surface or plugin starts. 3.x fenced only argument-less launches here and
  // left the rest to the windows_single_instance plugin, which brought the
  // first window to front and dropped the arguments; v4 does both here. The
  // main window is brought to front; a repeated extra-window id just exits.
  const std::wstring instance_id =
      InstanceIdFromArguments(command_line_arguments);
  const std::wstring mutex_name =
      instance_id.empty() ? std::wstring(kPrimaryInstanceMutex)
                          : L"Local\\PureLive_Instance_" + instance_id;
  HANDLE instance_mutex = ::CreateMutexW(nullptr, TRUE, mutex_name.c_str());
  if (instance_mutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    if (instance_id.empty()) {
      BringPrimaryWindowToFront();
    }
    ::CloseHandle(instance_mutex);
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  {
    flutter::DartProject project(L"data");

    project.set_dart_entrypoint_arguments(std::move(command_line_arguments));
    SetCurrentProcessExplicitAppUserModelID(L"com.mystyle.purelive");
    FlutterWindow window(project);
    Win32Window::Point origin(10, 10);
    Win32Window::Size size(1280, 720);
    if (!window.Create(kWindowTitle, origin, size)) {
      return EXIT_FAILURE;
    }
    window.SetQuitOnClose(true);
    if (instance_id.empty()) {
      // What a second launch looks for (BringPrimaryWindowToFront).
      ::SetPropW(window.GetHandle(), kPrimaryWindowProperty,
                 reinterpret_cast<HANDLE>(static_cast<INT_PTR>(1)));
    }

    ::MSG msg;
    while (::GetMessage(&msg, nullptr, 0, 0)) {
      ::TranslateMessage(&msg);
      ::DispatchMessage(&msg);
    }
  }

  ::CoUninitialize();
  // Flutter and plugin objects are already destroyed above. Bypass process
  // detach hooks in optional DLLs that can otherwise keep the process alive.
  ::TerminateProcess(::GetCurrentProcess(), EXIT_SUCCESS);
  return EXIT_SUCCESS;
}
