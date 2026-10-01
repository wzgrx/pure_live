import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';

/// How a room's picture is treated (3.x `PortraitOrientationOverride`):
/// as the stream reports it, or forced to portrait or landscape.
enum RoomOrientation {
  /// Follow the stream's own size.
  automatic,

  /// Treat the stream as portrait.
  portrait,

  /// Treat the stream as landscape.
  landscape,
}

/// Whether a stream is laid out as portrait: [orientation] wins over what
/// the player [detected].
bool isPortraitLayout(RoomOrientation orientation, {required bool detected}) => switch (orientation) {
  RoomOrientation.portrait => true,
  RoomOrientation.landscape => false,
  RoomOrientation.automatic => detected,
};

/// The orientation chosen for one room (3.x `portraitOverrideForRoom` and
/// `setPortraitOverrideForRoom`): kept in `portraitRoomOverrides` under the
/// room's identity when `rememberPortraitRoomOverride` is on, else only
/// until the app closes.
final class RoomOrientationChoice extends ChangeNotifier {
  /// The choice of [room].
  new({required this.settings, required this.room});

  /// Where remembered choices are kept.
  final SettingsStore settings;

  /// The room.
  final LiveRoom room;

  /// Choices made with "remember" off, for this run of the app (3.x
  /// `_sessionPortraitRoomOverrides`).
  static final Map<String, RoomOrientation> _session = {};

  /// Forgets the choices made for this run (tests).
  @visibleForTesting
  static void clearSession() => _session.clear();

  /// The current choice.
  RoomOrientation get value {
    final key = room.identityKey;
    final session = _session[key];
    if (session != null) return session;
    final stored = settings.get(Settings.portraitRoomOverrides)[key];
    return RoomOrientation.values.asNameMap()[stored] ?? RoomOrientation.automatic;
  }

  /// Whether choices are remembered for the next visit.
  bool get remember => settings.get(Settings.rememberPortraitRoomOverride);

  /// Turns "记住单个直播间方向" on or off at once (U.2b change 10: 3.x kept the
  /// switch as a draft until an option was tapped): the room's current
  /// choice moves between this run and the remembered ones.
  Future<void> setRemember({required bool remember}) => choose(value, remember: remember);

  /// Chooses [value]; [remember] keeps it for later visits (and becomes the
  /// default for the next choice, as 3.x's dialog did).
  Future<void> choose(RoomOrientation value, {required bool remember}) async {
    final key = room.identityKey;
    _session.remove(key);
    final stored = Map<String, Object?>.of(settings.get(Settings.portraitRoomOverrides));
    if (remember) {
      if (value == RoomOrientation.automatic) {
        stored.remove(key);
      } else {
        stored[key] = value.name;
      }
    } else {
      stored.remove(key);
      if (value != RoomOrientation.automatic) _session[key] = value;
    }
    await settings.set(Settings.rememberPortraitRoomOverride, remember);
    await settings.set(Settings.portraitRoomOverrides, stored);
    notifyListeners();
  }
}
