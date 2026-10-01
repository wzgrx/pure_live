import 'dart:ffi' show Abi;

import 'package:live_media/live_media.dart';

/// The FFmpeg inside each libmpv bundle of
/// `third_party/media_kit/hook/native_bundles.json`, by media_kit target
/// (`<os>_<architecture>`). Null when the bundle does not say.
///
/// - Android arm64, arm, x64 and Linux x64: self-built mpv 0.41.0 with
///   FFmpeg 9.0.2 (the `native-libmpv-*-0.41.0-ff9.0.2-b1` releases).
/// - Windows: Predidit's libmpv-win32-video-cmake development builds, mpv
///   0.41.0 with FFmpeg master (newer than 8.0).
/// - Android x86, Linux arm64, iOS, macOS: Predidit's builds without a
///   stated FFmpeg version.
const nativeBundleFfmpeg = <String, String?>{
  'android_arm64': '9.0.2',
  'android_arm': '9.0.2',
  'android_x64': '9.0.2',
  'android_ia32': null,
  'linux_x64': '9.0.2',
  'linux_arm64': null,
  'windows_x64': 'master',
  'windows_arm64': 'master',
  'ios_arm64': null,
  'ios_x64': null,
  'macos_arm64': null,
  'macos_x64': null,
};

/// The media_kit target of [abi], e.g. `android_arm64` (the hook uses the
/// same `<os>_<architecture>` names as `Abi`).
String nativeBundleTarget(Abi abi) => abi.toString();

/// What the libmpv of [abi] can read (M7.1 left this to the binding).
///
/// FFmpeg reads codec-id-12 HEVC FLV since 8.0, so the relay rewrites it to
/// Enhanced FLV only where the bundle's FFmpeg is older or unknown.
EngineProfile mpvEngineProfile([Abi? abi]) {
  final ffmpeg = nativeBundleFfmpeg[nativeBundleTarget(abi ?? Abi.current())];
  return EngineProfile(rewriteLegacyHevcFlv: !_readsLegacyHevc(ffmpeg));
}

bool _readsLegacyHevc(String? ffmpeg) {
  if (ffmpeg == null) return false;
  if (ffmpeg == 'master') return true;
  final major = int.tryParse(ffmpeg.split('.').first);
  return major != null && major >= 8;
}
