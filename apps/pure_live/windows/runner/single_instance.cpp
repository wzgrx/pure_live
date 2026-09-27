#include "single_instance.h"

#include <cwchar>

namespace {

// Distinct from 3.x (`Local\PureLive_Primary_Instance_v1`) so the preview and
// 3.x can run side by side.
constexpr wchar_t kPrimaryMutexName[] = L"Local\\PureLive.v4.Primary";
constexpr wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

BOOL CALLBACK FindPrimaryWindow(HWND window, LPARAM context) {
  wchar_t class_name[64] = {};
  if (::GetClassNameW(window, class_name, 64) == 0 ||
      std::wcscmp(class_name, kWindowClassName) != 0 ||
      ::GetPropW(window, kPrimaryWindowProperty) == nullptr) {
    return TRUE;
  }
  *reinterpret_cast<HWND*>(context) = window;
  return FALSE;
}

// The primary may still be starting: its window appears once its engine runs.
HWND WaitForPrimaryWindow() {
  for (int attempt = 0; attempt < 50; ++attempt) {
    HWND found = nullptr;
    ::EnumWindows(FindPrimaryWindow, reinterpret_cast<LPARAM>(&found));
    if (found != nullptr) {
      return found;
    }
    ::Sleep(100);
  }
  return nullptr;
}

void Forward(HWND primary, const std::vector<std::string>& arguments) {
  std::string payload;
  for (const auto& argument : arguments) {
    if (payload.size() + argument.size() + 1 > kMaxForwardedBytes) {
      break;
    }
    payload.append(argument);
    payload.push_back('\0');
  }
  DWORD process_id = 0;
  ::GetWindowThreadProcessId(primary, &process_id);
  if (process_id != 0) {
    // This process was just started by the user, so it may hand the
    // foreground to the running instance.
    ::AllowSetForegroundWindow(process_id);
  }
  COPYDATASTRUCT data = {};
  data.dwData = kForwardedArgumentsTag;
  data.cbData = static_cast<DWORD>(payload.size());
  data.lpData = payload.empty() ? nullptr : payload.data();
  DWORD_PTR result = 0;
  ::SendMessageTimeoutW(primary, WM_COPYDATA, 0,
                        reinterpret_cast<LPARAM>(&data), SMTO_ABORTIFHUNG,
                        3000, &result);
}

}  // namespace

bool IsSecondaryWindowLaunch(const std::vector<std::string>& arguments) {
  for (const auto& argument : arguments) {
    if (argument == "--instance") {
      return true;
    }
  }
  return false;
}

SingleInstance::~SingleInstance() {
  if (mutex_ != nullptr) {
    ::CloseHandle(mutex_);
  }
}

bool SingleInstance::Acquire(const std::vector<std::string>& arguments) {
  mutex_ = ::CreateMutexW(nullptr, FALSE, kPrimaryMutexName);
  if (mutex_ == nullptr) {
    // Without a mutex the app still runs, just without forwarding.
    return true;
  }
  if (::GetLastError() != ERROR_ALREADY_EXISTS) {
    return true;
  }
  ::CloseHandle(mutex_);
  mutex_ = nullptr;
  HWND primary = WaitForPrimaryWindow();
  if (primary != nullptr) {
    Forward(primary, arguments);
  }
  return false;
}

std::vector<std::string> ParseForwardedArguments(const void* data,
                                                 size_t size) {
  std::vector<std::string> arguments;
  if (data == nullptr || size == 0 || size > kMaxForwardedBytes) {
    return arguments;
  }
  const char* begin = static_cast<const char*>(data);
  const char* end = begin + size;
  const char* start = begin;
  for (const char* cursor = begin; cursor < end; ++cursor) {
    if (*cursor == '\0') {
      arguments.emplace_back(start, cursor);
      start = cursor + 1;
    }
  }
  return arguments;
}
