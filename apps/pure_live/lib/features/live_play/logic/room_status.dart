import 'package:flutter/foundation.dart' show immutable;
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// What the picture shows when it is not simply playing (docs/A-界面设计/A07-直播间界面/A07.7-直播间的状态:
/// eighteen states, one component).
enum PictureStateKind {
  /// Playing: nothing over the picture.
  none,

  /// Paused by the user: the play mark on its disc in the middle, which
  /// resumes (A-01, B02 c2); over an audio-only room's cover too (B-9).
  paused,

  /// The picture is there and the stream waits for data (a short stall, a
  /// resume after a pause): the middle mark turns, no words (B02 c2, c4).
  buffering,

  /// The room detail is being fetched: "正在进入直播间…" (c3).
  entering,

  /// The stream is opening: "正在连接直播流…" (c3).
  connecting,

  /// Opening for more than [slowAfter] without a picture (c4, Z4).
  slow,

  /// Not on air (c7).
  offline,

  /// Banned or closed by the platform (c10).
  banned,

  /// The platform plays old videos (c10).
  carousel,

  /// The platform did not say whether the room is on air (c10).
  statusUnknown,

  /// The room detail could not be fetched (c10).
  detailFailed,

  /// The room does not exist (c10).
  notFound,

  /// On air, but restricted: login, paid, region and so on (c11).
  restricted,

  /// On air, but the platform gave no stream (c11).
  noStream,

  /// The player failed (c12).
  playbackFailed,

  /// A dropped stream comes back (c13, U.2a E3).
  reconnecting,

  /// Only the sound plays (c14, U.2a E5); the cover is drawn under it.
  audioOnly,

  /// Back from audio only, waiting for the picture (c14).
  restoring,

  /// A replay or a catch-up reached its end (c15).
  replayEnded,
}

/// A button of a picture state (docs/A-界面设计/A07-直播间界面/A07.7-直播间的状态 按钮 1–7).
enum PictureAction {
  /// Opens the room switcher (1).
  switchRoom,

  /// Fetches the room again (2).
  refresh,

  /// Loads again (3).
  retry,

  /// Plays the next line (4; only with more than one line).
  switchLine,

  /// Opens the platform's sign-in, then retries (5).
  login,

  /// Opens the room in the platform's app or site (6).
  openInPlatform,

  /// Plays the replay from the start (7).
  playAgain,
}

/// What lies under a picture state.
enum PictureDim {
  /// The picture as it is (spinners while loading: the ground is black).
  none,

  /// 45 % black over the moving picture (reconnecting).
  light,

  /// 60 % black over the stopped picture (failed, ended).
  heavy,

  /// The room's cover under a dark veil (offline, restricted, audio only).
  cover,
}

/// One picture state: the words, at most two buttons (the first is the main
/// one) and what lies under it.
@immutable
final class PictureState {
  /// Creates the state.
  const new({required this.kind, this.title = '', this.reason, this.actions = const [], this.dim = PictureDim.none});

  /// Nothing over the picture.
  static const PictureState playing = PictureState(kind: PictureStateKind.none);

  /// Which state.
  final PictureStateKind kind;

  /// The sentence.
  final String title;

  /// Why, or what to do next.
  final String? reason;

  /// At most two buttons, the main one first.
  final List<PictureAction> actions;

  /// What lies under the words.
  final PictureDim dim;

  /// A spinner leads the words.
  bool get busy => switch (kind) {
    PictureStateKind.entering ||
    PictureStateKind.connecting ||
    PictureStateKind.slow ||
    PictureStateKind.reconnecting ||
    PictureStateKind.restoring ||
    PictureStateKind.buffering => true,
    _ => false,
  };

  /// The streamer's picture leads the words (offline, carousel).
  bool get showsStreamer => kind == PictureStateKind.offline || kind == PictureStateKind.carousel;

  @override
  bool operator ==(Object other) =>
      other is PictureState &&
      other.kind == kind &&
      other.title == title &&
      other.reason == reason &&
      other.dim == dim &&
      _sameActions(other.actions, actions);

  @override
  int get hashCode => Object.hash(kind, title, reason, dim, Object.hashAll(actions));

  @override
  String toString() => 'PictureState($kind, $title, $reason, $actions, $dim)';
}

