import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:path/path.dart' as p;

/// The command line of a Windows window (3.x `WindowsMultiInstanceLauncher`).
///
/// Every extra window runs as its own process with a unique `--instance`
/// id (its own data folder and window state), may open a room right away
/// (`--open-room`) and starts from the opening window's data
/// (`--config-file`, see [NewWindowHandoff]).
final class LaunchArgs {
  /// Creates the parsed arguments.
  const new({this.instanceId = '', this.room, this.configFile});

  /// Reads [args]; anything unexpected is ignored.
  factory parse(List<String> args, {String? tempRoot}) => LaunchArgs(
    instanceId: instanceIdFromArgs(args),
    room: roomFromArgs(args),
    configFile: configFileFromArgs(args, tempRoot: tempRoot),
  );

  /// `--instance=<id>`.
  static const String instancePrefix = '--instance=';

  /// `--open-room=<base64url JSON>`.
  static const String roomPrefix = '--open-room=';

  /// `--config-file=<path>`.
  static const String configPrefix = '--config-file=';

  /// Folder prefix of hand-over files under the system temp folder.
  static const String configDirectoryPrefix = 'pure_live_instance_';

  /// The window's id; empty for the main window.
  final String instanceId;

  /// The room to open after the home page is up.
  final LiveRoom? room;

  /// The hand-over file to import, already checked by [configFileFromArgs].
  final String? configFile;

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

  /// The hand-over file, or null. Only a file the launcher could have
  /// written is accepted: `<system temp>/pure_live_instance_*/<id>.json` of
  /// this window's own id, so the main window never imports one.
  static String? configFileFromArgs(List<String> args, {String? tempRoot}) {
    final argument = args.where((item) => item.startsWith(configPrefix)).firstOrNull;
    if (argument == null) return null;
    final path = argument.substring(configPrefix.length).trim();
    final instanceId = instanceIdFromArgs(args);
    if (path.isEmpty || instanceId.isEmpty) return null;
    final normalized = p.normalize(p.absolute(path));
    final root = p.normalize(p.absolute(tempRoot ?? Directory.systemTemp.path));
    final parent = p.dirname(normalized);
    if (p.dirname(parent) != root) return null;
    if (!p.basename(parent).startsWith(configDirectoryPrefix)) return null;
    if (p.basename(normalized) != '$instanceId.json') return null;
    return normalized;
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
  static List<String> build({
    LiveRoom? room,
    String? instanceId,
    String? configFile,
    int? processId,
    int? timestampMicros,
  }) {
    final id = instanceId ?? 'window_${processId ?? pid}_${timestampMicros ?? DateTime.now().microsecondsSinceEpoch}';
    return [
      '$instancePrefix$id',
      if (configFile != null) '$configPrefix$configFile',
      if (room != null) encodeRoomArgument(room),
    ];
  }
}

/// The data a new window starts from (3.x wrote a full backup with cookies
/// in plain text to the temp folder and imported it with
/// `recoverAndDelete`, bypassing the restore lock and its checks; M9 issue
/// 12).
///
/// v4 writes the backup without secrets ([BackupService.exportAll]) and
/// adds the secrets sealed by the platform cipher (DPAPI binds them to the
/// Windows user, so only the same user's process can open them). The new
/// window imports through [BackupService.restoreAll] and deletes the file.
abstract final class NewWindowHandoff {
  /// Key of the sealed secrets in the file.
  static const String sealedKey = 'pureLiveSealedSecrets';

  /// Writes the hand-over file of window [instanceId] and returns its path.
  static Future<String> write(
    LiveStore store,
    SecretCipher cipher, {
    required String instanceId,
    Directory? tempRoot,
  }) async {
    final data = await BackupService(store).exportAll();
    final sealed = <String, String>{};
    for (final ref in await _secretRefs(store)) {
      final value = store.secrets.read(ref);
      if (value == null) continue;
      sealed[ref] = base64.encode(await cipher.seal(ref, value));
    }
    final root = tempRoot ?? Directory.systemTemp;
    final directory = await root.createTemp(LaunchArgs.configDirectoryPrefix);
    final file = File(p.join(directory.path, '$instanceId.json'));
    await BackupService.writeFile(file, {...data, sealedKey: sealed});
    return file.path;
  }

  /// Imports the hand-over [file] and deletes it (and its folder). Returns
  /// whether the import succeeded; a failed import leaves the store as it
  /// was and still deletes the file.
  static Future<bool> restore(LiveStore store, SecretCipher cipher, File file) async {
    try {
      final data = await BackupService.readFile(file);
      final sealed = data.remove(sealedKey);
      await BackupService(store).restoreAll(data);
      if (sealed is Map) {
        final secrets = <String, String?>{};
        for (final MapEntry(:key, :value) in sealed.entries) {
          if (key is! String || value is! String) continue;
          try {
            secrets[key] = await cipher.open(key, base64.decode(value));
          } on Object {
            // Another user's or a damaged value: signed out there.
          }
        }
        if (secrets.isNotEmpty) await store.secrets.writeAll(secrets);
      }
      return true;
    } on Object {
      return false;
    } finally {
      try {
        await file.parent.delete(recursive: true);
      } on FileSystemException {
        // Left for the system's temp cleanup.
      }
    }
  }

  static Future<Set<String>> _secretRefs(LiveStore store) async => {
    for (final site in store.secrets.cookieSites) SecretRefs.cookie(site),
    SecretRefs.douyuLtp0,
    SecretRefs.douyuDid,
    for (final server in await store.webdav.all()) SecretRefs.webdav(server.name),
  };
}

/// Opens a new window with this window's data (3.x
/// `WindowsMultiInstanceLauncher.launch`); [room] opens right away.
Future<void> launchNewWindow(LiveStore store, SecretCipher cipher, {LiveRoom? room}) async {
  final instanceId = 'window_${pid}_${DateTime.now().microsecondsSinceEpoch}';
  final configFile = await NewWindowHandoff.write(store, cipher, instanceId: instanceId);
  await Process.start(
    Platform.resolvedExecutable,
    LaunchArgs.build(room: room, instanceId: instanceId, configFile: configFile),
    mode: ProcessStartMode.detached,
  );
}
