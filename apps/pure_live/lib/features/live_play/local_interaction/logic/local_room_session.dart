import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live/features/live_play/local_interaction/logic/local_catalog.dart';
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
final class LocalRoomSession {
  /// Creates the session of [room].
  new({
    required this.interaction,
    required this.room,
    required this.overlayShown,
    required this.toast,
    this.effectDuration = const Duration(seconds: 3),
  });

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

  /// Sends [text] as a local danmaku; false when there is nothing to send
  /// or the interaction is off.
  bool sendChat(String text) {
    if (_disposed || !interaction.enabled || text.trim().isEmpty) return false;
    _deliver(interaction.createChat(text, platform: platform));
    return true;
  }

  /// Sends [gift]; false (and "体验币余额不足") when the coins do not cover
  /// it.
  bool sendGift(LocalGift gift) {
    if (_disposed) return false;
    final message = interaction.sendGift(gift, platform: platform);
    if (message == null) {
      if (interaction.enabled) toast(i18n('local_coins_insufficient'));
      return false;
    }
    _deliver(message);
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

  /// Stops the banner's timer.
  void dispose() {
    _disposed = true;
    _effectTimer?.cancel();
    giftEffect.dispose();
  }
}
