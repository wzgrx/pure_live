#include "system_bridge.h"

#include <dwmapi.h>
#include <flutter/standard_method_codec.h>

#include <iterator>
#include <utility>

#include "single_instance.h"
#include "utils.h"

namespace {

#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

constexpr char kChannelName[] = "purelive/windows";
constexpr UINT kTrayCallbackMessage = WM_APP + 0x51;
constexpr UINT kMediaButtonMessage = WM_APP + 0x52;
constexpr UINT kMenuToggle = 1;
constexpr UINT kMenuExit = 2;
constexpr wchar_t kRunKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

const EncodableValue* Argument(const EncodableValue* arguments,
                               const char* key) {
  const auto* map = arguments == nullptr
                        ? nullptr
                        : std::get_if<EncodableMap>(arguments);
  if (map == nullptr) {
    return nullptr;
  }
  const auto found = map->find(EncodableValue(key));
  return found == map->end() ? nullptr : &found->second;
}

std::wstring WideArgument(const EncodableValue* arguments, const char* key) {
  const auto* value = Argument(arguments, key);
  const auto* text = value == nullptr ? nullptr : std::get_if<std::string>(value);
  return text == nullptr ? std::wstring() : Utf16FromUtf8(*text);
}

bool BoolArgument(const EncodableValue* arguments, const char* key) {
  const auto* value = Argument(arguments, key);
  const auto* flag = value == nullptr ? nullptr : std::get_if<bool>(value);
  return flag != nullptr && *flag;
}

// Adds or removes the Run value |name| for this executable (F-WIN-05).
bool SetLaunchAtStartup(const std::wstring& name, bool enabled) {
  if (name.empty()) {
    return false;
  }
  if (!enabled) {
    const LSTATUS status =
        ::RegDeleteKeyValueW(HKEY_CURRENT_USER, kRunKey, name.c_str());
    return status == ERROR_SUCCESS || status == ERROR_FILE_NOT_FOUND;
  }
  wchar_t path[4096] = {};
  const DWORD length = ::GetModuleFileNameW(
      nullptr, path, static_cast<DWORD>(std::size(path)));
  if (length == 0 || length >= std::size(path)) {
    return false;
  }
  const std::wstring command = L"\"" + std::wstring(path, length) + L"\"";
  const DWORD bytes =
      static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t));
  return ::RegSetKeyValueW(HKEY_CURRENT_USER, kRunKey, name.c_str(), REG_SZ,
                           command.c_str(), bytes) == ERROR_SUCCESS;
}

}  // namespace

SystemBridge::SystemBridge(flutter::BinaryMessenger* messenger, HWND window,
                           bool primary)
    : window_(window),
      primary_(primary),
      channel_(std::make_unique<flutter::MethodChannel<EncodableValue>>(
          messenger, kChannelName,
          &flutter::StandardMethodCodec::GetInstance())),
      tray_(window, kTrayCallbackMessage),
      media_(window, kMediaButtonMessage),
      taskbar_created_message_(::RegisterWindowMessageW(L"TaskbarCreated")) {
  if (primary_) {
    // Lets a second start find this window (single_instance.cpp).
    ::SetPropW(window_, kPrimaryWindowProperty,
               reinterpret_cast<HANDLE>(static_cast<INT_PTR>(1)));
  }
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        HandleMethodCall(call, std::move(result));
      });
}

SystemBridge::~SystemBridge() {
  channel_->SetMethodCallHandler(nullptr);
  if (primary_) {
    ::RemovePropW(window_, kPrimaryWindowProperty);
  }
}

void SystemBridge::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const std::string& method = call.method_name();
  const EncodableValue* arguments = call.arguments();
  if (method == "ready") {
    dart_ready_ = true;
    auto pending = std::move(pending_forwarded_);
    pending_forwarded_.clear();
    for (auto& forwarded : pending) {
      DeliverForwarded(std::move(forwarded));
    }
    result->Success();
  } else if (method == "setStartMaximized") {
    start_maximized_ = BoolArgument(arguments, "maximized");
    result->Success();
  } else if (method == "setTitleBarDark") {
    title_bar_dark_ = BoolArgument(arguments, "dark") ? 1 : 0;
    ReapplyTitleBar();
    result->Success();
  } else if (method == "showTray") {
    if (primary_) {
      show_label_ = WideArgument(arguments, "show");
      hide_label_ = WideArgument(arguments, "hide");
      exit_label_ = WideArgument(arguments, "exit");
      tray_.Show(WideArgument(arguments, "tooltip"));
    }
    result->Success();
  } else if (method == "hideTray") {
    tray_.Hide();
    result->Success();
  } else if (method == "setLaunchAtStartup") {
    result->Success(EncodableValue(SetLaunchAtStartup(
        WideArgument(arguments, "name"), BoolArgument(arguments, "enabled"))));
  } else if (method == "updateMediaControls") {
    result->Success(EncodableValue(media_.Update(
        WideArgument(arguments, "title"), WideArgument(arguments, "artist"),
        WideArgument(arguments, "album"), WideArgument(arguments, "thumbnail"),
        BoolArgument(arguments, "playing"))));
  } else if (method == "clearMediaControls") {
    media_.Clear();
    result->Success();
  } else {
    result->NotImplemented();
  }
}

