import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:live_media/live_media.dart' show VideoOrientation;
import 'package:live_store/live_store.dart' show PortraitFullscreenPolicy, PortraitOverride;
import 'package:window_manager/window_manager.dart';

/// How the room is presented (spec/modules/live-room.md §2.1): one value from
/// which the system bars, orientation and window fullscreen are derived
/// (PS-1). One video surface moves between the layouts (PS-3).
enum RoomPresentation {
  /// Video with the info and chat around it.
  inline,

  /// Large windows: the video fills the window height, the info bar hides,
  /// the chat panel stays optional (principles §5.2).
  theater,

  /// The video fills the screen or window.
  fullscreen,

  /// A portrait stream on a touch device, immersive and portrait.
  portraitFullscreen;

  /// Fullscreen of either kind.
  bool get isFullscreen => this == fullscreen || this == portraitFullscreen;
}

/// Whether the app runs on a touch platform (phones, tablets). Read from the
/// target platform, so tests can switch it.
bool get touchPlatform => switch (defaultTargetPlatform) {
  TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia => true,
  TargetPlatform.windows || TargetPlatform.linux || TargetPlatform.macOS => false,
};

/// How the platform should look for a presentation.
@immutable
final class PresentationEffects {
  const new({
    required this.presentation,
    this.lockLandscape = false,
    this.lockPortrait = false,
    this.restorePortrait = false,
  });

  /// The presentation.
  final RoomPresentation presentation;

  /// Lock landscape (phones, a landscape or forced-landscape fullscreen).
  final bool lockLandscape;

  /// Lock portrait (phones, portrait fullscreen).
  final bool lockPortrait;

  /// Leaving a forced-landscape fullscreen: lock portrait for 350 ms, then
  /// release (INV-ROOM-04).
  final bool restorePortrait;
}

/// PS-1: applies [effects]. Desktops send one window-fullscreen request per
/// change (INV-ROOM-18); phones set the system bars and the orientation
/// lock. Platform errors are ignored: the layout already changed.
Future<void> applyPresentation(PresentationEffects effects, {required bool desktop}) async {
  try {
    if (desktop) {
      await windowManager.setFullScreen(effects.presentation.isFullscreen);
      return;
    }
    if (effects.presentation.isFullscreen) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      if (effects.lockPortrait) {
        await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
      } else if (effects.lockLandscape) {
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        await SystemChrome.setPreferredOrientations(const []);
      }
      return;
    }
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (effects.restorePortrait) {
      await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
    await SystemChrome.setPreferredOrientations(const []);
  } on Object catch (error) {
    debugPrint('presentation: $error');
  }
}

/// The source as the room treats it (F-ROOM-06, GEO-7): the room's override
/// wins over the detected [geometry]; with [adaptation] off every source is
/// landscape. Neither while the geometry is unknown or square.
({bool portrait, bool landscape}) sourceShape({
  required bool adaptation,
  required PortraitOverride override,
  required VideoOrientation geometry,
}) {
  if (!adaptation) return (portrait: false, landscape: true);
  return switch (override) {
    PortraitOverride.portrait => (portrait: true, landscape: false),
    PortraitOverride.landscape => (portrait: false, landscape: true),
    PortraitOverride.automatic => (
      portrait: geometry == VideoOrientation.portrait,
      landscape: geometry == VideoOrientation.landscape,
    ),
  };
}

/// The orientation locks of a presentation change on a phone (F-ROOM-06):
/// follow the source (portrait sources lock portrait, others landscape),
/// follow the phone (no lock unless the user forced landscape), or always
/// landscape. Turning the phone sideways never locks (T-09).
({bool landscape, bool portrait}) orientationLocks({
  required PortraitFullscreenPolicy policy,
  required RoomPresentation next,
  required bool portraitSource,
  bool forceLandscape = false,
  bool byRotation = false,
}) => (
  landscape:
      next == RoomPresentation.fullscreen &&
      !byRotation &&
      (forceLandscape ||
          policy == PortraitFullscreenPolicy.landscape ||
          (policy == PortraitFullscreenPolicy.followSource && !portraitSource)),
  portrait: next == RoomPresentation.portraitFullscreen && policy != PortraitFullscreenPolicy.followSystem,
);
