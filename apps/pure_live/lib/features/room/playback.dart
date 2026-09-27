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

/// Picks the platform quality that matches the user's preference: the
/// platform's list is best first, the preference names a relative level.
Quality? preferredQuality(List<Quality> offered, QualityPreference preference) {
  if (offered.isEmpty || preference == QualityPreference.original) return null;
  // "流畅" always means the platform's lowest; the others count down from the best.
  if (preference == QualityPreference.smooth) return offered.last;
  return offered[preference.index.clamp(0, offered.length - 1)];
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
}) async {
  final initial = await site.streams.streams(detail);
  proxiedHosts?.note(settings, detail.ref.platform, initial);
  final wanted = preferredQuality(initial.qualities, preference ?? settings.get(Settings.qualityWifi));
  await session.open(
    wanted == null || wanted == initial.selected
        ? PlaybackRequest.room(site.streams, detail, initial: initial)
        : PlaybackRequest.room(site.streams, detail, quality: wanted),
  );
}
