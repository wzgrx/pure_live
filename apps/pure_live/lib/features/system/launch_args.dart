import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live_app/core/sites.dart';

/// Command-line arguments the app understands (F-APP-04, F-WIN-01, F-WIN-02).
///
/// Arguments arrive from shortcuts, other programs and forwarded second
/// launches, so only the exact forms the new-window launcher writes are
/// accepted; everything else is ignored. No argument names a file: a new
/// window reads the shared data root and the encrypted secret store instead
/// of a hand-off file (REG-STORE-024).
@immutable
final class LaunchArgs {
  /// Creates arguments.
  const new({this.secondaryWindow = false, this.openRoom});

  /// Parses [args]; unknown or malformed arguments are dropped. Only rooms of
  /// [platforms] are accepted.
  factory parse(List<String> args, {Iterable<String> platforms = platformOrder}) {
    var secondary = false;
    RoomRef? room;
    for (final arg in args) {
      if (arg == instanceFlag) {
        secondary = true;
      } else if (room == null && arg.startsWith(openRoomPrefix)) {
        room = parseRoom(arg.substring(openRoomPrefix.length), platforms: platforms);
      }
    }
    return LaunchArgs(secondaryWindow: secondary, openRoom: room);
  }

  /// Marks an extra window started by "新窗口打开" (F-WIN-02).
  static const instanceFlag = '--instance';

  /// Prefix of the room to open: `--open-room=platform:roomId` (F-APP-04).
  static const openRoomPrefix = '--open-room=';

  static final _roomId = RegExp(r'^[A-Za-z0-9_.\-]{1,64}$');

  /// Parses `platform:roomId`; null unless the platform is one of
  /// [platforms] and the room id is 1–64 letters, digits, `_`, `.` or `-`.
  static RoomRef? parseRoom(String value, {Iterable<String> platforms = platformOrder}) {
    final separator = value.indexOf(':');
    if (separator <= 0) return null;
    final platform = value.substring(0, separator);
    final roomId = value.substring(separator + 1);
    if (!platforms.contains(platform) || !_roomId.hasMatch(roomId)) return null;
    try {
      return RoomRef(platform, roomId);
    } on FormatException {
      return null;
    }
  }

  /// The arguments of a new window showing [room].
  static List<String> forNewWindow(RoomRef room) => [instanceFlag, '$openRoomPrefix${room.key}'];

  /// An extra window: it does not take part in single-instance forwarding,
  /// has no tray icon, does not remember the window placement and exits when
  /// closed.
  final bool secondaryWindow;

  /// The room to open after the first frame.
  final RoomRef? openRoom;

  @override
  bool operator ==(Object other) =>
      other is LaunchArgs && other.secondaryWindow == secondaryWindow && other.openRoom == openRoom;

  @override
  int get hashCode => Object.hash(secondaryWindow, openRoom);

  @override
  String toString() => 'LaunchArgs(secondary: $secondaryWindow, room: ${openRoom?.key})';
}

/// The arguments this process started with; main() overrides it.
final launchArgsProvider = Provider<LaunchArgs>((ref) => const LaunchArgs());

/// Starts a process the way [Process.start] does.
typedef ProcessStarter = Future<Process> Function(String executable, List<String> arguments, {ProcessStartMode mode});

/// Opens a room in another window (F-WIN-02, Windows only): starts a second
/// app process with `--instance --open-room=platform:roomId`. Returns false
/// where new windows are not supported or the process did not start.
final newWindowProvider = Provider<Future<bool> Function(RoomRef room)>((ref) => openRoomInNewWindow);

/// Whether rooms can open in a new window on this platform.
bool get newWindowSupported => Platform.isWindows;

/// Starts [executable] (this app by default) with [LaunchArgs.forNewWindow].
Future<bool> openRoomInNewWindow(
  RoomRef room, {
  ProcessStarter start = Process.start,
  String? executable,
  bool? supported,
}) async {
  if (!(supported ?? newWindowSupported)) return false;
  try {
    await start(
      executable ?? Platform.resolvedExecutable,
      LaunchArgs.forNewWindow(room),
      mode: ProcessStartMode.detached,
    );
    return true;
  } on ProcessException {
    return false;
  }
}