bool _sameActions(List<PictureAction> a, List<PictureAction> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

/// How long the stream may open before the picture says it is slow (c4).
const Duration slowAfter = Duration(seconds: 8);

/// Whether [playback] waits for data with its picture already there (a
/// short stall, a resume after a pause; B02): a new source has no picture
/// size yet, and says it connects instead.
bool pictureBuffering(PlaybackState playback) =>
    playback.status == PlaybackStatus.buffering && playback.videoWidth != null;

/// The short side, in pixels, at or under which a decoded picture is a
/// placeholder track rather than a picture (A07.20 c1: Missevan's is
/// 16 × 16; the lowest real quality, 144p, is far above).
const int placeholderPictureSide = 32;

/// Whether [playback] has no real picture (A07.20 c1): its short side is at
/// most [placeholderPictureSide], or the platform is a voice one
/// ([voiceLive], `LiveSite.isVoiceLive`) and the stream is under way. A size
/// not reported yet is not a placeholder: that moment shows the loading
/// state.
bool pictureIsPlaceholder(PlaybackState playback, {bool voiceLive = false}) {
  final width = playback.videoWidth;
  final height = playback.videoHeight;
  final known = width != null && height != null && width > 0 && height > 0;
  if (known && (width < height ? width : height) <= placeholderPictureSide) return true;
  if (!voiceLive) return false;
  return known || playback.status == PlaybackStatus.playing || playback.status == PlaybackStatus.paused;
}

/// Whether the picture's control bars belong on screen: only once a stream
/// is open (c5: no bars over loading, offline, failed or restricted rooms;
/// fullscreen keeps a reduced top bar, c6).
bool pictureHasControls(RoomStage stage) => stage == RoomStage.playing;

/// The picture state of a room (docs/A-界面设计/A07-直播间界面/A07.7-直播间的状态): [stage] and [failure]
/// of the room, [room] as known, the session's [playback], the stream's
/// recovery ([reconnecting], [attempts]: the session's own, B02 c4),
/// [audioOnly], [restoring] (back from audio only, no picture yet) and
/// [slow] (opening for [slowAfter]). Paused, the play mark shows over an
/// audio-only cover too (B-9); a stream that buffers with its picture there
/// turns the middle mark ([pictureBuffering]).
PictureState pictureStateOf({
  required RoomStage stage,
  required Object? failure,
  required LiveRoom room,
  required PlaybackState playback,
  bool reconnecting = false,
  int attempts = 0,
  bool audioOnly = false,
  bool restoring = false,
  bool slow = false,
}) {
  switch (stage) {
    case RoomStage.loading:
      return PictureState(kind: PictureStateKind.entering, title: i18n('live_play_entering'));
    case RoomStage.failed:
      if (failure is NotFound) {
        return PictureState(
          kind: PictureStateKind.notFound,
          title: i18n('live_play_error_not_found'),
          actions: const [PictureAction.switchRoom],
        );
      }
      return PictureState(
        kind: PictureStateKind.detailFailed,
        title: failureText(failure),
        actions: const [PictureAction.retry, PictureAction.switchRoom],
      );
    case RoomStage.offline:
      return _offline(room);
    case RoomStage.unplayable:
      return _unplayable(room, failure);
    case RoomStage.playing:
      break;
  }
  final lines = playback.lineCount;
  final line = lines > 1 ? const [PictureAction.switchLine] : const <PictureAction>[];
  if (playback.status == PlaybackStatus.error) {
    return PictureState(
      kind: PictureStateKind.playbackFailed,
      title: i18n('playback_failure_title'),
      reason: failureText(playback.error),
      actions: [PictureAction.retry, ...line],
      dim: PictureDim.heavy,
    );
  }
  if (reconnecting) {
    return PictureState(
      kind: PictureStateKind.reconnecting,
      title: i18n('live_play_reconnecting', args: {'count': '$attempts'}),
      actions: line,
      dim: PictureDim.light,
    );
  }
  // B-9: paused before audio only, which said "纯音频播放中" while paused.
  if (playback.status == PlaybackStatus.paused) return const PictureState(kind: PictureStateKind.paused);
  if (audioOnly) return const PictureState(kind: PictureStateKind.audioOnly);
  if (restoring) {
    return PictureState(kind: PictureStateKind.restoring, title: i18n('restoring_live_video'), dim: PictureDim.cover);
  }
  if (pictureBuffering(playback)) return const PictureState(kind: PictureStateKind.buffering);
  return switch (playback.status) {
    PlaybackStatus.idle || PlaybackStatus.opening || PlaybackStatus.buffering =>
      slow
          ? PictureState(
              kind: PictureStateKind.slow,
              title: i18n('live_play_connecting_stream'),
              reason: i18n('live_play_slow_hint'),
              actions: [...line, PictureAction.retry],
            )
          : PictureState(kind: PictureStateKind.connecting, title: i18n('live_play_connecting_stream')),
    PlaybackStatus.completed => PictureState(
      kind: PictureStateKind.replayEnded,
      title: i18n('live_play_replay_ended'),
      actions: const [PictureAction.playAgain, PictureAction.switchRoom],
      dim: PictureDim.heavy,
    ),
    PlaybackStatus.paused => const PictureState(kind: PictureStateKind.paused),
    PlaybackStatus.playing || PlaybackStatus.stopped || PlaybackStatus.error => PictureState.playing,
  };
}

PictureState _offline(LiveRoom room) => switch (room.effectiveLiveStatus) {
  LiveStatus.banned => PictureState(
    kind: PictureStateKind.banned,
    title: i18n('live_play_banned'),
    actions: const [PictureAction.switchRoom, PictureAction.refresh],
    dim: PictureDim.cover,
  ),
  LiveStatus.carousel => PictureState(
    kind: PictureStateKind.carousel,
    title: i18n('live_play_carousel'),
    reason: i18n('live_play_offline_hint'),
    actions: const [PictureAction.switchRoom, PictureAction.refresh],
    dim: PictureDim.cover,
  ),
  LiveStatus.unknown => PictureState(
    kind: PictureStateKind.statusUnknown,
    title: i18n('live_play_status_unknown'),
    actions: const [PictureAction.refresh, PictureAction.switchRoom],
  ),
  _ => PictureState(
    kind: PictureStateKind.offline,
    title: i18n('stream_not_live'),
    reason: i18n('live_play_offline_hint'),
    actions: const [PictureAction.switchRoom, PictureAction.refresh],
    dim: PictureDim.cover,
  ),
};

PictureState _unplayable(LiveRoom room, Object? failure) {
  var restriction = room.isRestricted && room.isLiveNow ? room.effectiveRestriction : LiveRestriction.none;
  if (restriction == LiveRestriction.none) {
    restriction = switch (failure) {
      NeedsLogin() => LiveRestriction.needsLogin,
      RegionBlocked() => LiveRestriction.regionBlocked,
      StreamUnavailable() => LiveRestriction.unplayable,
      _ => LiveRestriction.none,
    };
  }
  const retryOrSwitch = [PictureAction.retry, PictureAction.switchRoom];
  return switch (restriction) {
    LiveRestriction.none => PictureState(
      kind: PictureStateKind.noStream,
      title: failureText(failure),
      actions: retryOrSwitch,
      dim: PictureDim.cover,
    ),
    LiveRestriction.unplayable => PictureState(
      kind: PictureStateKind.noStream,
      title: restrictionReason(LiveRestriction.unplayable),
      actions: retryOrSwitch,
      dim: PictureDim.cover,
    ),
    LiveRestriction.needsLogin => PictureState(
      kind: PictureStateKind.restricted,
      title: restrictionReason(restriction),
      actions: const [PictureAction.login, PictureAction.retry],
      dim: PictureDim.cover,
    ),
    LiveRestriction.regionBlocked => PictureState(
      kind: PictureStateKind.restricted,
      title: restrictionReason(restriction),
      actions: retryOrSwitch,
      dim: PictureDim.cover,
    ),
    LiveRestriction.paid ||
    LiveRestriction.subscribersOnly ||
    LiveRestriction.private ||
    LiveRestriction.appOnly ||
    LiveRestriction.password ||
    LiveRestriction.adult => PictureState(
      kind: PictureStateKind.restricted,
      title: restrictionReason(restriction),
      actions: room.platform == SiteIds.iptv
          ? retryOrSwitch
          : const [PictureAction.openInPlatform, PictureAction.switchRoom],
      dim: PictureDim.cover,
    ),
  };
}
