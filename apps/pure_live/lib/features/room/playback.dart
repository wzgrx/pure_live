import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/engine.dart';
import 'package:pure_live_app/core/proxy.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/features/system/mini_player.dart';

/// A session the mini window handed back for the room page being built
/// (SES-9): the page puts it here right before it reads
/// [playbackSessionProvider], which takes it instead of creating one.
final class SessionHandoff {
  /// The handed-back session, until the provider takes it.
  PlaybackSession? pending;
}

/// The hand-back slot of [playbackSessionProvider].
final sessionHandoffProvider = Provider<SessionHandoff>((ref) => SessionHandoff());

/// The playback session of the open room page. One session per page; the
/// engine is created on the first open and released when the page goes away
/// (ADR 0018), unless the mini window took the session over (PIP-4).
final Provider<PlaybackSession> playbackSessionProvider = Provider.autoDispose<PlaybackSession>((ref) {
  final handoff = ref.read(sessionHandoffProvider);
  final session = handoff.pending ?? newPlaybackSession(ref);
  handoff.pending = null;
  // Read now: ref is unusable in onDispose.
  final mini = ref.read(miniPlayerProvider.notifier);
  ref.onDispose(() {
    if (!mini.owns(session)) unawaited(session.dispose());
  });
  return session;
});

/// The names of the standard levels (live-room Q-2).
const Map<QualityPreference, String> qualityPreferenceNames = {
  QualityPreference.original: '原画',
  QualityPreference.bluRay8M: '蓝光8M',
  QualityPreference.bluRay4M: '蓝光4M',
  QualityPreference.superHigh: '超清',
  QualityPreference.smooth: '流畅',
};

/// Picks the platform quality for the user's preference (live-room Q-2): a
/// quality with the preference's name, else the same relative position in
/// the platform's list (best first) as the preference has among the standard
/// levels, rounded. Null only for an empty list.
Quality? preferredQuality(List<Quality> offered, QualityPreference preference) {
  if (offered.isEmpty) return null;
  final name = qualityPreferenceNames[preference];
  for (final quality in offered) {
    if (quality.label.replaceAll(' ', '') == name) return quality;
  }
  final position = preference.index / (QualityPreference.values.length - 1);
  return offered[(position * (offered.length - 1)).round()];
}

/// Opens [detail] in [session] at the stored default quality: resolves once,
/// then opens with that set when it already is the wanted quality, or asks
/// for the wanted one.
Future<void> openRoom({
  required PlatformSite site,
  required SettingsStore settings,
  required PlaybackSession session,
  required RoomDetail detail,
  QualityPreference? preference,
  ProxiedHosts? proxiedHosts,
  bool cellular = false,
}) async {
  final initial = await site.streams.streams(detail);
  proxiedHosts?.note(settings, detail.ref.platform, initial);
  // Q-2: the cellular preference on mobile data, the other one elsewhere.
  final wanted = preferredQuality(
    initial.qualities,
    preference ?? settings.get(cellular ? Settings.qualityMobile : Settings.qualityWifi),
  );
  await session.open(
    wanted == null || wanted == initial.selected
        ? PlaybackRequest.room(site.streams, detail, initial: initial)
        : PlaybackRequest.room(site.streams, detail, quality: wanted),
  );
}