void SystemBridge::Invoke(const char* method, EncodableValue argument) {
  channel_->InvokeMethod(method,
                         std::make_unique<EncodableValue>(std::move(argument)));
}

void SystemBridge::DeliverForwarded(std::vector<std::string> arguments) {
  if (!dart_ready_) {
    pending_forwarded_.push_back(std::move(arguments));
    return;
  }
  EncodableList list;
  for (auto& argument : arguments) {
    list.emplace_back(std::move(argument));
  }
  Invoke("forwardedArguments", EncodableValue(std::move(list)));
}

void SystemBridge::BringToFront() {
  if (::IsIconic(window_)) {
    ::ShowWindow(window_, SW_RESTORE);
  } else if (!::IsWindowVisible(window_)) {
    ::ShowWindow(window_, SW_SHOW);
  }
  ::SetForegroundWindow(window_);
}

void SystemBridge::ReapplyTitleBar() {
  if (title_bar_dark_ < 0) {
    return;
  }
  const BOOL dark = title_bar_dark_ == 1 ? TRUE : FALSE;
  ::DwmSetWindowAttribute(window_, DWMWA_USE_IMMERSIVE_DARK_MODE, &dark,
                          sizeof(dark));
  if (::IsWindowVisible(window_)) {
    // Windows 10 repaints the caption only when the frame changes.
    ::SetWindowPos(window_, nullptr, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                       SWP_FRAMECHANGED);
  }
}

void SystemBridge::OnTrayEvent(LPARAM event) {
  switch (LOWORD(event)) {
    case WM_LBUTTONUP:
      Invoke("trayEvent", EncodableValue("click"));
      break;
    case WM_RBUTTONUP: {
      const bool shown = ::IsWindowVisible(window_) && !::IsIconic(window_);
      const UINT chosen = tray_.ShowMenu({
          {kMenuToggle, shown ? hide_label_ : show_label_},
          {0, std::wstring()},
          {kMenuExit, exit_label_},
      });
      if (chosen == kMenuToggle) {
        Invoke("trayEvent", EncodableValue(shown ? "hide" : "show"));
      } else if (chosen == kMenuExit) {
        Invoke("trayEvent", EncodableValue("exit"));
      }
      break;
    }
    default:
      break;
  }
}

void SystemBridge::OnMediaButton(WPARAM button) {
  // ABI::Windows::Media::SystemMediaTransportControlsButton values.
  switch (button) {
    case 0:
      Invoke("mediaButton", EncodableValue("play"));
      break;
    case 1:
      Invoke("mediaButton", EncodableValue("pause"));
      break;
    case 2:
      Invoke("mediaButton", EncodableValue("stop"));
      break;
    default:
      break;
  }
}

std::optional<LRESULT> SystemBridge::HandleMessage(UINT message, WPARAM wparam,
                                                   LPARAM lparam) {
  switch (message) {
    case WM_COPYDATA: {
      const auto* data = reinterpret_cast<const COPYDATASTRUCT*>(lparam);
      if (!primary_ || data == nullptr ||
          data->dwData != kForwardedArgumentsTag) {
        return std::nullopt;
      }
      // The sender's buffer is valid only during this call: copy it now.
      auto arguments = ParseForwardedArguments(data->lpData, data->cbData);
      BringToFront();
      DeliverForwarded(std::move(arguments));
      return TRUE;
    }
    case kTrayCallbackMessage:
      OnTrayEvent(lparam);
      return 0;
    case kMediaButtonMessage:
      OnMediaButton(wparam);
      return 0;
    default:
      if (taskbar_created_message_ != 0 &&
          message == taskbar_created_message_) {
        tray_.Restore();
        return 0;
      }
      return std::nullopt;
  }
}
