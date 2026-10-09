import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/features/live_play/local_interaction/logic/local_catalog.dart';
import 'package:pure_live/features/live_play/local_interaction/logic/local_growth.dart';
import 'package:pure_live/features/live_play/local_interaction/logic/local_interaction.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';

/// A gift banner on the picture; [serial] tells two banners of the same
/// gift apart (the new one replaces the old one and starts afresh).
@immutable
final class LocalGiftShow {
  /// Creates the banner of [message].
  const new(this.message, this.serial);

  /// The gift's message.
  final LiveMessage message;

  /// Counts the banners of the room.
  final int serial;
}

/// The local interaction inside one live room: sending local danmaku and
/// gifts into the room's chat list and over its picture, and the gift banner
/// (3.x `LivePlayController.emitLocalMessage`, `localGiftEffect`).
///
/// U.2k K1 (A): every composer shows a message at once (3.x's composers
/// waited 2 s and said so; its sheet did not). When the danmaku over the
/// picture are off, the first message of the room says it only joined the
/// chat list.
///
/// D08.1: what is sent is recorded with the room; entering the room puts
/// the local danmaku sent there in the last [replayWindow] back at the top
/// of the chat list ([replayCount] at most, "之前发的", not over the
/// picture) while "进房放回" is on.
final class LocalRoomSession {
  /// Creates the session of [room] and starts putting back what was sent
  /// there before ([events]: the stored history; none in previews).
  ///
  /// D08.3: entering checks in for the day, and the room's player counts
  /// the time it plays ([LocalRoomWatch], [periodic] its tick).
  new({
    required this.interaction,
    required this.room,
    required this.overlayShown,
    required this.toast,
    LocalEventStore? events,
    DateTime Function()? now,
    LocalTimerFactory? periodic,
    this.effectDuration = const Duration(seconds: 3),
  }) {
    if (events != null) unawaited(_replay(events, (now ?? DateTime.now)()));
    LocalRoomWatch.of(interaction, room.session, periodic: periodic)
      ..place = (() => place)
      ..toast = toast;
    final before = interaction.level;
    interaction.checkIn(place: place);
    _announce(before);
  }

  /// How far back entering a room looks (D08.1 c6).
  static const Duration replayWindow = Duration(hours: 24);

  /// The most local danmaku put back.
  static const int replayCount = 20;

  /// The profile, coins and style.
  final LocalInteraction interaction;

  /// The room.
  final LiveRoomController room;

  /// Whether danmaku fly over the picture now (`enableDanmakuDisplay` and
  /// not `hideDanmaku`).
  final bool Function() overlayShown;

  /// Shows a short message.
  final void Function(String message) toast;

  /// How long a gift banner stays (3.x: 3 s).
  final Duration effectDuration;

  /// The gift banner on the picture, or null.
  final ValueNotifier<LocalGiftShow?> giftEffect = ValueNotifier(null);

  Timer? _effectTimer;
  int _serial = 0;
  bool _overlayHinted = false;
  bool _disposed = false;

  /// The room's platform (its pack, gifts and badge).
  String get platform => room.room.platform;

  /// The room now, as the history records it.
  LocalPlace get place {
    final current = room.room;
    final name = current.nick.trim().isNotEmpty ? current.nick.trim() : current.title.trim();
    return (platform: current.platform, roomId: current.roomId, roomName: name);
  }

  /// Puts back what was sent in this room before [entered] (not what this
  /// visit sends meanwhile). The room hears of it even with nothing to put
  /// back: a room the floating window hands back to a new session holds this
  /// visit's lines already.
  Future<void> _replay(LocalEventStore events, DateTime entered) async {
    bool wanted() => interaction.enabled && interaction.replayOnEnter;
    final here = room.room;
    var sent = const <LocalEvent>[];
    if (wanted()) {
      try {
        sent = await events.recentChats(
          platform: here.platform,
          roomId: here.roomId,
          since: entered.subtract(replayWindow),
          before: entered,
          count: replayCount,
        );
      } on Object {
        // Nothing comes back this time.
      }
    }
    if (_disposed) return;
    room.replayLocal([
      if (wanted())
        for (final event in sent) interaction.replayed(event, platform: here.platform),
    ]);
  }

  /// Sends [text] as a local danmaku; false when there is nothing to send
  /// or the interaction is off.
  bool sendChat(String text) {
    if (_disposed || !interaction.enabled || text.trim().isEmpty) return false;
    final message = interaction.createChat(text, platform: platform);
    _deliver(message);
    final here = place;
    interaction.recordChat(message.message, here);
    final before = interaction.level;
    interaction.rewardChat(place: here);
    _announce(before);
    return true;
  }

