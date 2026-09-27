#ifndef RUNNER_SINGLE_INSTANCE_H_
#define RUNNER_SINGLE_INSTANCE_H_

#include <windows.h>

#include <cstddef>
#include <string>
#include <vector>

// Single instance (spec/product.md F-WIN-01): a second start forwards its
// arguments to the running app with WM_COPYDATA and exits.

// WM_COPYDATA tag of forwarded arguments ("PLAR").
constexpr ULONG_PTR kForwardedArgumentsTag = 0x504C4152;

// Largest forwarded payload: UTF-8 arguments separated by '\0'.
constexpr size_t kMaxForwardedBytes = 64 * 1024;

// Window property that marks the main window of the primary instance.
constexpr wchar_t kPrimaryWindowProperty[] = L"PureLive.v4.PrimaryWindow";

// Whether this start is an extra window (`--instance`, F-WIN-02). Extra
// windows neither take nor check the single-instance lock.
bool IsSecondaryWindowLaunch(const std::vector<std::string>& arguments);

// Holds the primary-instance mutex for the life of the process.
class SingleInstance {
 public:
  SingleInstance() = default;
  ~SingleInstance();

  SingleInstance(const SingleInstance&) = delete;
  SingleInstance& operator=(const SingleInstance&) = delete;

  // Returns true when this process is the primary instance. Otherwise hands
  // |arguments| to the running one, which comes to the front, and returns
  // false: the caller exits before starting Flutter.
  bool Acquire(const std::vector<std::string>& arguments);

 private:
  HANDLE mutex_ = nullptr;
};

// Splits a forwarded payload back into arguments.
std::vector<std::string> ParseForwardedArguments(const void* data, size_t size);

#endif  // RUNNER_SINGLE_INSTANCE_H_
