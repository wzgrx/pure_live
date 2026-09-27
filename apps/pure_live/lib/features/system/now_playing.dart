import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:pure_live_app/core/sites.dart';

/// The room whose playback the system integration follows: background policy
/// (INT-3), audio focus (INT-4), the media notification and SMTC (F-BG-01,
/// F-NEW-12), picture-in-picture (§9) and the mini window (PIP-4).
@immutable
final class NowPlaying {
  /// Creates an entry.
  const new({
    required this.session,
    required this.room,
    required this.title,
    required this.anchor,
    this.cover,
    this.platformName,
  });

  /// The entry of [detail] played by [session].
  factory fromDetail(PlaybackSession session, RoomDetail detail) => NowPlaying(
    session: session,
    room: detail.ref,
    title: detail.card.title,
    anchor: detail.card.anchorName,
    cover: detail.card.cover ?? detail.avatar ?? detail.card.avatar,
    platformName: platformNames[detail.ref.platform] ?? detail.ref.platform,
  );

  /// The session; its owner (the room page, or the mini window after
  /// adopting it) closes and disposes it.
  final PlaybackSession session;

  /// The room.
  final RoomRef room;

  /// Room title.
  final String title;

  /// Streamer name.
  final String anchor;

  /// Cover or avatar for the media notification and SMTC.
  final Uri? cover;

  /// Platform display name.
  final String? platformName;
}

/// Tracks [NowPlaying]; the room page attaches its session once it opened the
/// room and detaches it when it closes the session.
class NowPlayingNotifier extends Notifier<NowPlaying?> {
  @override
  NowPlaying? build() => null;

  /// Follows [playing]; replaces the previous entry (one room plays at a time).
  void attach(NowPlaying playing) {
    if (!identical(state, playing)) state = playing;
  }

  /// Stops following [session] if it is the current one.
  void detach(PlaybackSession session) {
    // Callers defer this past a frame; the app may be gone by then.
    if (!ref.mounted) return;
    if (identical(state?.session, session)) state = null;
  }
}

/// The playback the system integration follows.
final nowPlayingProvider = NotifierProvider<NowPlayingNotifier, NowPlaying?>(NowPlayingNotifier.new);

/// Runs a session [command] from a system event (notification, headset, PiP
/// action) without letting it fail the caller: a session its owner already
/// disposed throws [StateError], and errors of the command are the session's
/// own business.
void runSessionCommand(Future<void> Function() command) {
  try {
    unawaited(command().catchError((Object _) {}));
  } on Object {
    // Disposed by its owner (StateError); nothing to control any more.
  }
}