  /// Sends [gift]; false (and "体验币余额不足") when the coins do not cover
  /// it.
  bool sendGift(LocalGift gift) {
    if (_disposed) return false;
    final before = interaction.level;
    final message = interaction.sendGift(gift, platform: platform, place: place);
    if (message == null) {
      if (interaction.enabled) toast(i18n('local_coins_insufficient'));
      return false;
    }
    _deliver(message);
    _announce(before);
    if (LocalGiftData.of(message)?.effect ?? false) {
      _effectTimer?.cancel();
      giftEffect.value = LocalGiftShow(message, ++_serial);
      _effectTimer = Timer(effectDuration, () {
        if (!_disposed) giftEffect.value = null;
      });
    }
    return true;
  }

  void _deliver(LiveMessage message) {
    final fly = interaction.showAsDanmaku;
    room.addLocal(message, fly: fly);
    if (fly && !overlayShown() && !_overlayHinted) {
      _overlayHinted = true;
      toast(i18n('local_overlay_off_hint'));
    }
  }

  /// "本地等级升到 Lv.N" when the level rose above [before] (D08.3).
  void _announce(int before) => announceLocalLevel(interaction, before, toast);

  /// Stops the banner's timer. The watch time goes on while the player
  /// plays (the in-app floating window); leaving the room stops the player,
  /// which settles it.
  void dispose() {
    _disposed = true;
    _effectTimer?.cancel();
    giftEffect.dispose();
  }
}

/// Says "本地等级升到 Lv.N" through [toast] when [interaction]'s level rose
/// above [before] while growth is on (D08.3 c1: off, sending is as before).
void announceLocalLevel(LocalInteraction interaction, int before, void Function(String message) toast) {
  final level = interaction.level;
  if (level > before && interaction.growing) toast(i18n('local_level_up', args: {'level': '$level'}));
}

/// The watch time of one room player (D08.3 c2): it counts while the player
/// plays (not while it opens, buffers, is paused or stopped), the app is on
/// the screen or in picture-in-picture (Flutter reports the system
/// picture-in-picture as inactive) and local growth is on. One per player,
/// so a room handed to the in-app floating window carries on, and a room
/// page opened again on the same player picks it up; the player's end (the
/// room left, the floating window closed) settles it.
///
/// It does not start anything in the background: the app hidden stops the
/// count and stores it. Within a run of counting, a minute's tick hands the
/// time to [LocalInteraction.watched], which writes only when ten minutes
/// are complete; stopping stores the rest ([LocalInteraction.settleWatch]).
/// A tick past midnight also checks in for the new day.
final class LocalRoomWatch {
  new _(this.interaction, this._player, LocalTimerFactory? periodic) {
    _clock = LocalWatchTime(
      onWatched: _watched,
      onSettle: interaction.settleWatch,
      now: interaction.now,
      periodic: periodic,
    );
    _states = _player.states.listen((_) => _update(), onDone: _end);
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        _state = state;
        _update();
      },
    );
    interaction.addListener(_update);
    _update();
  }

  /// The watch of [player] for [interaction]: the one it has, or a new one.
  factory of(LocalInteraction interaction, PlaybackSession player, {LocalTimerFactory? periodic}) {
    final current = _watches[player];
    if (current != null && !current._ended && identical(current.interaction, interaction)) return current;
    current?._end();
    return _watches[player] = LocalRoomWatch._(interaction, player, periodic);
  }

  static final Expando<LocalRoomWatch> _watches = Expando('LocalRoomWatch');

  /// What the watch time goes to.
  final LocalInteraction interaction;

  final PlaybackSession _player;
  late final LocalWatchTime _clock;
  late final StreamSubscription<PlaybackState> _states;
  late final AppLifecycleListener _lifecycle;
  AppLifecycleState? _state = WidgetsBinding.instance.lifecycleState;
  bool _ended = false;

  /// The room the player plays now (its level entries name it); the last
  /// room session sets it.
  LocalPlace Function()? place;

  /// Shows "本地等级升到 Lv.N"; the last room session sets it.
  void Function(String message)? toast;

  /// Whether the time counts now.
  bool get counting => _clock.counting;

  void _update() {
    if (_ended) return;
    final front = switch (_state) {
      null || AppLifecycleState.resumed || AppLifecycleState.inactive => true,
      _ => false,
    };
    _clock.update(counting: interaction.growing && front && _player.state.status == PlaybackStatus.playing);
  }

  void _watched(DateTime from, DateTime to) {
    final here = place?.call();
    final before = interaction.level;
    interaction
      ..watched(from, to, place: here)
      ..checkIn(place: here);
    if (toast case final say?) announceLocalLevel(interaction, before, say);
  }

  void _end() {
    if (_ended) return;
    _ended = true;
    _clock.dispose();
    unawaited(_states.cancel());
    _lifecycle.dispose();
    interaction.removeListener(_update);
  }
}
