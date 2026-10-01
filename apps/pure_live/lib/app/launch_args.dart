import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';

/// The command line of a desktop window (3.x `WindowsMultiInstanceLauncher`).
///
/// Every extra window runs as its own process with a unique `--instance`
/// id (its own window and log folder) and may open a room right away
/// (`--open-room`). It shares the main window's data folder: follows,
/// history, settings and sign-ins are one copy for all windows
/// (docs/ui/compare/U.13 c14; 3.x handed a copy over in `--config-file`,
/// which is ignored now).
final class LaunchArgs {
  /// Creates the parsed arguments.
  const new({this.instanceId = '', this.room});

  /// Reads [args]; anything unexpected is ignored.
  factory parse(List<String> args) => LaunchArgs(instanceId: instanceIdFromArgs(args), room: roomFromArgs(args));

  /// `--instance=<id>`.
  static const String instancePrefix = '--instance=';

  /// `--open-room=<base64url JSON>`.
  static const String roomPrefix = '--open-room=';

  /// The window's id; empty for the main window.
  final String instanceId;

  /// The room to open after the home page is up.
  final LiveRoom? room;

  /// Whether this is the main window.
  bool get isPrimary => instanceId.isEmpty;

  /// One safe path component and mutex suffix from a command-line value
  /// (shortcuts and protocol handlers can pass anything).
  static String sanitizeInstanceId(String value) {
    var result = value.replaceAll(RegExp('[^a-zA-Z0-9_.-]'), '');
    result = result.replaceAll(RegExp(r'\.{2,}'), '.');
    result = result.replaceAll(RegExp(r'^[.-]+|[.-]+$'), '');
    if (result.length > 96) result = result.substring(0, 96);
    if (result.isEmpty) return '';
    // Windows device names are reserved even with an extension.
    final stem = result.split('.').first.toUpperCase();
    if (RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$').hasMatch(stem)) result = 'instance_$result';
    return result;
  }

  /// The sanitized `--instance` value, or ''.
  static String instanceIdFromArgs(List<String> args) {
    final argument = args.where((item) => item.startsWith(instancePrefix)).firstOrNull;
    return argument == null ? '' : sanitizeInstanceId(argument.substring(instancePrefix.length));
  }

  /// The `--open-room` room, or null when missing or malformed.
  static LiveRoom? roomFromArgs(List<String> args) {
    final argument = args.where((item) => item.startsWith(roomPrefix)).firstOrNull;
    if (argument == null) return null;
    try {
      final encoded = base64Url.normalize(argument.substring(roomPrefix.length));
      final decoded = jsonDecode(utf8.decode(base64Url.decode(encoded)));
      if (decoded is! Map) return null;
      final room = LiveRoom.fromJson(decoded.cast<String, Object?>());
      if (room.roomId.isEmpty || room.platform.isEmpty || room.platform == 'unknown') return null;
      return room;
    } on FormatException {
      return null;
    }
  }

  /// `--open-room=…` for [room]: the card fields only, never the platform's
  /// response objects.
  static String encodeRoomArgument(LiveRoom room) {
    final payload = <String, Object?>{
      'roomId': room.roomId,
      'userId': room.userId,
      'title': room.title,
      'nick': room.nick,
      'avatar': room.avatar,
      'cover': room.cover,
      'area': room.area,
      'watching': room.watching,
      'audienceMetricType': room.effectiveAudienceMetricType.name,
      'popularity': room.popularity,
      'onlineViewers': room.onlineViewers,
      'totalViewers': room.totalViewers,
      'followers': room.followers,
      'platform': room.platform,
      'liveStatus': room.effectiveLiveStatus.index,
      'isRecord': room.isRecord,
      'status': room.isLiveNow,
    };
    return '$roomPrefix${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}';
  }

  /// The arguments of a new window.
  static List<String> build({LiveRoom? room, String? instanceId, int? processId, int? timestampMicros}) {
    final id = instanceId ?? 'window_${processId ?? pid}_${timestampMicros ?? DateTime.now().microsecondsSinceEpoch}';
    return ['$instancePrefix$id', if (room != null) encodeRoomArgument(room)];
  }
}

/// Starts a new window process (3.x `WindowsMultiInstanceLauncher.launch`);
/// [room] opens right away. The window shares this one's data (U.13 c14),
/// so nothing is handed over.
Future<void> startWindowProcess({LiveRoom? room}) async {
  await Process.start(Platform.resolvedExecutable, LaunchArgs.build(room: room), mode: ProcessStartMode.detached);
}

/// [startWindowProcess] for the callers written before the data was shared
/// ([store] and [cipher] are no longer needed); new code calls
/// `DesktopWindow.openNewWindow`.
Future<void> launchNewWindow(LiveStore store, SecretCipher cipher, {LiveRoom? room}) => startWindowProcess(room: room);
