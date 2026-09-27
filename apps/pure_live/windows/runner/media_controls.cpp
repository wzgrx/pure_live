#include "media_controls.h"

// The WinRT ABI headers are not warning-clean at /W4 in every SDK.
#pragma warning(push, 3)
#include <roapi.h>
#include <systemmediatransportcontrolsinterop.h>
#include <windows.foundation.h>
#include <windows.media.h>
#include <windows.storage.streams.h>
#include <wrl/client.h>
#include <wrl/event.h>
#include <wrl/wrappers/corewrappers.h>
#pragma warning(pop)

namespace {

using ABI::Windows::Foundation::ITypedEventHandler;
using ABI::Windows::Foundation::IUriRuntimeClass;
using ABI::Windows::Foundation::IUriRuntimeClassFactory;
using ABI::Windows::Media::IMusicDisplayProperties;
using ABI::Windows::Media::ISystemMediaTransportControls;
using ABI::Windows::Media::ISystemMediaTransportControlsButtonPressedEventArgs;
using ABI::Windows::Media::ISystemMediaTransportControlsDisplayUpdater;
using ABI::Windows::Media::SystemMediaTransportControls;
using ABI::Windows::Media::SystemMediaTransportControlsButton;
using ABI::Windows::Media::SystemMediaTransportControlsButtonPressedEventArgs;
using ABI::Windows::Storage::Streams::IRandomAccessStreamReference;
using ABI::Windows::Storage::Streams::IRandomAccessStreamReferenceStatics;
using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;
using Microsoft::WRL::Wrappers::HString;
using Microsoft::WRL::Wrappers::HStringReference;

// Sets |target| to |text|; false when the string could not be created.
bool MakeHString(const std::wstring& text, HString* target) {
  return SUCCEEDED(
      target->Set(text.c_str(), static_cast<unsigned int>(text.size())));
}

// A stream reference for the cover at |url|; SMTC downloads it itself.
ComPtr<IRandomAccessStreamReference> ThumbnailFromUrl(const std::wstring& url) {
  ComPtr<IRandomAccessStreamReference> reference;
  if (url.empty()) {
    return reference;
  }
  ComPtr<IUriRuntimeClassFactory> uri_factory;
  if (FAILED(::RoGetActivationFactory(
          HStringReference(L"Windows.Foundation.Uri").Get(),
          IID_PPV_ARGS(&uri_factory)))) {
    return reference;
  }
  HString url_string;
  ComPtr<IUriRuntimeClass> uri;
  if (!MakeHString(url, &url_string) ||
      FAILED(uri_factory->CreateUri(url_string.Get(), &uri))) {
    return reference;
  }
  ComPtr<IRandomAccessStreamReferenceStatics> statics;
  if (FAILED(::RoGetActivationFactory(
          HStringReference(L"Windows.Storage.Streams.RandomAccessStreamReference")
              .Get(),
          IID_PPV_ARGS(&statics)))) {
    return reference;
  }
  statics->CreateFromUri(uri.Get(), &reference);
  return reference;
}

}  // namespace

struct MediaControls::State {
  ComPtr<ISystemMediaTransportControls> controls;
  ComPtr<ISystemMediaTransportControlsDisplayUpdater> updater;
  EventRegistrationToken button_token = {};
  bool subscribed = false;
};

MediaControls::MediaControls(HWND window, UINT message)
    : window_(window), message_(message) {}

MediaControls::~MediaControls() {
  if (state_ == nullptr) {
    return;
  }
  if (state_->subscribed) {
    state_->controls->remove_ButtonPressed(state_->button_token);
  }
  if (state_->controls) {
    state_->controls->put_IsEnabled(false);
  }
  delete state_;
  state_ = nullptr;
}

bool MediaControls::EnsureInitialized() {
  if (state_ != nullptr) {
    return true;
  }
  if (failed_) {
    return false;
  }
  failed_ = true;
  ComPtr<ISystemMediaTransportControlsInterop> interop;
  if (FAILED(::RoGetActivationFactory(
          HStringReference(L"Windows.Media.SystemMediaTransportControls").Get(),
          IID_PPV_ARGS(&interop)))) {
    return false;
  }
  auto* state = new State();
  if (FAILED(interop->GetForWindow(window_, IID_PPV_ARGS(&state->controls))) ||
      FAILED(state->controls->get_DisplayUpdater(&state->updater))) {
    delete state;
    return false;
  }
  // WinRT calls this on its own thread: post to the window, never touch
  // Flutter from here.
  const HWND window = window_;
  const UINT message = message_;
  auto handler = Callback<ITypedEventHandler<
      SystemMediaTransportControls*,
      SystemMediaTransportControlsButtonPressedEventArgs*>>(
      [window, message](
          ISystemMediaTransportControls*,
          ISystemMediaTransportControlsButtonPressedEventArgs* args) -> HRESULT {
        SystemMediaTransportControlsButton button =
            static_cast<SystemMediaTransportControlsButton>(-1);
        if (args != nullptr && SUCCEEDED(args->get_Button(&button))) {
          ::PostMessageW(window, message, static_cast<WPARAM>(button), 0);
        }
        return S_OK;
      });
  if (handler &&
      SUCCEEDED(state->controls->add_ButtonPressed(handler.Get(),
                                                   &state->button_token))) {
    state->subscribed = true;
  }
  state->controls->put_IsPlayEnabled(true);
  state->controls->put_IsPauseEnabled(true);
  state->controls->put_IsStopEnabled(true);
  state_ = state;
  failed_ = false;
  return true;
}

bool MediaControls::Update(const std::wstring& title,
                           const std::wstring& artist,
                           const std::wstring& album,
                           const std::wstring& thumbnail,
                           bool playing) {
  if (!EnsureInitialized()) {
    return false;
  }
  auto& controls = state_->controls;
  auto& updater = state_->updater;
  controls->put_IsEnabled(true);
  controls->put_PlaybackStatus(
      playing ? ABI::Windows::Media::MediaPlaybackStatus::MediaPlaybackStatus_Playing
              : ABI::Windows::Media::MediaPlaybackStatus::MediaPlaybackStatus_Paused);
  updater->put_Type(ABI::Windows::Media::MediaPlaybackType::MediaPlaybackType_Music);
  ComPtr<IMusicDisplayProperties> music;
  if (SUCCEEDED(updater->get_MusicProperties(&music))) {
    HString title_string;
    HString artist_string;
    HString album_string;
    if (MakeHString(title, &title_string)) {
      music->put_Title(title_string.Get());
    }
    if (MakeHString(artist, &artist_string)) {
      music->put_Artist(artist_string.Get());
    }
    if (MakeHString(album, &album_string)) {
      music->put_AlbumArtist(album_string.Get());
    }
  }
  ComPtr<IRandomAccessStreamReference> cover = ThumbnailFromUrl(thumbnail);
  updater->put_Thumbnail(cover.Get());
  return SUCCEEDED(updater->Update());
}

void MediaControls::Clear() {
  if (state_ == nullptr) {
    return;
  }
  state_->updater->ClearAll();
  state_->controls->put_PlaybackStatus(
      ABI::Windows::Media::MediaPlaybackStatus::MediaPlaybackStatus_Closed);
  state_->controls->put_IsEnabled(false);
}
