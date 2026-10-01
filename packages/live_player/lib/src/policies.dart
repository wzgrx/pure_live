/// Whether playback continues when the app goes to the background (3.x's
/// `BackgroundPlaybackPolicy`, unchanged).
///
/// Manual audio-only mode is a presentation and power choice for the room;
/// it does not override the user's background playback switch. A sleep
/// timer session keeps playing until its timer stops the room.
bool shouldContinueInBackground({required bool backgroundPlaybackEnabled, required bool sleepSessionActive}) =>
    backgroundPlaybackEnabled || sleepSessionActive;

/// The settings key of a room's saved volume (3.x's
/// `LiveRoomVolumeManager`, kept so M9 reads 3.x's stored values).
String roomVolumeKey(String platform, String roomId) => 'room_vol_${platform.toLowerCase().trim()}_${roomId.trim()}';

/// The volume a room opens with (3.x's `LiveRoomVolumeManager.getRoomVolume`):
/// 0 when muted globally, else the room's saved volume, else the platform's
/// default (3.x: phones 0.5, desktop 1.0 when the setting is unusable).
double roomVolume({
  required String platform,
  required String roomId,
  required Map<String, double> saved,
  required bool globalMute,
  required bool mobile,
  double? defaultMobile,
  double? defaultDesktop,
}) {
  if (globalMute) return 0;
  final volume = saved[roomVolumeKey(platform, roomId)];
  if (volume != null && volume.isFinite) return volume.clamp(0, 1).toDouble();
  final fallback = mobile ? 0.5 : 1.0;
  final configured = mobile ? defaultMobile : defaultDesktop;
  return configured != null && configured.isFinite ? configured.clamp(0, 1).toDouble() : fallback;
}
