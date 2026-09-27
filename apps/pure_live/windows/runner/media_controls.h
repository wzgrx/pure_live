#ifndef RUNNER_MEDIA_CONTROLS_H_
#define RUNNER_MEDIA_CONTROLS_H_

#include <windows.h>

#include <string>

// Windows System Media Transport Controls for the playing room (spec/product.md
// F-NEW-12): title, streamer, cover and play state in the media flyout and on
// the media keys. Uses the WinRT ABI through WRL (no exceptions, as the runner
// builds with _HAS_EXCEPTIONS=0).
//
// Button presses arrive on a WinRT thread; they are posted to |window| as
// |message| with the SystemMediaTransportControlsButton value in wParam
// (0 play, 1 pause, 2 stop).
class MediaControls {
 public:
  MediaControls(HWND window, UINT message);
  ~MediaControls();

  MediaControls(const MediaControls&) = delete;
  MediaControls& operator=(const MediaControls&) = delete;

  // Shows the room; |thumbnail| is an http(s) URL or empty. False when SMTC
  // is unavailable.
  bool Update(const std::wstring& title,
              const std::wstring& artist,
              const std::wstring& album,
              const std::wstring& thumbnail,
              bool playing);

  // Removes the room from SMTC.
  void Clear();

 private:
  struct State;

  bool EnsureInitialized();

  HWND window_;
  UINT message_;
  State* state_ = nullptr;
  bool failed_ = false;
};

#endif  // RUNNER_MEDIA_CONTROLS_H_
